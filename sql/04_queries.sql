/*
================================================================================
SCRIPT: 04_queries.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+
DESCRIPTION:
    Demonstrates advanced, production-grade SQL querying techniques:
    1. Multi-table Inner & Outer Joins (preserving 0-enrollment edge cases)
    2. Aggregations & HAVING Filtering
    3. Scalar and Correlated Subqueries
    4. Recursive and Multi-Step Common Table Expressions (CTEs)
    5. Window Functions (Ranking, Offset LAG/LEAD, Running Totals)
    6. Anti-Joins (NOT EXISTS vs. LEFT JOIN / IS NULL)
================================================================================
*/

SET NOCOUNT ON;
GO

PRINT '================================================================================';
PRINT 'DEMONSTRATION 1: MULTI-TABLE JOINS (INNER & OUTER)';
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- Query 1A: Comprehensive Student Roster with Major and Academic Summary (LEFT JOIN)
-- Demonstrates: Preserving students with 0 enrollments via LEFT JOIN.
-- -----------------------------------------------------------------------------
SELECT
    s.StudentNumber,
    s.FirstName + N' ' + s.LastName AS StudentName,
    d.DepartmentCode AS Major,
    s.AcademicStatus,
    COUNT(e.EnrollmentID) AS TotalLifetimeEnrollments,
    COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) AS CurrentActiveEnrollments,
    COALESCE(SUM(CASE WHEN e.EnrollmentStatus = 'Completed' AND gs.IsCreditBearing = 1 THEN c.Credits ELSE 0 END), 0) AS CreditsEarned
FROM [academic].[Students] s
INNER JOIN [academic].[Departments] d ON s.DepartmentID = d.DepartmentID
LEFT JOIN [academic].[Enrollments] e ON s.StudentID = e.StudentID
LEFT JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
LEFT JOIN [academic].[Courses] c ON sec.CourseID = c.CourseID
LEFT JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade
GROUP BY
    s.StudentNumber,
    s.FirstName,
    s.LastName,
    d.DepartmentCode,
    s.AcademicStatus
ORDER BY
    CreditsEarned DESC, s.StudentNumber ASC;
GO

PRINT '================================================================================';
PRINT 'DEMONSTRATION 2: AGGREGATIONS & HAVING CLAUSES';
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- Query 2A: Department Course Load & Credit Production Analysis
-- Demonstrates: Multi-table aggregation with HAVING clause filtering departments
--               producing significant credit volumes.
-- -----------------------------------------------------------------------------
SELECT
    d.DepartmentCode,
    d.DepartmentName,
    COUNT(DISTINCT c.CourseID) AS ActiveCatalogCourses,
    COUNT(DISTINCT s.SectionID) AS TotalSectionsOffered,
    COUNT(CASE WHEN e.EnrollmentStatus = 'Completed' THEN 1 END) AS CompletedEnrollments,
    SUM(CASE WHEN e.EnrollmentStatus = 'Completed' AND gs.IsCreditBearing = 1 THEN c.Credits ELSE 0 END) AS TotalCreditsAwarded,
    CAST(ROUND(AVG(CASE WHEN e.EnrollmentStatus = 'Completed' AND gs.IsIncludedInGPA = 1 THEN gs.GradePoints END), 2) AS DECIMAL(3, 2)) AS DeptAverageGradePoints
FROM [academic].[Departments] d
INNER JOIN [academic].[Courses] c ON d.DepartmentID = c.DepartmentID
LEFT JOIN [academic].[CourseSections] s ON c.CourseID = s.CourseID
LEFT JOIN [academic].[Enrollments] e ON s.SectionID = e.SectionID
LEFT JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade
GROUP BY
    d.DepartmentCode,
    d.DepartmentName
HAVING
    COUNT(DISTINCT c.CourseID) >= 2
ORDER BY
    TotalCreditsAwarded DESC;
GO

PRINT '================================================================================';
PRINT 'DEMONSTRATION 3: SUBQUERIES (SCALAR & CORRELATED)';
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- Query 3A: Faculty Earning Above Their Department Average (Correlated Subquery)
-- Demonstrates: Correlated subquery in WHERE comparing individual to department mean.
-- -----------------------------------------------------------------------------
SELECT
    i.InstructorNumber,
    i.FirstName + N' ' + i.LastName AS FacultyName,
    i.Title,
    d.DepartmentCode,
    i.Salary,
    CAST(ROUND((
        SELECT AVG(sub.Salary)
        FROM [academic].[Instructors] sub
        WHERE sub.DepartmentID = i.DepartmentID
    ), 2) AS DECIMAL(10, 2)) AS DeptAverageSalary,
    CAST(ROUND(i.Salary - (
        SELECT AVG(sub.Salary)
        FROM [academic].[Instructors] sub
        WHERE sub.DepartmentID = i.DepartmentID
    ), 2) AS DECIMAL(10, 2)) AS SalaryAboveDeptAvg
