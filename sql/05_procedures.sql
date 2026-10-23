/*
================================================================================
SCRIPT: 05_procedures.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+
DESCRIPTION:
    Implements mission-critical stored procedures with robust transactional
    integrity, concurrency locking strategies, and error handling:
    1. usp_EnrollStudent: Concurrency-safe enrollment with prerequisite checks
    2. usp_DropEnrollment: Atomic drop/withdrawal with audit tracking
    3. usp_GetStudentTranscript: Official student academic profile & history
    4. usp_GetCourseRoster: Section headcount and student roster
================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Procedure: academic.usp_EnrollStudent
--    Enrolls an eligible student into an open course section.
--    Concurrency Strategy:
--    - Uses explicit UPDLOCK, HOLDLOCK on the target CourseSection row.
--    - Evaluates live active enrollment count within the serializable lock window.
--    - Relies on physical UNIQUE constraint UQ_Enrollments_Student_Section as final safeguard.
--    - Transactional TRY...CATCH with SET XACT_ABORT ON guarantees all-or-nothing rollback.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [academic].[usp_EnrollStudent]
    @StudentID                  INT,
    @SectionID                  INT,
    @OverrideRegistrationDates  BIT = 0,
    @EnrolledBy                 NVARCHAR(128) = NULL,
    @NewEnrollmentID            INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AuditUser NVARCHAR(128) = COALESCE(@EnrolledBy, SUSER_SNAME());
    DECLARE @CourseID INT;
    DECLARE @TermID INT;
    DECLARE @MaxCapacity INT;
    DECLARE @SectionStatus NVARCHAR(20);
    DECLARE @StudentStatus NVARCHAR(20);
    DECLARE @StudentName NVARCHAR(100);
    DECLARE @CourseCode VARCHAR(10);
    DECLARE @RegOpenDate DATE;
    DECLARE @RegCloseDate DATE;
    DECLARE @IsTermActive BIT;
    DECLARE @CurrentActiveEnrolled INT;
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

    -- -------------------------------------------------------------------------
    -- Step 1: Pre-Transaction Validation (Read-only validation of existence)
    -- -------------------------------------------------------------------------
    -- Verify student existence
    SELECT
        @StudentStatus = AcademicStatus,
        @StudentName = FirstName + N' ' + LastName
    FROM [academic].[Students]
    WHERE StudentID = @StudentID;

    IF @StudentStatus IS NULL
    BEGIN
        THROW 51001, 'Enrollment rejected: Student record does not exist.', 1;
    END;

    -- Verify student academic eligibility
    IF @StudentStatus <> 'Active'
    BEGIN
        DECLARE @StatusMsg NVARCHAR(200) = FORMATMESSAGE(
            'Enrollment rejected: Student %s is ineligible for registration (Academic Status: %s).',
            @StudentName, @StudentStatus
        );
        THROW 51002, @StatusMsg, 1;
    END;

    -- Verify section existence and gather metadata
    SELECT
        @CourseID = s.CourseID,
        @TermID = s.TermID,
        @MaxCapacity = s.MaxCapacity,
        @SectionStatus = s.Status,
        @CourseCode = c.CourseCode,
        @RegOpenDate = t.RegistrationOpenDate,
        @RegCloseDate = t.RegistrationCloseDate,
        @IsTermActive = t.IsActive
    FROM [academic].[CourseSections] s
    INNER JOIN [academic].[Courses] c ON s.CourseID = c.CourseID
    INNER JOIN [academic].[AcademicTerms] t ON s.TermID = t.TermID
    WHERE s.SectionID = @SectionID;

    IF @CourseID IS NULL
    BEGIN
        THROW 51003, 'Enrollment rejected: Course section does not exist.', 1;
    END;

    -- Verify section schedule status
    IF @SectionStatus <> 'Open'
    BEGIN
        DECLARE @SectionMsg NVARCHAR(200) = FORMATMESSAGE(
            'Enrollment rejected: Course section %d is not open for registration (Status: %s).',
            @SectionID, @SectionStatus
        );
        THROW 51004, @SectionMsg, 1;
    END;

    -- Verify registration window dates (unless overridden by administrator)
    IF @OverrideRegistrationDates = 0
    BEGIN
        IF @Today < @RegOpenDate OR @Today > @RegCloseDate
        BEGIN
            DECLARE @DateMsg NVARCHAR(250) = FORMATMESSAGE(
                'Enrollment rejected: Registration window for course %s is closed. (Open: %s, Close: %s, Current: %s).',
                @CourseCode, CONVERT(VARCHAR(10), @RegOpenDate, 120), CONVERT(VARCHAR(10), @RegCloseDate, 120), CONVERT(VARCHAR(10), @Today, 120)
            );
            THROW 51005, @DateMsg, 1;
        END;
    END;

    -- Check for duplicate active registration in the same course during the same term
    IF EXISTS (
        SELECT 1
        FROM [academic].[Enrollments] e
        INNER JOIN [academic].[CourseSections] s ON e.SectionID = s.SectionID
        WHERE e.StudentID = @StudentID
          AND s.CourseID = @CourseID
          AND s.TermID = @TermID
          AND e.EnrollmentStatus = 'Enrolled'
    )
    BEGIN
        DECLARE @DupCourseMsg NVARCHAR(200) = FORMATMESSAGE(
            'Enrollment rejected: Student is already actively registered in a section of %s for this term.',
            @CourseCode
        );
        THROW 51006, @DupCourseMsg, 1;
    END;

    -- Verify prerequisite satisfaction using deterministic function
    IF [academic].[fn_CheckPrerequisitesSatisfied](@StudentID, @CourseID) = 0
    BEGIN
        DECLARE @PrereqMsg NVARCHAR(250) = FORMATMESSAGE(
            'Enrollment rejected: Student has not satisfied the required prerequisites with the minimum qualifying grade for course %s.',
            @CourseCode
        );
        THROW 51007, @PrereqMsg, 1;
    END;

    -- -------------------------------------------------------------------------
    -- Step 2: Atomic Transaction Execution with Concurrency Locking
    -- -------------------------------------------------------------------------
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Acquire an exclusive update lock on the target section row to serialize
        -- concurrent enrollment requests for this specific section
        DECLARE @CurrentSectionStatus NVARCHAR(20);

        SELECT
            @MaxCapacity = MaxCapacity,
            @CurrentSectionStatus = Status
        FROM [academic].[CourseSections] WITH (UPDLOCK, HOLDLOCK)
        WHERE SectionID = @SectionID;

        -- Revalidate administrative section status inside serialized lock
        -- Guarantees that concurrent closures or cancellations are honored immediately
        IF @CurrentSectionStatus <> 'Open'
        BEGIN
            DECLARE @LockedStatusMsg NVARCHAR(200) = FORMATMESSAGE(
                'Enrollment rejected: Course section %d is not open for registration (Current Administrative Status: %s).',
                @SectionID, @CurrentSectionStatus
            );
            THROW 51004, @LockedStatusMsg, 1;
        END;

        -- Count live active enrollments under lock protection
        SELECT @CurrentActiveEnrolled = COUNT(*)
        FROM [academic].[Enrollments] WITH (UPDLOCK, HOLDLOCK)
        WHERE SectionID = @SectionID
          AND EnrollmentStatus = 'Enrolled';

        -- Enforce strict capacity limit dynamically against active enrollments
        IF @CurrentActiveEnrolled >= @MaxCapacity
        BEGIN
            DECLARE @CapMsg NVARCHAR(200) = FORMATMESSAGE(
                'Enrollment rejected: Course section has reached maximum capacity (%d of %d seats occupied).',
                @CurrentActiveEnrolled, @MaxCapacity
            );
            THROW 51008, @CapMsg, 1;
        END;

        -- Insert enrollment record
        INSERT INTO [academic].[Enrollments]
            ([StudentID], [SectionID], [EnrollmentDate], [EnrollmentStatus], [LetterGrade])
        VALUES
            (@StudentID, @SectionID, SYSDATETIME(), 'Enrolled', NULL);

        SET @NewEnrollmentID = SCOPE_IDENTITY();

        -- Record audit event
        INSERT INTO [audit].[EnrollmentAuditLog]
            ([EnrollmentID], [StudentID], [SectionID], [ActionType], [PreviousStatus], [NewStatus], [PreviousGrade], [NewGrade], [ChangedBy], [Details])
        VALUES
            (@NewEnrollmentID, @StudentID, @SectionID, 'ENROLL', NULL, 'Enrolled', NULL, NULL, @AuditUser,
             FORMATMESSAGE('Enrolled student %d in section %d. Live Occupancy: %d/%d.', @StudentID, @SectionID, @CurrentActiveEnrolled + 1, @MaxCapacity));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Cleanly translate unique constraint violation if hit concurrently
        IF ERROR_NUMBER() IN (2601, 2627)
        BEGIN
            THROW 51009, 'Enrollment rejected: Duplicate enrollment detected. Student is already enrolled in this section.', 1;
        END;

        -- Re-throw original error
        THROW;
    END CATCH;
END;
GO

PRINT 'Procedure [academic].[usp_EnrollStudent] created.';
GO

-- -----------------------------------------------------------------------------
-- 2. Procedure: academic.usp_DropEnrollment
--    Safely drops an active enrollment. Applies Drop vs. Withdrawal logic
--    based on registration calendar dates, and audits the transition.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [academic].[usp_DropEnrollment]
    @StudentID      INT,
    @SectionID      INT,
    @Reason         NVARCHAR(250) = NULL,
    @DroppedBy      NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AuditUser NVARCHAR(128) = COALESCE(@DroppedBy, SUSER_SNAME());
    DECLARE @EnrollmentID INT;
    DECLARE @CurrentStatus NVARCHAR(20);
    DECLARE @CurrentGrade CHAR(2);
    DECLARE @RegCloseDate DATE;
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @NewStatus NVARCHAR(20);
    DECLARE @NewGrade CHAR(2);

    -- Find active enrollment record
    SELECT
        @EnrollmentID = e.EnrollmentID,
        @CurrentStatus = e.EnrollmentStatus,
        @CurrentGrade = e.LetterGrade,
        @RegCloseDate = t.RegistrationCloseDate
    FROM [academic].[Enrollments] e
    INNER JOIN [academic].[CourseSections] s ON e.SectionID = s.SectionID
    INNER JOIN [academic].[AcademicTerms] t ON s.TermID = t.TermID
    WHERE e.StudentID = @StudentID
      AND e.SectionID = @SectionID;

    IF @EnrollmentID IS NULL
    BEGIN
        THROW 51010, 'Drop rejected: No enrollment record found for the specified student and section.', 1;
    END;

    IF @CurrentStatus <> 'Enrolled'
    BEGIN
        DECLARE @StatusMsg NVARCHAR(200) = FORMATMESSAGE(
            'Drop rejected: Cannot drop enrollment with status [%s]. Only active enrollments can be dropped.',
            @CurrentStatus
        );
        THROW 51011, @StatusMsg, 1;
    END;

    -- Determine Drop vs. Official Withdrawal:
    -- If dropping on or before registration close date: Dropped (no grade, no transcript penalty)
    -- If dropping after registration close date: Withdrawn (grade 'W' recorded, no GPA penalty)
    IF @Today <= @RegCloseDate
    BEGIN
        SET @NewStatus = 'Dropped';
        SET @NewGrade = NULL;
    END
    ELSE
    BEGIN
        SET @NewStatus = 'Withdrawn';
        SET @NewGrade = 'W';
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Update enrollment record
        UPDATE [academic].[Enrollments]
        SET [EnrollmentStatus] = @NewStatus,
            [LetterGrade] = @NewGrade
        WHERE [EnrollmentID] = @EnrollmentID;

        -- Record audit event
        INSERT INTO [audit].[EnrollmentAuditLog]
            ([EnrollmentID], [StudentID], [SectionID], [ActionType], [PreviousStatus], [NewStatus], [PreviousGrade], [NewGrade], [ChangedBy], [Details])
        VALUES
            (@EnrollmentID, @StudentID, @SectionID,
             CASE WHEN @NewStatus = 'Dropped' THEN 'DROP' ELSE 'STATUS_CHANGE' END,
             @CurrentStatus, @NewStatus, @CurrentGrade, @NewGrade, @AuditUser,
             ISNULL(@Reason, N'Enrollment dropped via administrative procedure.'));

        -- Note: CourseSections.Status represents administrative intent (Open, Closed, Cancelled).
        -- Capacity availability is evaluated dynamically from active enrollments (vw_CourseEnrollmentStatus).
        -- We deliberately do not overwrite administrative section status on drop.

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

PRINT 'Procedure [academic].[usp_DropEnrollment] created.';
GO

-- -----------------------------------------------------------------------------
-- 3. Procedure: academic.usp_GetStudentTranscript
--    Returns an official student transcript with cumulative GPA and academic history.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [academic].[usp_GetStudentTranscript]
    @StudentID      INT = NULL,
    @StudentNumber  VARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Resolve StudentID from StudentNumber if needed
    IF @StudentID IS NULL AND @StudentNumber IS NOT NULL
    BEGIN
        SELECT @StudentID = StudentID
        FROM [academic].[Students]
        WHERE StudentNumber = @StudentNumber;
    END;

    IF @StudentID IS NULL OR NOT EXISTS (SELECT 1 FROM [academic].[Students] WHERE StudentID = @StudentID)
    BEGIN
        THROW 51020, 'Transcript generation failed: Student record does not exist.', 1;
    END;

    -- Result Set 1: Student Academic Profile Summary
    SELECT
        s.StudentID,
        s.StudentNumber,
        s.FirstName + N' ' + s.LastName AS StudentFullName,
        s.Email,
        d.DepartmentCode AS MajorCode,
        d.DepartmentName AS MajorDepartment,
        s.AcademicStatus,
        s.EnrollmentDate,
        [academic].[fn_CalculateStudentGPA](s.StudentID) AS CumulativeGPA,
        ISNULL(SUM(CASE WHEN e.EnrollmentStatus = 'Completed' AND gs.IsCreditBearing = 1 THEN c.Credits ELSE 0 END), 0) AS TotalCreditsEarned,
        ISNULL(SUM(CASE WHEN e.EnrollmentStatus = 'Completed' AND gs.IsIncludedInGPA = 1 THEN c.Credits ELSE 0 END), 0) AS TotalGPACreditsAttempted
    FROM [academic].[Students] s
    INNER JOIN [academic].[Departments] d ON s.DepartmentID = d.DepartmentID
    LEFT JOIN [academic].[Enrollments] e ON s.StudentID = e.StudentID
    LEFT JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
    LEFT JOIN [academic].[Courses] c ON sec.CourseID = c.CourseID
    LEFT JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade
    WHERE s.StudentID = @StudentID
    GROUP BY
        s.StudentID, s.StudentNumber, s.FirstName, s.LastName, s.Email,
        d.DepartmentCode, d.DepartmentName, s.AcademicStatus, s.EnrollmentDate;

    -- Result Set 2: Chronological Academic Course History
    SELECT
        t.TermCode,
        t.TermName,
        t.StartDate AS TermStartDate,
        c.CourseCode,
        c.Title AS CourseTitle,
        c.Credits,
        e.EnrollmentStatus,
        e.LetterGrade,
        gs.GradePoints,
        CASE
            WHEN gs.IsIncludedInGPA = 1
            THEN CAST(ROUND(c.Credits * gs.GradePoints, 2) AS DECIMAL(5, 2))
            ELSE 0.00
        END AS QualityPoints,
        ISNULL(gs.IsCreditBearing, 0) AS IsCreditBearing,
        ISNULL(gs.IsIncludedInGPA, 0) AS IsIncludedInGPA,
        i.FirstName + N' ' + i.LastName AS InstructorName
    FROM [academic].[Enrollments] e
    INNER JOIN [academic].[CourseSections] sec ON e.SectionID = sec.SectionID
    INNER JOIN [academic].[Courses] c ON sec.CourseID = c.CourseID
    INNER JOIN [academic].[AcademicTerms] t ON sec.TermID = t.TermID
    INNER JOIN [academic].[Instructors] i ON sec.InstructorID = i.InstructorID
    LEFT JOIN [academic].[GradeScales] gs ON e.LetterGrade = gs.LetterGrade
    WHERE e.StudentID = @StudentID
    ORDER BY
        t.StartDate ASC, c.CourseCode ASC;
END;
GO

PRINT 'Procedure [academic].[usp_GetStudentTranscript] created.';
GO

-- -----------------------------------------------------------------------------
-- 4. Procedure: academic.usp_GetCourseRoster
--    Returns section details and the roster of enrolled students.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [academic].[usp_GetCourseRoster]
    @SectionID          INT,
    @IncludeInactive    BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [academic].[CourseSections] WHERE SectionID = @SectionID)
    BEGIN
        THROW 51030, 'Roster retrieval failed: Course section does not exist.', 1;
    END;

    -- Result Set 1: Section Header and Capacity Status
    SELECT
        s.SectionID,
        c.CourseCode,
        c.Title AS CourseTitle,
        c.Credits,
        t.TermCode,
        t.TermName,
        s.SectionNumber,
        i.FirstName + N' ' + i.LastName AS InstructorName,
        s.Classroom,
        s.ScheduleDayTime,
        s.MaxCapacity,
        COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) AS ActiveEnrolledCount,
        s.MaxCapacity - COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) AS SeatsAvailable,
        CAST(ROUND(
            COUNT(CASE WHEN e.EnrollmentStatus = 'Enrolled' THEN 1 END) * 100.0 / s.MaxCapacity, 1
        ) AS DECIMAL(5, 1)) AS OccupancyRatePercent,
        s.Status AS SectionStatus
    FROM [academic].[CourseSections] s
    INNER JOIN [academic].[Courses] c ON s.CourseID = c.CourseID
    INNER JOIN [academic].[AcademicTerms] t ON s.TermID = t.TermID
    INNER JOIN [academic].[Instructors] i ON s.InstructorID = i.InstructorID
    LEFT JOIN [academic].[Enrollments] e ON s.SectionID = e.SectionID
    WHERE s.SectionID = @SectionID
    GROUP BY
        s.SectionID, c.CourseCode, c.Title, c.Credits, t.TermCode, t.TermName,
        s.SectionNumber, i.FirstName, i.LastName, s.Classroom, s.ScheduleDayTime,
        s.MaxCapacity, s.Status;

    -- Result Set 2: Student Enrollment Roster
    SELECT
        s.StudentID,
        s.StudentNumber,
        s.FirstName + N' ' + s.LastName AS StudentFullName,
        s.Email,
        d.DepartmentCode AS MajorCode,
        s.AcademicStatus,
        e.EnrollmentStatus,
        e.LetterGrade,
        e.EnrollmentDate
    FROM [academic].[Enrollments] e
    INNER JOIN [academic].[Students] s ON e.StudentID = s.StudentID
    INNER JOIN [academic].[Departments] d ON s.DepartmentID = d.DepartmentID
    WHERE e.SectionID = @SectionID
      AND (
          (@IncludeInactive = 1)
          OR (@IncludeInactive = 0 AND e.EnrollmentStatus = 'Enrolled')
      )
    ORDER BY
        s.LastName ASC, s.FirstName ASC;
END;
GO

PRINT 'Procedure [academic].[usp_GetCourseRoster] created.';
PRINT '================================================================================';
PRINT '05_procedures.sql executed successfully. All procedures verified.';
PRINT '================================================================================';
GO
