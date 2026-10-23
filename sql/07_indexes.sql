/*
================================================================================
SCRIPT: 07_indexes.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+
DESCRIPTION:
    Implements a justified, workload-aligned indexing strategy to optimize
    critical query paths across reporting views, procedures, and functions:
    1. Section live headcount & capacity verification (usp_EnrollStudent)
    2. Student transcript and GPA calculation covering lookups (fn_CalculateStudentGPA)
    3. Academic term and section status lookups (vw_CourseEnrollmentStatus)
    4. Reverse prerequisite tree traversal (04_queries.sql recursive CTE)
    5. Foreign key columns in multi-table joins (Departments, Students, Courses)
    6. Audit trail lookups by student and section

SAFETY & IDEMPOTENCY:
    - Checks sys.indexes before creating each index to avoid redundant DDL.
    - Preserves existing PK and UNIQUE constraints.
    - Safe to execute repeatedly without dropping or rebuilding valid indexes.
================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '================================================================================';
PRINT 'STARTING INDEX DEPLOYMENT: SchoolDB';
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- 1. Table: academic.Enrollments
-- Index: IX_Enrollments_SectionID_Status
--
-- JUSTIFICATION:
-- - Supports: academic.usp_EnrollStudent (concurrency capacity check under lock),
--             academic.vw_CourseEnrollmentStatus (active headcount per section),
--             academic.usp_GetCourseRoster (roster retrieval by section).
-- - Problem Solved: The existing unique constraint UQ_Enrollments_Student_Section
--   has StudentID as its leading key. Searching by SectionID forces an index scan.
-- - Column Order: SectionID (equality filter / join) -> EnrollmentStatus (status filter).
-- - Included Columns: StudentID, LetterGrade, EnrollmentDate (covers roster queries).
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Enrollments_SectionID_Status'
      AND object_id = OBJECT_ID(N'academic.Enrollments')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Enrollments_SectionID_Status]
    ON [academic].[Enrollments] ([SectionID], [EnrollmentStatus])
    INCLUDE ([StudentID], [LetterGrade], [EnrollmentDate]);

    PRINT 'Index [IX_Enrollments_SectionID_Status] created on [academic].[Enrollments].';
END
ELSE
BEGIN
    PRINT 'Index [IX_Enrollments_SectionID_Status] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 2. Table: academic.Enrollments
-- Index: IX_Enrollments_StudentID_Status
--
-- JUSTIFICATION:
-- - Supports: academic.fn_CalculateStudentGPA (credit-weighted GPA calculation),
--             academic.vw_StudentAcademicSummary (lifetime credits attempted & earned),
--             academic.usp_GetStudentTranscript (chronological course history).
-- - Problem Solved: Eliminates clustered index key lookups when evaluating a student's
--   completed academic history.
-- - Column Order: StudentID (equality seek) -> EnrollmentStatus (status filter).
-- - Included Columns: SectionID, LetterGrade, EnrollmentDate.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Enrollments_StudentID_Status'
      AND object_id = OBJECT_ID(N'academic.Enrollments')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Enrollments_StudentID_Status]
    ON [academic].[Enrollments] ([StudentID], [EnrollmentStatus])
    INCLUDE ([SectionID], [LetterGrade], [EnrollmentDate]);

    PRINT 'Index [IX_Enrollments_StudentID_Status] created on [academic].[Enrollments].';
END
ELSE
BEGIN
    PRINT 'Index [IX_Enrollments_StudentID_Status] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 3. Table: academic.CourseSections
-- Index: IX_CourseSections_TermID_Status
--
-- JUSTIFICATION:
-- - Supports: academic.vw_CourseEnrollmentStatus (filtering active term sections),
--             academic.fn_GetStudentSchedule (term-specific schedule lookups),
--             04_queries.sql (Query 2A & 6C term section aggregations).
-- - Problem Solved: The existing unique constraint has CourseID as leading key.
--   Filtering sections strictly by TermID and Status requires a full index scan.
-- - Column Order: TermID (equality filter) -> Status (administrative status).
-- - Included Columns: CourseID, InstructorID, SectionNumber, MaxCapacity, Classroom, ScheduleDayTime.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_CourseSections_TermID_Status'
      AND object_id = OBJECT_ID(N'academic.CourseSections')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_CourseSections_TermID_Status]
    ON [academic].[CourseSections] ([TermID], [Status])
    INCLUDE ([CourseID], [InstructorID], [SectionNumber], [MaxCapacity], [Classroom], [ScheduleDayTime]);

    PRINT 'Index [IX_CourseSections_TermID_Status] created on [academic].[CourseSections].';
END
ELSE
BEGIN
    PRINT 'Index [IX_CourseSections_TermID_Status] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 4. Table: academic.CoursePrerequisites
-- Index: IX_CoursePrerequisites_PrerequisiteCourseID
--
-- JUSTIFICATION:
-- - Supports: 04_queries.sql (Query 4A recursive CTE resolving prerequisite trees),
--             Academic planning queries ("Which courses require CS101 as a prerequisite?").
-- - Problem Solved: PK_CoursePrerequisites has (CourseID, PrerequisiteCourseID).
--   Reverse lookups on PrerequisiteCourseID cannot seek without a dedicated index.
-- - Column Order: PrerequisiteCourseID (equality seek in reverse traversal).
-- - Included Columns: CourseID, MinimumGrade (covers dependency path mapping).
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_CoursePrerequisites_PrerequisiteCourseID'
      AND object_id = OBJECT_ID(N'academic.CoursePrerequisites')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_CoursePrerequisites_PrerequisiteCourseID]
    ON [academic].[CoursePrerequisites] ([PrerequisiteCourseID])
    INCLUDE ([CourseID], [MinimumGrade]);

    PRINT 'Index [IX_CoursePrerequisites_PrerequisiteCourseID] created on [academic].[CoursePrerequisites].';
END
ELSE
BEGIN
    PRINT 'Index [IX_CoursePrerequisites_PrerequisiteCourseID] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 5. Table: academic.Students
-- Index: IX_Students_DepartmentID
--
-- JUSTIFICATION:
-- - Supports: academic.vw_DepartmentPerformance (counting active student majors),
--             04_queries.sql (Query 5A ranking student GPAs partitioned by major department).
-- - Problem Solved: DepartmentID is an un-indexed foreign key. Joins from Departments
--   to Students require scanning PK_Students.
-- - Column Order: DepartmentID (join / partition key).
-- - Included Columns: StudentNumber, FirstName, LastName, AcademicStatus, EnrollmentDate.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Students_DepartmentID'
      AND object_id = OBJECT_ID(N'academic.Students')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Students_DepartmentID]
    ON [academic].[Students] ([DepartmentID])
    INCLUDE ([StudentNumber], [FirstName], [LastName], [AcademicStatus], [EnrollmentDate]);

    PRINT 'Index [IX_Students_DepartmentID] created on [academic].[Students].';
END
ELSE
BEGIN
    PRINT 'Index [IX_Students_DepartmentID] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 6. Table: academic.Courses
-- Index: IX_Courses_DepartmentID
--
-- JUSTIFICATION:
-- - Supports: academic.vw_DepartmentPerformance (total course catalog count),
--             04_queries.sql (Query 2A department course load and credit volume).
-- - Problem Solved: DepartmentID foreign key column un-indexed on Courses.
-- - Column Order: DepartmentID (join key).
-- - Included Columns: CourseCode, Title, Credits.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Courses_DepartmentID'
      AND object_id = OBJECT_ID(N'academic.Courses')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Courses_DepartmentID]
    ON [academic].[Courses] ([DepartmentID])
    INCLUDE ([CourseCode], [Title], [Credits]);

    PRINT 'Index [IX_Courses_DepartmentID] created on [academic].[Courses].';
END
ELSE
BEGIN
    PRINT 'Index [IX_Courses_DepartmentID] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 7. Table: academic.Instructors
-- Index: IX_Instructors_DepartmentID
--
-- JUSTIFICATION:
-- - Supports: academic.vw_DepartmentPerformance (total faculty salary payroll & count),
--             04_queries.sql (Query 3A comparing faculty salary to department average).
-- - Problem Solved: DepartmentID foreign key column un-indexed on Instructors.
-- - Column Order: DepartmentID (join key).
-- - Included Columns: InstructorNumber, FirstName, LastName, Title, Salary, IsActive.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Instructors_DepartmentID'
      AND object_id = OBJECT_ID(N'academic.Instructors')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_Instructors_DepartmentID]
    ON [academic].[Instructors] ([DepartmentID])
    INCLUDE ([InstructorNumber], [FirstName], [LastName], [Title], [Salary], [IsActive]);

    PRINT 'Index [IX_Instructors_DepartmentID] created on [academic].[Instructors].';
END
ELSE
BEGIN
    PRINT 'Index [IX_Instructors_DepartmentID] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 8. Table: academic.CourseSections
-- Index: IX_CourseSections_InstructorID
--
-- JUSTIFICATION:
-- - Supports: academic.vw_CourseEnrollmentStatus (instructor teaching assignments),
--             04_queries.sql (Query 6C anti-join identifying faculty on sabbatical with no sections).
-- - Problem Solved: InstructorID foreign key column un-indexed on CourseSections.
-- - Column Order: InstructorID (join key).
-- - Included Columns: CourseID, TermID, SectionNumber, Status.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_CourseSections_InstructorID'
      AND object_id = OBJECT_ID(N'academic.CourseSections')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_CourseSections_InstructorID]
    ON [academic].[CourseSections] ([InstructorID])
    INCLUDE ([CourseID], [TermID], [SectionNumber], [Status]);

    PRINT 'Index [IX_CourseSections_InstructorID] created on [academic].[CourseSections].';
END
ELSE
BEGIN
    PRINT 'Index [IX_CourseSections_InstructorID] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 9. Table: audit.EnrollmentAuditLog
-- Index: IX_EnrollmentAuditLog_StudentID_ChangedAt
--
-- JUSTIFICATION:
-- - Supports: Auditing student enrollment transitions and registration disputes
--             over chronological time.
-- - Column Order: StudentID (equality seek) -> ChangedAt DESC (chronological sort).
-- - Included Columns: SectionID, ActionType, PreviousStatus, NewStatus, ChangedBy.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_EnrollmentAuditLog_StudentID_ChangedAt'
      AND object_id = OBJECT_ID(N'audit.EnrollmentAuditLog')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_EnrollmentAuditLog_StudentID_ChangedAt]
    ON [audit].[EnrollmentAuditLog] ([StudentID], [ChangedAt] DESC)
    INCLUDE ([SectionID], [ActionType], [PreviousStatus], [NewStatus], [ChangedBy]);

    PRINT 'Index [IX_EnrollmentAuditLog_StudentID_ChangedAt] created on [audit].[EnrollmentAuditLog].';
END
ELSE
BEGIN
    PRINT 'Index [IX_EnrollmentAuditLog_StudentID_ChangedAt] already exists. Skipping.';
END;
GO

-- -----------------------------------------------------------------------------
-- 10. Table: audit.EnrollmentAuditLog
-- Index: IX_EnrollmentAuditLog_SectionID
--
-- JUSTIFICATION:
-- - Supports: Administrative reviews of section roster changes and capacity churn.
-- - Column Order: SectionID (equality seek).
-- - Included Columns: StudentID, ActionType, ChangedAt, ChangedBy.
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_EnrollmentAuditLog_SectionID'
      AND object_id = OBJECT_ID(N'audit.EnrollmentAuditLog')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_EnrollmentAuditLog_SectionID]
    ON [audit].[EnrollmentAuditLog] ([SectionID])
    INCLUDE ([StudentID], [ActionType], [ChangedAt], [ChangedBy]);

    PRINT 'Index [IX_EnrollmentAuditLog_SectionID] created on [audit].[EnrollmentAuditLog].';
END
ELSE
BEGIN
    PRINT 'Index [IX_EnrollmentAuditLog_SectionID] already exists. Skipping.';
END;
GO

PRINT '================================================================================';
PRINT '07_indexes.sql executed successfully. All indexes verified.';
PRINT '================================================================================';
GO