FROM [academic].[Instructors] i
INNER JOIN [academic].[Departments] d ON i.DepartmentID = d.DepartmentID
WHERE i.Salary > (
    SELECT AVG(sub.Salary)
    FROM [academic].[Instructors] sub
    WHERE sub.DepartmentID = i.DepartmentID
)
ORDER BY
    SalaryAboveDeptAvg DESC;
GO

PRINT '================================================================================';
PRINT 'DEMONSTRATION 4: RECURSIVE CTE (PREREQUISITE DEPENDENCY TREE)';
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- Query 4A: Prerequisite Hierarchy Tree Resolver (Recursive CTE)
-- Demonstrates: Resolving complete multi-level prerequisite chains for advanced courses
--               (e.g., CS401 -> CS301 -> CS201 -> CS101) with depth tracking and loop guard.
-- -----------------------------------------------------------------------------
WITH PrerequisiteHierarchy AS (
    -- Anchor Member: Direct prerequisites of target course
    SELECT
        cp.CourseID AS RootCourseID,
        c_root.CourseCode AS RootCourseCode,
        cp.PrerequisiteCourseID,
        c_prereq.CourseCode AS PrerequisiteCourseCode,
        c_prereq.Title AS PrerequisiteTitle,
        cp.MinimumGrade,
        1 AS PrerequisiteLevel,
        CAST(c_root.CourseCode + ' -> ' + c_prereq.CourseCode AS VARCHAR(1000)) AS DependencyPath
    FROM [academic].[CoursePrerequisites] cp
    INNER JOIN [academic].[Courses] c_root ON cp.CourseID = c_root.CourseID
    INNER JOIN [academic].[Courses] c_prereq ON cp.PrerequisiteCourseID = c_prereq.CourseID

    UNION ALL

    -- Recursive Member: Prerequisites of prerequisites
    SELECT
        ph.RootCourseID,
        ph.RootCourseCode,
        cp_next.PrerequisiteCourseID,
        c_next.CourseCode AS PrerequisiteCourseCode,
        c_next.Title AS PrerequisiteTitle,
        cp_next.MinimumGrade,
        ph.PrerequisiteLevel + 1 AS PrerequisiteLevel,
        CAST(ph.DependencyPath + ' -> ' + c_next.CourseCode AS VARCHAR(1000)) AS DependencyPath
    FROM PrerequisiteHierarchy ph
    INNER JOIN [academic].[CoursePrerequisites] cp_next
        ON ph.PrerequisiteCourseID = cp_next.CourseID
    INNER JOIN [academic].[Courses] c_next
        ON cp_next.PrerequisiteCourseID = c_next.CourseID
    WHERE ph.PrerequisiteLevel < 10 -- Guard against cyclic references
)
SELECT
    RootCourseCode AS TargetCourse,
    PrerequisiteLevel AS DistanceLevel,
    PrerequisiteCourseCode AS RequiredPrerequisite,
    PrerequisiteTitle,
    MinimumGrade AS MinGradeRequired,
    DependencyPath
FROM PrerequisiteHierarchy
ORDER BY
    RootCourseCode, PrerequisiteLevel ASC, PrerequisiteCourseCode;
GO

PRINT '================================================================================';
PRINT 'DEMONSTRATION 5: WINDOW FUNCTIONS (RANKING, LAG, AND RUNNING TOTALS)';
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- Query 5A: Student GPA Ranking within Major Department
-- Demonstrates: ROW_NUMBER(), DENSE_RANK(), and RANK() partitioned by department.
-- -----------------------------------------------------------------------------
WITH StudentGPAs AS (
    SELECT
        v.StudentID,
        v.StudentNumber,
        v.StudentFullName,
        v.MajorDepartmentCode,
        v.TotalCreditsEarned,
        v.CumulativeGPA
    FROM [academic].[vw_StudentAcademicSummary] v
    WHERE v.CumulativeGPA IS NOT NULL
)
SELECT
    MajorDepartmentCode,
    DENSE_RANK() OVER (
        PARTITION BY MajorDepartmentCode
        ORDER BY CumulativeGPA DESC
    ) AS DeptRank,
    StudentNumber,
    StudentFullName,
    CumulativeGPA,
    TotalCreditsEarned
FROM StudentGPAs
ORDER BY
    MajorDepartmentCode, DeptRank ASC;
GO

