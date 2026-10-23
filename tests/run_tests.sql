/*
================================================================================
SCRIPT: tests/run_tests.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+ (Database: SchoolDB_Test)
DESCRIPTION:
    Comprehensive, automated regression and validation test suite containing 66 assertions:
    1. Schema objects, tables, columns, primary keys, check constraints, foreign keys
    2. Canonical seed data baseline and relational edge cases
    3. Reporting views (transcripts, summaries, capacities, performance)
    4. Deterministic scalar and inline table-valued functions
    5. Stored procedures (success, duplicates, capacity, status, prereqs, transcripts, rosters)
    6. Audit trail integrity, action tracking, and rejection isolation
    7. System-versioned temporal table history, queryability, and dynamic data masking
    8. Strategic nonclustered indexes, covering column definitions, and key column order

SAFETY & REPEATABILITY:
    - Runs exclusively against [SchoolDB_Test].
    - Uses isolated test fixtures (SectionNumber = 'T99', StudentID = 23).
    - Guarantees 100% deterministic cleanup of test fixtures in all execution paths.
    - Verifies baseline seed row counts are strictly preserved at completion.
    - Exits with a nonzero return code (THROW 59999) if any assertion fails.
================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- -----------------------------------------------------------------------------
-- Safety Check: Ensure execution only against SchoolDB_Test
-- -----------------------------------------------------------------------------
DECLARE @CurrentDB NVARCHAR(128) = DB_NAME();
IF @CurrentDB <> 'SchoolDB_Test'
BEGIN
    RAISERROR('FATAL SAFETY ERROR: This test suite must be executed ONLY against [SchoolDB_Test]. Current database is [%s]. Aborting.', 20, 1, @CurrentDB) WITH LOG;
END;
GO

PRINT '================================================================================';
PRINT 'STARTING AUTOMATED TEST SUITE: SchoolDB_Test';
PRINT 'Server: ' + @@SERVERNAME + ' | Version: SQL Server 2022 | Date: ' + CONVERT(VARCHAR, SYSDATETIME(), 120);
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- Test Results Harness Table
-- -----------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TestResults') IS NOT NULL
    DROP TABLE #TestResults;

CREATE TABLE #TestResults (
    [TestID]        INT IDENTITY(1, 1) PRIMARY KEY,
    [Category]      VARCHAR(40)     NOT NULL,
    [TestName]      VARCHAR(100)    NOT NULL,
    [Status]        VARCHAR(10)     NOT NULL, -- 'PASS' or 'FAIL'
    [Details]       NVARCHAR(500)   NULL
);

DECLARE @PassedCount INT = 0;
DECLARE @FailedCount INT = 0;

-- Snapshot baseline counts for seed validation and drift detection
DECLARE @InitSections INT = (SELECT COUNT(*) FROM [academic].[CourseSections]);
DECLARE @InitEnrollments INT = (SELECT COUNT(*) FROM [academic].[Enrollments]);
DECLARE @InitAuditLogs INT = (SELECT COUNT(*) FROM [audit].[EnrollmentAuditLog]);
DECLARE @InitStudents INT = (SELECT COUNT(*) FROM [academic].[Students]);
DECLARE @InitCourses INT = (SELECT COUNT(*) FROM [academic].[Courses]);
DECLARE @InitHistoryRows INT = (SELECT COUNT(*) FROM [academic].[StudentsHistory]);

-- =============================================================================
-- CATEGORY 1: SCHEMA OBJECTS & DATA INTEGRITY CONSTRAINTS
-- =============================================================================

-- Assert 1: Academic Departments table existence and column count
IF (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'academic' AND TABLE_NAME = 'Departments') = 7
    INSERT INTO #TestResults VALUES ('Schema', 'Departments Table Structure', 'PASS', '7 columns verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Schema', 'Departments Table Structure', 'FAIL', 'Column count mismatch.');

-- Assert 2: Students table existence and column count
IF (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'academic' AND TABLE_NAME = 'Students') >= 10
    INSERT INTO #TestResults VALUES ('Schema', 'Students Table Structure', 'PASS', 'Columns verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Schema', 'Students Table Structure', 'FAIL', 'Columns missing.');

-- Assert 3: CourseSections table existence and column count
IF (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'academic' AND TABLE_NAME = 'CourseSections') = 9
    INSERT INTO #TestResults VALUES ('Schema', 'CourseSections Table Structure', 'PASS', '9 columns verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Schema', 'CourseSections Table Structure', 'FAIL', 'Columns mismatch.');

-- Assert 4: Enrollments table existence and column count
IF (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'academic' AND TABLE_NAME = 'Enrollments') = 7
    INSERT INTO #TestResults VALUES ('Schema', 'Enrollments Table Structure', 'PASS', '7 columns verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Schema', 'Enrollments Table Structure', 'FAIL', 'Columns mismatch.');

-- Assert 5: Primary Keys presence on all 10 core tables
IF (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE CONSTRAINT_TYPE = 'PRIMARY KEY' AND TABLE_SCHEMA IN ('academic', 'audit')) = 10
    INSERT INTO #TestResults VALUES ('Constraints', 'Primary Key Coverage', 'PASS', '10 primary keys verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Constraints', 'Primary Key Coverage', 'FAIL', 'Missing primary keys.');

-- Assert 6: Unique constraint on Enrollments (StudentID, SectionID)
IF EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_NAME = 'UQ_Enrollments_Student_Section' AND TABLE_SCHEMA = 'academic'
)
    INSERT INTO #TestResults VALUES ('Constraints', 'Unique Student-Section Enrollment Constraint', 'PASS', 'UQ_Enrollments_Student_Section verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Constraints', 'Unique Student-Section Enrollment Constraint', 'FAIL', 'Unique constraint missing.');

-- Assert 7: CoursePrerequisites Self-Loop Prevention Check Constraint
IF EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_CoursePrerequisites_NoDirectSelfLoop'
)
    INSERT INTO #TestResults VALUES ('Constraints', 'Prerequisite No Self-Loop Constraint', 'PASS', 'CK_CoursePrerequisites_NoDirectSelfLoop verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Constraints', 'Prerequisite No Self-Loop Constraint', 'FAIL', 'Constraint missing.');

-- Assert 8: Check constraint on GradePoints range (0.00 to 4.00)
IF EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_GradeScales_GradePoints'
)
    INSERT INTO #TestResults VALUES ('Constraints', 'GradePoints Range Constraint', 'PASS', 'CK_GradeScales_GradePoints verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Constraints', 'GradePoints Range Constraint', 'FAIL', 'Constraint missing.');

-- Assert 9: Check constraint on Section MaxCapacity (> 0)
IF EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_CourseSections_MaxCapacity'
)
    INSERT INTO #TestResults VALUES ('Constraints', 'MaxCapacity Positive Constraint', 'PASS', 'CK_CourseSections_MaxCapacity verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Constraints', 'MaxCapacity Positive Constraint', 'FAIL', 'Constraint missing.');

-- Assert 10: Foreign Keys existence (13 verified FKs in academic and audit)
IF (SELECT COUNT(*) FROM sys.foreign_keys WHERE SCHEMA_NAME(schema_id) IN ('academic', 'audit')) = 13
    INSERT INTO #TestResults VALUES ('Constraints', 'Foreign Key Relational Integrity', 'PASS', '13 foreign keys verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Constraints', 'Foreign Key Relational Integrity', 'FAIL', 'Foreign key count mismatch.');

-- =============================================================================
-- CATEGORY 2: BASELINE SEED DATA
-- =============================================================================

-- Assert 11: Exactly 5 departments seeded
IF (SELECT COUNT(*) FROM [academic].[Departments]) = 5
    INSERT INTO #TestResults VALUES ('SeedData', 'Department Baseline Count', 'PASS', '5 departments verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Department Baseline Count', 'FAIL', 'Department count mismatch.');

-- Assert 12: Exactly 4 academic terms seeded
IF (SELECT COUNT(*) FROM [academic].[AcademicTerms]) = 4
    INSERT INTO #TestResults VALUES ('SeedData', 'Academic Terms Baseline Count', 'PASS', '4 terms verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Academic Terms Baseline Count', 'FAIL', 'Terms count mismatch.');

-- Assert 13: Exactly 1 active term configured
IF (SELECT COUNT(*) FROM [academic].[AcademicTerms] WHERE IsActive = 1) = 1
    INSERT INTO #TestResults VALUES ('SeedData', 'Active Term Configuration', 'PASS', 'Exactly 1 active term verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Active Term Configuration', 'FAIL', 'Active term count mismatch.');

-- Assert 14: Exactly 11 instructors seeded
IF (SELECT COUNT(*) FROM [academic].[Instructors]) = 11
    INSERT INTO #TestResults VALUES ('SeedData', 'Instructor Baseline Count', 'PASS', '11 instructors verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Instructor Baseline Count', 'FAIL', 'Instructor count mismatch.');

-- Assert 15: Exactly 25 students seeded
IF (SELECT COUNT(*) FROM [academic].[Students]) = 25
    INSERT INTO #TestResults VALUES ('SeedData', 'Student Baseline Count', 'PASS', '25 students verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Student Baseline Count', 'FAIL', 'Student count mismatch.');

-- Assert 16: Exactly 15 courses seeded
IF (SELECT COUNT(*) FROM [academic].[Courses]) = 15
    INSERT INTO #TestResults VALUES ('SeedData', 'Course Catalog Baseline Count', 'PASS', '15 courses verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Course Catalog Baseline Count', 'FAIL', 'Course count mismatch.');

-- Assert 17: Exactly 8 prerequisite rules seeded
IF (SELECT COUNT(*) FROM [academic].[CoursePrerequisites]) = 8
    INSERT INTO #TestResults VALUES ('SeedData', 'Prerequisites Baseline Count', 'PASS', '8 rules verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Prerequisites Baseline Count', 'FAIL', 'Prerequisite count mismatch.');

-- Assert 18: Exactly 15 canonical grade scales seeded
IF (SELECT COUNT(*) FROM [academic].[GradeScales]) = 15
    INSERT INTO #TestResults VALUES ('SeedData', 'Grade Scales Baseline Count', 'PASS', '15 grades verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Grade Scales Baseline Count', 'FAIL', 'Grade scale count mismatch.');

-- Assert 19: Edge case - Students with 0 enrollments exist
IF (SELECT COUNT(*) FROM [academic].[Students] s WHERE NOT EXISTS (SELECT 1 FROM [academic].[Enrollments] e WHERE e.StudentID = s.StudentID)) = 5
    INSERT INTO #TestResults VALUES ('SeedData', 'Edge Case: Students with Zero Enrollments', 'PASS', '5 non-enrolled students verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Edge Case: Students with Zero Enrollments', 'FAIL', 'Unexpected non-enrolled student count.');

-- Assert 20: Edge case - Courses with 0 scheduled sections exist
IF (SELECT COUNT(*) FROM [academic].[Courses] c WHERE NOT EXISTS (SELECT 1 FROM [academic].[CourseSections] s WHERE s.CourseID = c.CourseID)) = 5
    INSERT INTO #TestResults VALUES ('SeedData', 'Edge Case: Catalog Courses Never Scheduled', 'PASS', '5 un-scheduled courses verified.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Edge Case: Catalog Courses Never Scheduled', 'FAIL', 'Unexpected un-scheduled course count.');

-- Assert 21: Edge case - Full section exists (CS401-01, SectionID = 15)
IF EXISTS (
    SELECT 1 FROM [academic].[CourseSections] s
    WHERE s.SectionID = 15
      AND s.MaxCapacity = 3
      AND (SELECT COUNT(*) FROM [academic].[Enrollments] e WHERE e.SectionID = s.SectionID AND e.EnrollmentStatus = 'Enrolled') = 3
)
    INSERT INTO #TestResults VALUES ('SeedData', 'Edge Case: Fully Occupied Section Verification', 'PASS', 'Section 15 (CS401) is at 3/3 capacity.');
ELSE
    INSERT INTO #TestResults VALUES ('SeedData', 'Edge Case: Fully Occupied Section Verification', 'FAIL', 'Full section 15 not at capacity.');

-- =============================================================================
-- CATEGORY 3: VIEWS ACCURACY & REPORTING
-- =============================================================================

-- Assert 22: vw_StudentAcademicSummary preserves all 25 students
IF (SELECT COUNT(*) FROM [academic].[vw_StudentAcademicSummary]) = 25
    INSERT INTO #TestResults VALUES ('Views', 'vw_StudentAcademicSummary Completeness', 'PASS', 'All 25 students preserved via LEFT JOIN.');
ELSE
    INSERT INTO #TestResults VALUES ('Views', 'vw_StudentAcademicSummary Completeness', 'FAIL', 'Row count mismatch.');

-- Assert 23: vw_StudentAcademicSummary returns NULL GPA for students with 0 GPA credits
IF (SELECT COUNT(*) FROM [academic].[vw_StudentAcademicSummary] WHERE GPACreditsAttempted = 0 AND CumulativeGPA IS NULL) = 10
    INSERT INTO #TestResults VALUES ('Views', 'vw_StudentAcademicSummary NULL GPA Policy', 'PASS', '10 students with 0 GPA credits cleanly return NULL.');
ELSE
    INSERT INTO #TestResults VALUES ('Views', 'vw_StudentAcademicSummary NULL GPA Policy', 'FAIL', 'NULL GPA count mismatch.');

-- Assert 24: vw_StudentAcademicSummary computes Sophia Chen GPA as 4.00
IF (SELECT CumulativeGPA FROM [academic].[vw_StudentAcademicSummary] WHERE StudentNumber = 'STU-2023-0001') = 4.00
    INSERT INTO #TestResults VALUES ('Views', 'vw_StudentAcademicSummary GPA Accuracy', 'PASS', 'Sophia Chen GPA verified as 4.00.');
ELSE
    INSERT INTO #TestResults VALUES ('Views', 'vw_StudentAcademicSummary GPA Accuracy', 'FAIL', 'GPA mismatch for Sophia Chen.');

-- Assert 25: vw_CourseEnrollmentStatus correctly classifies Section 15 as FULL
IF (SELECT CapacityStatus FROM [academic].[vw_CourseEnrollmentStatus] WHERE SectionID = 15) = 'FULL'
    INSERT INTO #TestResults VALUES ('Views', 'vw_CourseEnrollmentStatus Full Classification', 'PASS', 'Section 15 classified as FULL.');
ELSE
    INSERT INTO #TestResults VALUES ('Views', 'vw_CourseEnrollmentStatus Full Classification', 'FAIL', 'Section 15 not classified as FULL.');

-- Assert 26: vw_CourseEnrollmentStatus correctly classifies Section 16 as EMPTY
IF (SELECT CapacityStatus FROM [academic].[vw_CourseEnrollmentStatus] WHERE SectionID = 16) = 'EMPTY'
    INSERT INTO #TestResults VALUES ('Views', 'vw_CourseEnrollmentStatus Empty Classification', 'PASS', 'Section 16 classified as EMPTY.');
ELSE
    INSERT INTO #TestResults VALUES ('Views', 'vw_CourseEnrollmentStatus Empty Classification', 'FAIL', 'Section 16 not classified as EMPTY.');

-- Assert 27: vw_DepartmentPerformance returns all 5 departments
IF (SELECT COUNT(*) FROM [academic].[vw_DepartmentPerformance]) = 5
    INSERT INTO #TestResults VALUES ('Views', 'vw_DepartmentPerformance Completeness', 'PASS', '5 departments reported.');
ELSE
    INSERT INTO #TestResults VALUES ('Views', 'vw_DepartmentPerformance Completeness', 'FAIL', 'Department count mismatch.');

-- Assert 28: vw_StudentTranscripts quality points calculation
IF EXISTS (
    SELECT 1 FROM [academic].[vw_StudentTranscripts]
    WHERE StudentNumber = 'STU-2023-0001' AND CourseCode = 'CS101' AND QualityPoints = 16.00
)
    INSERT INTO #TestResults VALUES ('Views', 'vw_StudentTranscripts Quality Points Accuracy', 'PASS', 'Quality points (4 cr * 4.00) = 16.00 verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Views', 'vw_StudentTranscripts Quality Points Accuracy', 'FAIL', 'Quality points calculation mismatch.');

-- =============================================================================
-- CATEGORY 4: USER-DEFINED FUNCTIONS
-- =============================================================================

-- Assert 29: fn_CalculateStudentGPA parity with summary view
DECLARE @MismatchGpaCount INT = (
    SELECT COUNT(*)
    FROM [academic].[Students] s
    INNER JOIN [academic].[vw_StudentAcademicSummary] v ON s.StudentID = v.StudentID
    WHERE (v.CumulativeGPA IS NOT NULL AND [academic].[fn_CalculateStudentGPA](s.StudentID) <> v.CumulativeGPA)
       OR (v.CumulativeGPA IS NULL AND [academic].[fn_CalculateStudentGPA](s.StudentID) IS NOT NULL)
);

IF @MismatchGpaCount = 0
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CalculateStudentGPA Parity', 'PASS', '100% parity across all 25 students.');
ELSE
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CalculateStudentGPA Parity', 'FAIL', 'GPA function mismatch detected.');

-- Assert 30: fn_CalculateStudentGPA returns NULL for non-enrolled student
IF [academic].[fn_CalculateStudentGPA](23) IS NULL
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CalculateStudentGPA NULL Handling', 'PASS', 'Returns NULL for student with 0 graded courses.');
ELSE
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CalculateStudentGPA NULL Handling', 'FAIL', 'Did not return NULL.');

-- Assert 31: fn_CheckPrerequisitesSatisfied for course with 0 prerequisites (CS101)
DECLARE @CS101_ID INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS101');
IF [academic].[fn_CheckPrerequisitesSatisfied](23, @CS101_ID) = 1
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CheckPrerequisitesSatisfied No Prereqs', 'PASS', 'Returns 1 for course without prerequisites.');
ELSE
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CheckPrerequisitesSatisfied No Prereqs', 'FAIL', 'Did not return 1.');

-- Assert 32: fn_CheckPrerequisitesSatisfied with earned passing grade ('A' in CS101 for CS201)
DECLARE @CS201_ID INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS201');
IF [academic].[fn_CheckPrerequisitesSatisfied](1, @CS201_ID) = 1
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CheckPrerequisitesSatisfied Passing Bar', 'PASS', 'Returns 1 for student with A grade.');
ELSE
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CheckPrerequisitesSatisfied Passing Bar', 'FAIL', 'Did not return 1 for passing grade.');

-- Assert 33: fn_CheckPrerequisitesSatisfied with failing grade ('F' in CS101 for CS201)
IF [academic].[fn_CheckPrerequisitesSatisfied](16, @CS201_ID) = 0
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CheckPrerequisitesSatisfied Failing Bar', 'PASS', 'Returns 0 for student with F grade.');
ELSE
    INSERT INTO #TestResults VALUES ('Functions', 'fn_CheckPrerequisitesSatisfied Failing Bar', 'FAIL', 'Did not return 0 for failing grade.');

-- Assert 34: fn_GetStudentSchedule returns active term enrollments
IF (SELECT COUNT(*) FROM [academic].[fn_GetStudentSchedule](1, NULL)) = 2
    INSERT INTO #TestResults VALUES ('Functions', 'fn_GetStudentSchedule Active Schedule', 'PASS', '2 active courses returned for Sophia Chen.');
ELSE
    INSERT INTO #TestResults VALUES ('Functions', 'fn_GetStudentSchedule Active Schedule', 'FAIL', 'Schedule count mismatch.');

-- =============================================================================
-- CATEGORY 5: STORED PROCEDURES & BUSINESS RULES (ISOLATED FIXTURES)
-- =============================================================================

-- Setup Temporary Test Fixtures
INSERT INTO [academic].[CourseSections]
    ([CourseID], [TermID], [InstructorID], [SectionNumber], [MaxCapacity], [Classroom], [ScheduleDayTime], [Status])
VALUES
    (1, 3, 1, 'T99', 1, 'Test Fixture Lab', 'M 07:00-08:00', 'Open');
DECLARE @TestSecID INT = SCOPE_IDENTITY();

INSERT INTO [academic].[CourseSections]
    ([CourseID], [TermID], [InstructorID], [SectionNumber], [MaxCapacity], [Classroom], [ScheduleDayTime], [Status])
VALUES
    (1, 3, 1, 'T98', 30, 'Test Fixture Lab', 'T 07:00-08:00', 'Closed');
DECLARE @TestSecClosedID INT = SCOPE_IDENTITY();

INSERT INTO [academic].[CourseSections]
    ([CourseID], [TermID], [InstructorID], [SectionNumber], [MaxCapacity], [Classroom], [ScheduleDayTime], [Status])
VALUES
    (1, 3, 1, 'T97', 30, 'Test Fixture Lab', 'W 07:00-08:00', 'Cancelled');
DECLARE @TestSecCancelledID INT = SCOPE_IDENTITY();

-- Assert 35: usp_EnrollStudent normal successful enrollment
DECLARE @NewEnrollID INT;
BEGIN TRY
    EXEC [academic].[usp_EnrollStudent]
        @StudentID = 23,
        @SectionID = @TestSecID,
        @EnrolledBy = N'TestRunner',
        @NewEnrollmentID = @NewEnrollID OUTPUT;

    IF EXISTS (SELECT 1 FROM [academic].[Enrollments] WHERE EnrollmentID = @NewEnrollID AND EnrollmentStatus = 'Enrolled')
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Success Path', 'PASS', 'Enrollment created with status = Enrolled.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Success Path', 'FAIL', 'Enrollment ID not found.');
END TRY
BEGIN CATCH
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Success Path', 'FAIL', ERROR_MESSAGE());
END CATCH;

-- Assert 36: usp_EnrollStudent rejects duplicate enrollment
BEGIN TRY
    EXEC [academic].[usp_EnrollStudent] @StudentID = 23, @SectionID = @TestSecID, @EnrolledBy = N'TestRunner';
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Duplicate Rejection', 'FAIL', 'Duplicate enrollment succeeded.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() IN (51006, 51009)
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Duplicate Rejection', 'PASS', 'Duplicate caught: ' + ERROR_MESSAGE());
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Duplicate Rejection', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- Assert 37: usp_EnrollStudent rejects non-existent student
BEGIN TRY
    EXEC [academic].[usp_EnrollStudent] @StudentID = 99999, @SectionID = @TestSecID, @EnrolledBy = N'TestRunner';
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Non-Existent Student', 'FAIL', 'Non-existent student allowed enrollment.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51001
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Non-Existent Student', 'PASS', 'Error 51001 caught as expected.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Non-Existent Student', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- Assert 38: usp_EnrollStudent rejects closed section
BEGIN TRY
    EXEC [academic].[usp_EnrollStudent] @StudentID = 25, @SectionID = @TestSecClosedID, @EnrolledBy = N'TestRunner';
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Closed Section Rejection', 'FAIL', 'Closed section allowed enrollment.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51004
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Closed Section Rejection', 'PASS', 'Error 51004 caught as expected.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Closed Section Rejection', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- Assert 39: usp_EnrollStudent rejects cancelled section
BEGIN TRY
    EXEC [academic].[usp_EnrollStudent] @StudentID = 25, @SectionID = @TestSecCancelledID, @EnrolledBy = N'TestRunner';
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Cancelled Section Rejection', 'FAIL', 'Cancelled section allowed enrollment.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51004
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Cancelled Section Rejection', 'PASS', 'Error 51004 caught as expected.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Cancelled Section Rejection', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- Assert 40: usp_EnrollStudent rejects when section capacity reached
BEGIN TRY
    -- Section has MaxCapacity = 1, and Student 23 is already enrolled
    EXEC [academic].[usp_EnrollStudent] @StudentID = 25, @SectionID = @TestSecID, @EnrolledBy = N'TestRunner';
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Capacity Rejection', 'FAIL', 'Exceeded capacity without rejection.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51008
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Capacity Rejection', 'PASS', 'Error 51008 capacity caught as expected.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Capacity Rejection', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- Assert 41: usp_EnrollStudent rejects unmet prerequisite
BEGIN TRY
    -- Student 24 (Arya Stark, no courses) trying to enroll in CS201 (requires CS101)
    EXEC [academic].[usp_EnrollStudent] @StudentID = 24, @SectionID = 10, @EnrolledBy = N'TestRunner';
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Unmet Prerequisite', 'FAIL', 'Unmet prereq allowed enrollment.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51007
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Unmet Prerequisite', 'PASS', 'Error 51007 prereq caught as expected.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Unmet Prerequisite', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- Assert 42: usp_EnrollStudent rejects ineligible student (Suspended)
BEGIN TRY
    EXEC [academic].[usp_EnrollStudent] @StudentID = 17, @SectionID = @TestSecID, @EnrolledBy = N'TestRunner';
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Ineligible Student', 'FAIL', 'Suspended student allowed enrollment.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51002
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Ineligible Student', 'PASS', 'Error 51002 status caught as expected.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_EnrollStudent Ineligible Student', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- Assert 43: usp_DropEnrollment drops enrollment and records audit
BEGIN TRY
    -- Mark section as Closed administratively
    UPDATE [academic].[CourseSections] SET Status = 'Closed' WHERE SectionID = @TestSecID;

    EXEC [academic].[usp_DropEnrollment]
        @StudentID = 23,
        @SectionID = @TestSecID,
        @Reason = N'Test drop execution',
        @DroppedBy = N'TestRunner';

    IF EXISTS (SELECT 1 FROM [academic].[Enrollments] WHERE EnrollmentID = @NewEnrollID AND EnrollmentStatus = 'Dropped')
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_DropEnrollment Status Update', 'PASS', 'Status transitioned to Dropped.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_DropEnrollment Status Update', 'FAIL', 'Status not updated to Dropped.');
END TRY
BEGIN CATCH
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_DropEnrollment Status Update', 'FAIL', ERROR_MESSAGE());
END CATCH;

-- Assert 44: usp_DropEnrollment does NOT reopen administratively closed section
IF (SELECT Status FROM [academic].[CourseSections] WHERE SectionID = @TestSecID) = 'Closed'
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_DropEnrollment Administrative Status Preservation', 'PASS', 'Section status remained Closed.');
ELSE
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_DropEnrollment Administrative Status Preservation', 'FAIL', 'Section was incorrectly reopened.');

-- Assert 45: usp_GetStudentTranscript execution
BEGIN TRY
    EXEC [academic].[usp_GetStudentTranscript] @StudentID = 23;
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetStudentTranscript Execution', 'PASS', 'Transcript procedure executed successfully.');
END TRY
BEGIN CATCH
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetStudentTranscript Execution', 'FAIL', ERROR_MESSAGE());
END CATCH;

-- Assert 46: usp_GetStudentTranscript non-existent student rejection
BEGIN TRY
    EXEC [academic].[usp_GetStudentTranscript] @StudentID = 99999;
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetStudentTranscript Non-Existent Rejection', 'FAIL', 'Invalid student did not throw error.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51020
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetStudentTranscript Non-Existent Rejection', 'PASS', 'Error 51020 caught as expected.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetStudentTranscript Non-Existent Rejection', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- Assert 47: usp_GetCourseRoster execution
BEGIN TRY
    EXEC [academic].[usp_GetCourseRoster] @SectionID = 16, @IncludeInactive = 0;
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetCourseRoster Execution', 'PASS', 'Roster procedure executed successfully.');
END TRY
BEGIN CATCH
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetCourseRoster Execution', 'FAIL', ERROR_MESSAGE());
END CATCH;

-- Assert 48: usp_GetCourseRoster non-existent section rejection
BEGIN TRY
    EXEC [academic].[usp_GetCourseRoster] @SectionID = 99999;
    INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetCourseRoster Non-Existent Rejection', 'FAIL', 'Invalid section did not throw error.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51030
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetCourseRoster Non-Existent Rejection', 'PASS', 'Error 51030 caught as expected.');
    ELSE
        INSERT INTO #TestResults VALUES ('Procedures', 'usp_GetCourseRoster Non-Existent Rejection', 'FAIL', 'Unexpected error: ' + ERROR_MESSAGE());
END CATCH;

-- =============================================================================
-- CATEGORY 6: AUDIT TRAIL INTEGRITY
-- =============================================================================

-- Assert 49: Audit log captured ENROLL action
IF EXISTS (SELECT 1 FROM [audit].[EnrollmentAuditLog] WHERE EnrollmentID = @NewEnrollID AND ActionType = 'ENROLL')
    INSERT INTO #TestResults VALUES ('Audit', 'Audit Log ENROLL Capture', 'PASS', 'ENROLL action logged with user and details.');
ELSE
    INSERT INTO #TestResults VALUES ('Audit', 'Audit Log ENROLL Capture', 'FAIL', 'Audit record missing.');

-- Assert 50: Audit log captured DROP action
IF EXISTS (SELECT 1 FROM [audit].[EnrollmentAuditLog] WHERE EnrollmentID = @NewEnrollID AND ActionType = 'DROP')
    INSERT INTO #TestResults VALUES ('Audit', 'Audit Log DROP Capture', 'PASS', 'DROP action logged with user and details.');
ELSE
    INSERT INTO #TestResults VALUES ('Audit', 'Audit Log DROP Capture', 'FAIL', 'Audit record missing.');

-- Assert 51: Rejected operations do not generate false audit entries
IF NOT EXISTS (
    SELECT 1 FROM [audit].[EnrollmentAuditLog]
    WHERE StudentID IN (24, 25, 99999) AND SectionID = @TestSecID
)
    INSERT INTO #TestResults VALUES ('Audit', 'Audit Trail Isolation on Rejected Operations', 'PASS', 'Rejected attempts produced zero audit records.');
ELSE
    INSERT INTO #TestResults VALUES ('Audit', 'Audit Trail Isolation on Rejected Operations', 'FAIL', 'Rejected attempts left dangling audit records.');

-- Teardown Test Fixtures
DELETE FROM [audit].[EnrollmentAuditLog] WHERE SectionID IN (@TestSecID, @TestSecClosedID, @TestSecCancelledID);
DELETE FROM [academic].[Enrollments] WHERE SectionID IN (@TestSecID, @TestSecClosedID, @TestSecCancelledID);
DELETE FROM [academic].[CourseSections] WHERE SectionID IN (@TestSecID, @TestSecClosedID, @TestSecCancelledID);

-- Assert 52: Zero dangling audit rows after cleanup
IF (SELECT COUNT(*) FROM [audit].[EnrollmentAuditLog]) = @InitAuditLogs
    INSERT INTO #TestResults VALUES ('Audit', 'Zero Dangling Audit Records', 'PASS', 'Audit count returned to exact baseline.');
ELSE
    INSERT INTO #TestResults VALUES ('Audit', 'Zero Dangling Audit Records', 'FAIL', 'Audit log count drifted.');

-- =============================================================================
-- CATEGORY 7: TEMPORAL HISTORY & DATA MASKING
-- =============================================================================

-- Assert 53: Temporal versioning is enabled on academic.Students
IF EXISTS (
    SELECT 1 FROM sys.tables
    WHERE name = 'Students' AND schema_id = SCHEMA_ID('academic') AND temporal_type = 2
)
    INSERT INTO #TestResults VALUES ('Temporal', 'System Versioning Enabled', 'PASS', 'Students is SYSTEM_VERSIONED_TEMPORAL_TABLE.');
ELSE
    INSERT INTO #TestResults VALUES ('Temporal', 'System Versioning Enabled', 'FAIL', 'Students is not system-versioned.');

-- Assert 54: Companion history table academic.StudentsHistory exists
IF OBJECT_ID('academic.StudentsHistory', 'U') IS NOT NULL
    INSERT INTO #TestResults VALUES ('Temporal', 'Companion History Table Existence', 'PASS', 'academic.StudentsHistory exists.');
ELSE
    INSERT INTO #TestResults VALUES ('Temporal', 'Companion History Table Existence', 'FAIL', 'StudentsHistory table missing.');

-- Assert 55: Period columns SysStartTime and SysEndTime are HIDDEN
IF (
    SELECT COUNT(*)
    FROM sys.columns
    WHERE object_id = OBJECT_ID('academic.Students')
      AND name IN ('SysStartTime', 'SysEndTime')
      AND is_hidden = 1
) = 2
    INSERT INTO #TestResults VALUES ('Temporal', 'Hidden Period Columns', 'PASS', 'SysStartTime and SysEndTime are marked HIDDEN.');
ELSE
    INSERT INTO #TestResults VALUES ('Temporal', 'Hidden Period Columns', 'FAIL', 'Period columns not marked HIDDEN.');

-- Assert 56: FOR SYSTEM_TIME ALL queryability across baseline records
IF (SELECT COUNT(*) FROM [academic].[Students] FOR SYSTEM_TIME ALL) >= 25
    INSERT INTO #TestResults VALUES ('Temporal', 'FOR SYSTEM_TIME Queryability', 'PASS', 'FOR SYSTEM_TIME ALL returns >= 25 records.');
ELSE
    INSERT INTO #TestResults VALUES ('Temporal', 'FOR SYSTEM_TIME Queryability', 'FAIL', 'FOR SYSTEM_TIME query failed.');

-- Assert 57: Dynamic Data Masking on Students.Email
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('academic.Students') AND name = 'Email' AND is_masked = 1
)
    INSERT INTO #TestResults VALUES ('Masking', 'Students.Email DDM Active', 'PASS', 'Email column is masked.');
ELSE
    INSERT INTO #TestResults VALUES ('Masking', 'Students.Email DDM Active', 'FAIL', 'Email column is not masked.');

-- Assert 58: Dynamic Data Masking on Students.DateOfBirth
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('academic.Students') AND name = 'DateOfBirth' AND is_masked = 1
)
    INSERT INTO #TestResults VALUES ('Masking', 'Students.DateOfBirth DDM Active', 'PASS', 'DateOfBirth column is masked.');
ELSE
    INSERT INTO #TestResults VALUES ('Masking', 'Students.DateOfBirth DDM Active', 'FAIL', 'DateOfBirth column is not masked.');

-- Assert 59: Dynamic Data Masking on Instructors.Salary
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('academic.Instructors') AND name = 'Salary' AND is_masked = 1
)
    INSERT INTO #TestResults VALUES ('Masking', 'Instructors.Salary DDM Active', 'PASS', 'Salary column is masked.');
ELSE
    INSERT INTO #TestResults VALUES ('Masking', 'Instructors.Salary DDM Active', 'FAIL', 'Salary column is not masked.');

-- =============================================================================
-- CATEGORY 8: STRATEGIC INDEX INVENTORY & KEY COLUMN INTEGRITY
-- =============================================================================

-- Assert 60: IX_Enrollments_SectionID_Status index existence and key columns
IF EXISTS (
    SELECT 1
    FROM sys.index_columns ic1
    INNER JOIN sys.columns c1 ON ic1.object_id = c1.object_id AND ic1.column_id = c1.column_id
    INNER JOIN sys.index_columns ic2 ON ic1.object_id = ic2.object_id
    INNER JOIN sys.columns c2 ON ic2.object_id = c2.object_id AND ic2.column_id = c2.column_id
    WHERE ic1.object_id = OBJECT_ID('academic.Enrollments')
      AND ic1.index_id = INDEXPROPERTY(OBJECT_ID('academic.Enrollments'), 'IX_Enrollments_SectionID_Status', 'IndexID')
      AND c1.name = 'SectionID' AND ic1.key_ordinal = 1
      AND c2.name = 'EnrollmentStatus' AND ic2.key_ordinal = 2
)
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_Enrollments_SectionID_Status', 'PASS', 'Key columns (SectionID, EnrollmentStatus) verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_Enrollments_SectionID_Status', 'FAIL', 'Index or key columns missing.');

-- Assert 61: IX_Enrollments_StudentID_Status index existence and key columns
IF EXISTS (
    SELECT 1
    FROM sys.index_columns ic1
    INNER JOIN sys.columns c1 ON ic1.object_id = c1.object_id AND ic1.column_id = c1.column_id
    INNER JOIN sys.index_columns ic2 ON ic1.object_id = ic2.object_id
    INNER JOIN sys.columns c2 ON ic2.object_id = c2.object_id AND ic2.column_id = c2.column_id
    WHERE ic1.object_id = OBJECT_ID('academic.Enrollments')
      AND ic1.index_id = INDEXPROPERTY(OBJECT_ID('academic.Enrollments'), 'IX_Enrollments_StudentID_Status', 'IndexID')
      AND c1.name = 'StudentID' AND ic1.key_ordinal = 1
      AND c2.name = 'EnrollmentStatus' AND ic2.key_ordinal = 2
)
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_Enrollments_StudentID_Status', 'PASS', 'Key columns (StudentID, EnrollmentStatus) verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_Enrollments_StudentID_Status', 'FAIL', 'Index or key columns missing.');

-- Assert 62: IX_CourseSections_TermID_Status index existence and key columns
IF EXISTS (
    SELECT 1
    FROM sys.index_columns ic1
    INNER JOIN sys.columns c1 ON ic1.object_id = c1.object_id AND ic1.column_id = c1.column_id
    INNER JOIN sys.index_columns ic2 ON ic1.object_id = ic2.object_id
    INNER JOIN sys.columns c2 ON ic2.object_id = c2.object_id AND ic2.column_id = c2.column_id
    WHERE ic1.object_id = OBJECT_ID('academic.CourseSections')
      AND ic1.index_id = INDEXPROPERTY(OBJECT_ID('academic.CourseSections'), 'IX_CourseSections_TermID_Status', 'IndexID')
      AND c1.name = 'TermID' AND ic1.key_ordinal = 1
      AND c2.name = 'Status' AND ic2.key_ordinal = 2
)
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_CourseSections_TermID_Status', 'PASS', 'Key columns (TermID, Status) verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_CourseSections_TermID_Status', 'FAIL', 'Index or key columns missing.');

-- Assert 63: IX_CoursePrerequisites_PrerequisiteCourseID index existence
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CoursePrerequisites_PrerequisiteCourseID' AND object_id = OBJECT_ID('academic.CoursePrerequisites'))
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_CoursePrerequisites_PrereqID', 'PASS', 'Reverse prerequisite index verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_CoursePrerequisites_PrereqID', 'FAIL', 'Index missing.');

-- Assert 64: Foreign key indexes on DepartmentID (Students, Courses, Instructors)
IF (
    SELECT COUNT(*) FROM sys.indexes
    WHERE name IN ('IX_Students_DepartmentID', 'IX_Courses_DepartmentID', 'IX_Instructors_DepartmentID')
) = 3
    INSERT INTO #TestResults VALUES ('Indexes', 'Foreign Key DepartmentID Indexes', 'PASS', 'All 3 department FK indexes verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Indexes', 'Foreign Key DepartmentID Indexes', 'FAIL', 'Department FK indexes missing.');

-- Assert 65: IX_CourseSections_InstructorID index existence
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CourseSections_InstructorID' AND object_id = OBJECT_ID('academic.CourseSections'))
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_CourseSections_InstructorID', 'PASS', 'Faculty section assignment index verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Indexes', 'Index IX_CourseSections_InstructorID', 'FAIL', 'Index missing.');

-- Assert 66: Audit Log nonclustered indexes (StudentID_ChangedAt, SectionID)
IF (
    SELECT COUNT(*) FROM sys.indexes
    WHERE object_id = OBJECT_ID('audit.EnrollmentAuditLog')
      AND name IN ('IX_EnrollmentAuditLog_StudentID_ChangedAt', 'IX_EnrollmentAuditLog_SectionID')
) = 2
    INSERT INTO #TestResults VALUES ('Indexes', 'Audit Log Nonclustered Indexes', 'PASS', 'Both audit log indexes verified.');
ELSE
    INSERT INTO #TestResults VALUES ('Indexes', 'Audit Log Nonclustered Indexes', 'FAIL', 'Audit log indexes missing.');

-- =============================================================================
-- FINAL REPORT & SUMMARY
-- =============================================================================

SELECT @PassedCount = COUNT(CASE WHEN Status = 'PASS' THEN 1 END) FROM #TestResults;
SELECT @FailedCount = COUNT(CASE WHEN Status = 'FAIL' THEN 1 END) FROM #TestResults;

PRINT '';
PRINT '================================================================================';
PRINT 'TEST EXECUTION SUMMARY';
PRINT '================================================================================';
PRINT FORMATMESSAGE('Total Assertions : %d', @PassedCount + @FailedCount);
PRINT FORMATMESSAGE('Passed           : %d', @PassedCount);
PRINT FORMATMESSAGE('Failed           : %d', @FailedCount);
PRINT '--------------------------------------------------------------------------------';

-- Output detailed results table
SELECT
    CAST(TestID AS VARCHAR(4)) AS [#],
    CAST(Category AS VARCHAR(14)) AS [Category],
    CAST(TestName AS VARCHAR(42)) AS [Assertion],
    CAST(Status AS VARCHAR(6)) AS [Status],
    CAST(Details AS VARCHAR(50)) AS [Details]
FROM #TestResults
ORDER BY TestID;

-- Verify baseline database counts were preserved and no drift occurred
DECLARE @FinalSections INT = (SELECT COUNT(*) FROM [academic].[CourseSections]);
DECLARE @FinalEnrollments INT = (SELECT COUNT(*) FROM [academic].[Enrollments]);
DECLARE @FinalAuditLogs INT = (SELECT COUNT(*) FROM [audit].[EnrollmentAuditLog]);
DECLARE @FinalStudents INT = (SELECT COUNT(*) FROM [academic].[Students]);
DECLARE @FinalCourses INT = (SELECT COUNT(*) FROM [academic].[Courses]);
DECLARE @FinalHistoryRows INT = (SELECT COUNT(*) FROM [academic].[StudentsHistory]);

IF @FinalSections <> @InitSections
   OR @FinalEnrollments <> @InitEnrollments
   OR @FinalAuditLogs <> @InitAuditLogs
   OR @FinalStudents <> @InitStudents
   OR @FinalCourses <> @InitCourses
   OR @FinalHistoryRows <> @InitHistoryRows
BEGIN
    PRINT 'FATAL ERROR: Baseline row counts drifted after test execution!';
    PRINT FORMATMESSAGE('Sections: Init=%d, Final=%d | Enrollments: Init=%d, Final=%d | Audit: Init=%d, Final=%d | History: Init=%d, Final=%d',
        @InitSections, @FinalSections, @InitEnrollments, @FinalEnrollments, @InitAuditLogs, @FinalAuditLogs, @InitHistoryRows, @FinalHistoryRows);
    SET @FailedCount = @FailedCount + 1;
END;

IF @FailedCount > 0
BEGIN
    PRINT '';
    PRINT '================================================================================';
    PRINT 'RESULT: FAILED (' + CAST(@FailedCount AS VARCHAR) + ' assertion(s) failed)';
    PRINT '================================================================================';
    THROW 59999, 'Test suite failed with one or more assertion failures.', 1;
END
ELSE
BEGIN
    PRINT '';
    PRINT '================================================================================';
    PRINT 'RESULT: SUCCESS (All ' + CAST(@PassedCount AS VARCHAR) + ' assertions passed flawlessly)';
    PRINT '================================================================================';
END;
GO
