/*
================================================================================
SCRIPT: 06_functions.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+
DESCRIPTION:
    Implements deterministic scalar and inline table-valued functions (ITVFs)
    for GPA calculation, prerequisite verification, and student schedules.

DESIGN & PERFORMANCE POLICIES:
    1. fn_CalculateStudentGPA:
       - Uses WITH SCHEMABINDING for deterministic execution and scalar UDF inlining.
       - Strictly weights quality points: SUM(Credits * GradePoints) / SUM(Credits).
       - Grades with IsIncludedInGPA = 0 ('W', 'I', 'P', 'NP') are excluded.
       - Returns NULL if the student has 0 GPA-eligible credits attempted.
    2. fn_CheckPrerequisitesSatisfied:
       - Evaluates prerequisite completion against academic history.
       - Evaluates prerequisites using numeric grade points:
         earnedGrade.GradePoints >= minRequiredGrade.GradePoints
       - Retakes: If any completed attempt meets or exceeds the required threshold,
         the prerequisite is satisfied.
       - Withdrawn ('W'), dropped, or incomplete ('I') records do not satisfy prerequisites.
       - Returns 1 if all prerequisites are satisfied or if none are defined.
    3. fn_GetStudentSchedule:
       - Implemented as an Inline Table-Valued Function (ITVF).
       - Eliminates scalar UDF execution overhead and seamlessly inlines into
         the caller's execution plan.
================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Function: academic.fn_CalculateStudentGPA
--    Calculates cumulative credit-weighted GPA on a 4.0 scale.
-- -----------------------------------------------------------------------------
CREATE OR ALTER FUNCTION [academic].[fn_CalculateStudentGPA] (
    @StudentID INT
)
RETURNS DECIMAL(3, 2)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @CalculatedGPA DECIMAL(3, 2);

    SELECT
        @CalculatedGPA = CAST(ROUND(
            SUM(c.Credits * gs.GradePoints) / NULLIF(SUM(c.Credits), 0),
            2
        ) AS DECIMAL(3, 2))
    FROM [academic].[Enrollments] e
    INNER JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
    INNER JOIN [academic].[Courses] c ON sec.CourseID = c.CourseID
    INNER JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade
    WHERE e.StudentID = @StudentID
      AND e.EnrollmentStatus = 'Completed'
      AND gs.IsIncludedInGPA = 1;

    RETURN @CalculatedGPA;
END;
GO

PRINT 'Function [academic].[fn_CalculateStudentGPA] created.';
GO

-- -----------------------------------------------------------------------------
-- 2. Function: academic.fn_CheckPrerequisitesSatisfied
--    Verifies whether a student has completed all required prerequisites
--    for a course with the specified minimum grade points.
-- -----------------------------------------------------------------------------
CREATE OR ALTER FUNCTION [academic].[fn_CheckPrerequisitesSatisfied] (
    @StudentID INT,
    @CourseID  INT
)
RETURNS BIT
WITH SCHEMABINDING
AS
BEGIN
    -- If course has no prerequisites defined, rule is satisfied immediately
    IF NOT EXISTS (
        SELECT 1
        FROM [academic].[CoursePrerequisites]
        WHERE CourseID = @CourseID
    )
        RETURN 1;

    -- If there exists any required prerequisite for which the student has NOT
    -- earned at least the minimum required grade points in a completed section:
    IF EXISTS (
        SELECT 1
        FROM [academic].[CoursePrerequisites] cp
        INNER JOIN [academic].[GradeScales] req_gs ON cp.MinimumGrade = req_gs.LetterGrade
        WHERE cp.CourseID = @CourseID
          AND NOT EXISTS (
              -- Search student's completed academic history for this prerequisite
              SELECT 1
              FROM [academic].[Enrollments] e
              INNER JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
              INNER JOIN [academic].[GradeScales] earned_gs ON e.LetterGrade = earned_gs.LetterGrade
              WHERE e.StudentID = @StudentID
                AND sec.CourseID = cp.PrerequisiteCourseID
                AND e.EnrollmentStatus = 'Completed'
                AND earned_gs.IsCreditBearing = 1
                AND earned_gs.GradePoints >= req_gs.GradePoints
          )
    )
        RETURN 0;

    -- All prerequisites satisfied
    RETURN 1;
END;
GO

PRINT 'Function [academic].[fn_CheckPrerequisitesSatisfied] created.';
GO

-- -----------------------------------------------------------------------------
-- 3. Function: academic.fn_GetStudentSchedule
--    Inline Table-Valued Function returning a student's active or term schedule.
-- -----------------------------------------------------------------------------
CREATE OR ALTER FUNCTION [academic].[fn_GetStudentSchedule] (
    @StudentID INT,
    @TermID    INT = NULL
)
RETURNS TABLE
AS
RETURN (
    SELECT
        s.StudentNumber,
        s.FirstName + N' ' + s.LastName AS StudentFullName,
        sec.SectionID,
        c.CourseCode,
        c.Title AS CourseTitle,
        c.Credits,
        t.TermCode,
        t.TermName,
        sec.SectionNumber,
        i.FirstName + N' ' + i.LastName AS InstructorFullName,
        sec.Classroom,
        sec.ScheduleDayTime,
        e.EnrollmentStatus,
        e.EnrollmentDate,
        e.LetterGrade
    FROM [academic].[Enrollments] e
    INNER JOIN [academic].[Students] s ON e.StudentID = s.StudentID
    INNER JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
    INNER JOIN [academic].[Courses] c ON sec.CourseID = c.CourseID
    INNER JOIN [academic].[AcademicTerms] t ON sec.TermID = t.TermID
    INNER JOIN [academic].[Instructors] i ON sec.InstructorID = i.InstructorID
    WHERE e.StudentID = @StudentID
      AND (
          (@TermID IS NOT NULL AND sec.TermID = @TermID)
          OR (@TermID IS NULL AND t.IsActive = 1)
      )
);
GO

PRINT 'Function [academic].[fn_GetStudentSchedule] created.';
PRINT '================================================================================';
PRINT '06_functions.sql executed successfully. All functions verified.';
PRINT '================================================================================';
GO