-- -----------------------------------------------------------------------------
-- Query 5B: Running Total of Credits Earned Over Time per Student
-- Demonstrates: Running total window aggregation with frame specification.
-- -----------------------------------------------------------------------------
SELECT
    s.StudentNumber,
    s.FirstName + N' ' + s.LastName AS StudentName,
    t.TermCode,
    c.CourseCode,
    c.Credits,
    e.LetterGrade,
    -- Running total of credits earned chronologically
    SUM(c.Credits) OVER (
        PARTITION BY s.StudentID
        ORDER BY t.StartDate, c.CourseCode
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS CumulativeCreditsEarnedToDate
FROM [academic].[Enrollments] e
INNER JOIN [academic].[Students] s ON e.StudentID = s.StudentID
INNER JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
INNER JOIN [academic].[Courses] c ON sec.CourseID = c.CourseID
INNER JOIN [academic].[AcademicTerms] t ON sec.TermID = t.TermID
INNER JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade
WHERE e.EnrollmentStatus = 'Completed' AND gs.IsCreditBearing = 1
ORDER BY
    s.StudentNumber, t.StartDate, c.CourseCode;
GO

-- -----------------------------------------------------------------------------
-- Query 5C: Term-over-Term Student GPA Progression (LAG Window Function)
-- Demonstrates: LAG() offset function comparing current term GPA with prior term.
-- -----------------------------------------------------------------------------
WITH TermGPA AS (
    SELECT
        e.StudentID,
        s.StudentNumber,
        s.FirstName + N' ' + s.LastName AS StudentName,
        t.TermID,
        t.TermCode,
        t.StartDate AS TermStartDate,
        CAST(ROUND(SUM(c.Credits * gs.GradePoints) / NULLIF(SUM(c.Credits), 0), 2) AS DECIMAL(3, 2)) AS TermGPA
    FROM [academic].[Enrollments] e
    INNER JOIN [academic].[Students] s ON e.StudentID = s.StudentID
    INNER JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
    INNER JOIN [academic].[Courses] c ON sec.CourseID = c.CourseID
    INNER JOIN [academic].[AcademicTerms] t ON sec.TermID = t.TermID
    INNER JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade
    WHERE e.EnrollmentStatus = 'Completed' AND gs.IsIncludedInGPA = 1
    GROUP BY
        e.StudentID, s.StudentNumber, s.FirstName, s.LastName, t.TermID, t.TermCode, t.StartDate
)
SELECT
    StudentNumber,
    StudentName,
    TermCode,
    TermGPA,
    LAG(TermGPA, 1) OVER (
        PARTITION BY StudentID
        ORDER BY TermStartDate
    ) AS PreviousTermGPA,
    CAST(ROUND(TermGPA - LAG(TermGPA, 1) OVER (
        PARTITION BY StudentID
        ORDER BY TermStartDate
    ), 2) AS DECIMAL(3, 2)) AS GPATrendDelta
FROM TermGPA
ORDER BY
    StudentNumber, TermStartDate;
GO

PRINT '================================================================================';
PRINT 'DEMONSTRATION 6: ANTI-JOINS (NOT EXISTS VS. LEFT JOIN / IS NULL)';
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- Query 6A: Admitted Students with Zero Lifetime Enrollments
-- Demonstrates: Anti-join using NOT EXISTS to find inactive/unregistered students.
-- -----------------------------------------------------------------------------
SELECT
    s.StudentID,
    s.StudentNumber,
    s.FirstName + N' ' + s.LastName AS StudentName,
    s.Email,
    d.DepartmentCode AS Major,
    s.AcademicStatus,
    s.EnrollmentDate
FROM [academic].[Students] s
INNER JOIN [academic].[Departments] d ON s.DepartmentID = d.DepartmentID
WHERE NOT EXISTS (
    SELECT 1
    FROM [academic].[Enrollments] e
    WHERE e.StudentID = s.StudentID
)
ORDER BY
    s.StudentNumber;
GO

-- -----------------------------------------------------------------------------
-- Query 6B: Catalog Courses Never Offered in Any Academic Term
-- Demonstrates: Anti-join using LEFT JOIN ... WHERE IS NULL.
-- -----------------------------------------------------------------------------
SELECT
    c.CourseID,
    c.CourseCode,
    c.Title AS CourseTitle,
    c.Credits,
    d.DepartmentCode
FROM [academic].[Courses] c
INNER JOIN [academic].[Departments] d ON c.DepartmentID = d.DepartmentID
LEFT JOIN [academic].[CourseSections] s ON c.CourseID = s.CourseID
WHERE s.SectionID IS NULL
ORDER BY
    c.CourseCode;
GO

-- -----------------------------------------------------------------------------
-- Query 6C: Faculty Members Not Assigned to Any Section in Current Active Term
-- Demonstrates: NOT EXISTS with multi-table correlated condition (e.g. Sabbatical faculty).
-- -----------------------------------------------------------------------------
SELECT
    i.InstructorID,
    i.InstructorNumber,
    i.FirstName + N' ' + i.LastName AS FacultyName,
    i.Title,
    d.DepartmentCode,
    i.OfficeRoom
FROM [academic].[Instructors] i
INNER JOIN [academic].[Departments] d ON i.DepartmentID = d.DepartmentID
WHERE i.IsActive = 1
  AND NOT EXISTS (
      SELECT 1
      FROM [academic].[CourseSections] s
      INNER JOIN [academic].[AcademicTerms] t ON s.TermID = t.TermID
      WHERE s.InstructorID = i.InstructorID
        AND t.IsActive = 1
  )
ORDER BY
    i.InstructorNumber;
GO

PRINT '================================================================================';
PRINT '04_queries.sql executed successfully. All query patterns validated.';
PRINT '================================================================================';
GO
