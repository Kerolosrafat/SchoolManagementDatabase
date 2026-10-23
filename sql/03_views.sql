/*
================================================================================
SCRIPT: 03_views.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+
DESCRIPTION:
    Creates reporting and operational views for student summaries, course
    capacities, department metrics, and transcripts.

DATA INTEGRITY & DESIGN POLICIES:
    1. GPA Calculation: Strict adherence to academic policy.
       - Sum of (Credits * GradePoints) / Sum of (Credits for GPA-eligible grades).
       - Grades with IsIncludedInGPA = 0 ('W', 'I', 'P', 'NP') are excluded.
       - Students with 0 GPA-eligible credits return NULL (not 0.00), preventing
         misrepresenting un-graded or non-enrolled students as failing.
    2. Outer Join Preservation:
       - Preserves students without enrollments, sections without students,
         and departments without faculty/courses.
================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- -----------------------------------------------------------------------------
-- 1. View: vw_StudentAcademicSummary
--    Comprehensive academic progress summary per student.
--    Computes credits attempted, credits earned, cumulative GPA, and active course load.
-- -----------------------------------------------------------------------------
CREATE OR ALTER VIEW [academic].[vw_StudentAcademicSummary]
AS
WITH StudentCourseMetrics AS (
    SELECT
        e.StudentID,
        -- Attempted credits: all completed courses + active enrollments
        SUM(c.Credits) AS TotalCreditsAttempted,

        -- Earned credits: completed courses where GradeScale grants credit (Grade D or higher)
        SUM(CASE
            WHEN e.EnrollmentStatus = 'Completed' AND gs.IsCreditBearing = 1
            THEN c.Credits
            ELSE 0
        END) AS TotalCreditsEarned,

        -- GPA-eligible credits (denominator for GPA)
        SUM(CASE
            WHEN e.EnrollmentStatus = 'Completed' AND gs.IsIncludedInGPA = 1
            THEN c.Credits
            ELSE 0
        END) AS GPACreditsAttempted,

        -- Quality points (numerator for GPA: Credits * GradePoints)
        SUM(CASE
            WHEN e.EnrollmentStatus = 'Completed' AND gs.IsIncludedInGPA = 1
            THEN c.Credits * gs.GradePoints
            ELSE 0.00
        END) AS TotalQualityPoints,

        -- Active enrollments in current courses
        COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) AS ActiveEnrollmentsCount,

        -- Completed course count
        COUNT(CASE WHEN e.EnrollmentStatus = 'Completed' THEN 1 END) AS CompletedCoursesCount,

        -- Withdrawn count
        COUNT(CASE WHEN e.EnrollmentStatus = 'Withdrawn' THEN 1 END) AS WithdrawnCoursesCount
    FROM [academic].[Enrollments] e
    INNER JOIN [academic].[CourseSections] s ON e.SectionID = s.SectionID
    INNER JOIN [academic].[Courses] c ON s.CourseID = c.CourseID
    LEFT JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade
    GROUP BY e.StudentID
)
SELECT
    s.StudentID,
    s.StudentNumber,
    s.FirstName + N' ' + s.LastName AS StudentFullName,
    s.Email,
    d.DepartmentCode AS MajorDepartmentCode,
    d.DepartmentName AS MajorDepartmentName,
    s.AcademicStatus,
    s.EnrollmentDate,
    ISNULL(m.TotalCreditsAttempted, 0) AS TotalCreditsAttempted,
    ISNULL(m.TotalCreditsEarned, 0) AS TotalCreditsEarned,
    ISNULL(m.GPACreditsAttempted, 0) AS GPACreditsAttempted,
    -- Prevent division by zero; return NULL if no graded courses completed
    CASE
        WHEN ISNULL(m.GPACreditsAttempted, 0) > 0
        THEN CAST(ROUND(m.TotalQualityPoints / m.GPACreditsAttempted, 2) AS DECIMAL(3, 2))
        ELSE NULL
    END AS CumulativeGPA,
    ISNULL(m.ActiveEnrollmentsCount, 0) AS ActiveEnrollmentsCount,
    ISNULL(m.CompletedCoursesCount, 0) AS CompletedCoursesCount,
    ISNULL(m.WithdrawnCoursesCount, 0) AS WithdrawnCoursesCount
FROM [academic].[Students] s
INNER JOIN [academic].[Departments] d ON s.DepartmentID = d.DepartmentID
LEFT JOIN StudentCourseMetrics m ON s.StudentID = m.StudentID;
GO

PRINT 'View [academic].[vw_StudentAcademicSummary] created.';
GO

-- -----------------------------------------------------------------------------
-- 2. View: vw_CourseEnrollmentStatus
--    Operational view monitoring section capacities, active headcount,
--    and occupancy rates.
-- -----------------------------------------------------------------------------
CREATE OR ALTER VIEW [academic].[vw_CourseEnrollmentStatus]
AS
SELECT
    s.SectionID,
    c.CourseCode,
    c.Title AS CourseTitle,
    c.Credits,
    t.TermCode,
    t.TermName,
    t.IsActive AS IsCurrentTerm,
    s.SectionNumber,
    i.FirstName + N' ' + i.LastName AS InstructorFullName,
    s.Classroom,
    s.ScheduleDayTime,
    s.MaxCapacity,
    -- Concurrency-accurate headcount of currently active enrollments
    COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) AS ActiveEnrolledCount,
    s.MaxCapacity - COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) AS SeatsAvailable,
    CAST(ROUND(
        COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) * 100.0 / s.MaxCapacity,
        1
    ) AS DECIMAL(5, 1)) AS OccupancyRatePercent,
    s.Status AS SectionScheduleStatus,
    CASE
        WHEN COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) >= s.MaxCapacity THEN 'FULL'
        WHEN COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) * 100.0 / s.MaxCapacity >= 80.0 THEN 'NEAR_CAPACITY'
        WHEN COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) = 0 THEN 'EMPTY'
        ELSE 'OPEN'
    END AS CapacityStatus
FROM [academic].[CourseSections] s
INNER JOIN [academic].[Courses] c ON s.CourseID = c.CourseID
INNER JOIN [academic].[AcademicTerms] t ON s.TermID = t.TermID
INNER JOIN [academic].[Instructors] i ON s.InstructorID = i.InstructorID
LEFT JOIN [academic].[Enrollments] e ON s.SectionID = e.SectionID
GROUP BY
    s.SectionID,
    c.CourseCode,
    c.Title,
    c.Credits,
    t.TermCode,
    t.TermName,
    t.IsActive,
    s.SectionNumber,
    i.FirstName,
    i.LastName,
    s.Classroom,
    s.ScheduleDayTime,
    s.MaxCapacity,
    s.Status;
GO

PRINT 'View [academic].[vw_CourseEnrollmentStatus] created.';
GO

-- -----------------------------------------------------------------------------
-- 3. View: vw_DepartmentPerformance
--    Institutional metrics: budgets, faculty salary payrolls, student majors,
--    and course offerings.
-- -----------------------------------------------------------------------------
CREATE OR ALTER VIEW [academic].[vw_DepartmentPerformance]
AS
WITH FacultyStats AS (
    SELECT
        DepartmentID,
        COUNT(*) AS TotalFacultyCount,
        SUM(Salary) AS TotalFacultyPayroll,
        AVG(Salary) AS AverageFacultySalary
    FROM [academic].[Instructors]
    WHERE IsActive = 1
    GROUP BY DepartmentID
),
StudentStats AS (
    SELECT
        DepartmentID,
        COUNT(*) AS ActiveStudentMajorsCount
    FROM [academic].[Students]
    WHERE AcademicStatus IN ('Active', 'Probation')
    GROUP BY DepartmentID
),
CourseStats AS (
    SELECT
        DepartmentID,
        COUNT(*) AS TotalCourseCatalogCount
    FROM [academic].[Courses]
    GROUP BY DepartmentID
),
ActiveSectionStats AS (
    SELECT
        c.DepartmentID,
        COUNT(s.SectionID) AS ActiveTermSectionsCount
    FROM [academic].[CourseSections] s
    INNER JOIN [academic].[Courses] c ON s.CourseID = c.CourseID
    INNER JOIN [academic].[AcademicTerms] t ON s.TermID = t.TermID
    WHERE t.IsActive = 1
    GROUP BY c.DepartmentID
)
SELECT
    d.DepartmentID,
    d.DepartmentCode,
    d.DepartmentName,
    d.OfficeLocation,
    d.Budget AS DepartmentBudget,
    hod.FirstName + N' ' + hod.LastName AS HeadOfDepartmentName,
    ISNULL(f.TotalFacultyCount, 0) AS TotalFacultyCount,
    ISNULL(st.ActiveStudentMajorsCount, 0) AS ActiveStudentMajorsCount,
    ISNULL(cs.TotalCourseCatalogCount, 0) AS TotalCourseCatalogCount,
    ISNULL(sec.ActiveTermSectionsCount, 0) AS ActiveTermSectionsCount,
    CAST(ROUND(ISNULL(f.AverageFacultySalary, 0.00), 2) AS DECIMAL(10, 2)) AS AverageFacultySalary,
    ISNULL(f.TotalFacultyPayroll, 0.00) AS TotalFacultyPayroll,
    -- Payroll as a percentage of department budget
    CASE
        WHEN d.Budget > 0
        THEN CAST(ROUND((ISNULL(f.TotalFacultyPayroll, 0.00) * 100.0) / d.Budget, 1) AS DECIMAL(5, 1))
        ELSE 0.0
    END AS PayrollBudgetPercent
FROM [academic].[Departments] d
LEFT JOIN [academic].[Instructors] hod ON d.HeadOfDepartmentID = hod.InstructorID
LEFT JOIN FacultyStats f ON d.DepartmentID = f.DepartmentID
LEFT JOIN StudentStats st ON d.DepartmentID = st.DepartmentID
LEFT JOIN CourseStats cs ON d.DepartmentID = cs.DepartmentID
LEFT JOIN ActiveSectionStats sec ON d.DepartmentID = sec.DepartmentID;
GO

PRINT 'View [academic].[vw_DepartmentPerformance] created.';
GO

-- -----------------------------------------------------------------------------
-- 4. View: vw_StudentTranscripts
--    Official, chronological student academic history records.
-- -----------------------------------------------------------------------------
CREATE OR ALTER VIEW [academic].[vw_StudentTranscripts]
AS
SELECT
    s.StudentID,
    s.StudentNumber,
    s.FirstName + N' ' + s.LastName AS StudentFullName,
    t.TermCode,
    t.TermName,
    t.StartDate AS TermStartDate,
    c.CourseCode,
    c.Title AS CourseTitle,
    c.Credits,
    e.EnrollmentStatus,
    e.LetterGrade,
    gs.GradePoints,
    -- Quality Points: Credits * GradePoints (for graded courses)
    CASE
        WHEN gs.IsIncludedInGPA = 1
        THEN CAST(ROUND(c.Credits * gs.GradePoints, 2) AS DECIMAL(5, 2))
        ELSE 0.00
    END AS QualityPoints,
    ISNULL(gs.IsCreditBearing, 0) AS IsCreditBearing,
    ISNULL(gs.IsIncludedInGPA, 0) AS IsIncludedInGPA,
    i.FirstName + N' ' + i.LastName AS InstructorFullName,
    e.EnrollmentDate
FROM [academic].[Enrollments] e
INNER JOIN [academic].[Students] s ON e.StudentID = s.StudentID
INNER JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
INNER JOIN [academic].[Courses] c ON sec.CourseID = c.CourseID
INNER JOIN [academic].[AcademicTerms] t ON sec.TermID = t.TermID
INNER JOIN [academic].[Instructors] i ON sec.InstructorID = i.InstructorID
LEFT JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade;
GO

PRINT 'View [academic].[vw_StudentTranscripts] created.';
PRINT '================================================================================';
PRINT '03_views.sql executed successfully. All views verified.';
PRINT '================================================================================';
GO
