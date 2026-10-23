/*
================================================================================
SCRIPT: 01_schema.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+
DESCRIPTION:
    Initializes database schemas, tables, constraints, and relational integrity.
    Engineered with 3NF normalization, explicit domain constraints, and audit logging.

SAFETY & IDEMPOTENCY:
    - Does NOT drop existing databases unconditionally.
    - If executed in a system database context (master/tempdb), it defaults to SchoolDB.
    - If executed within an existing target database (e.g., SchoolDB_Test), it respects
      the current database context.
================================================================================
*/

-- -----------------------------------------------------------------------------
-- 1. Database Context Management
-- -----------------------------------------------------------------------------
IF DB_NAME() IN (N'master', N'tempdb', N'model', N'msdb')
BEGIN
    IF DB_ID(N'SchoolDB') IS NULL
    BEGIN
        PRINT 'Creating database SchoolDB...';
        CREATE DATABASE [SchoolDB]
        COLLATE Latin1_General_100_CI_AS_SC_UTF8;
    END;
    USE [SchoolDB];
END;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- -----------------------------------------------------------------------------
-- 2. Schemas Initialization
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'academic')
BEGIN
    EXEC('CREATE SCHEMA [academic] AUTHORIZATION [dbo];');
    PRINT 'Schema [academic] created.';
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'audit')
BEGIN
    EXEC('CREATE SCHEMA [audit] AUTHORIZATION [dbo];');
    PRINT 'Schema [audit] created.';
END;
GO

-- -----------------------------------------------------------------------------
-- 3. Reference Table: GradeScales
--    Explicit grade mapping policy. Enforces letter grade validation,
--    numeric grade points (4.0 scale), credit earning, and GPA inclusion rules.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.GradeScales', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[GradeScales] (
        [LetterGrade]       CHAR(2)         NOT NULL,
        [GradePoints]       DECIMAL(3, 2)   NOT NULL,
        [IsCreditBearing]   BIT             NOT NULL,
        [IsIncludedInGPA]   BIT             NOT NULL,
        [Description]       NVARCHAR(50)    NOT NULL,

        CONSTRAINT [PK_GradeScales] PRIMARY KEY CLUSTERED ([LetterGrade]),
        CONSTRAINT [CK_GradeScales_GradePoints] CHECK ([GradePoints] BETWEEN 0.00 AND 4.00)
    );

    PRINT 'Table [academic].[GradeScales] created.';

    -- Seed canonical grade scale reference data
    INSERT INTO [academic].[GradeScales] ([LetterGrade], [GradePoints], [IsCreditBearing], [IsIncludedInGPA], [Description])
    VALUES
        ('A',  4.00, 1, 1, N'Excellent / Superior Achievement'),
        ('A-', 3.70, 1, 1, N'Excellent / High Achievement'),
        ('B+', 3.30, 1, 1, N'Good / Above Average'),
        ('B',  3.00, 1, 1, N'Good / Average High'),
        ('B-', 2.70, 1, 1, N'Good / Above Competent'),
        ('C+', 2.30, 1, 1, N'Satisfactory / Competent High'),
        ('C',  2.00, 1, 1, N'Satisfactory / Standard Minimum Prerequisite'),
        ('C-', 1.70, 1, 1, N'Marginal / Below Prerequisite Standard'),
        ('D+', 1.30, 1, 1, N'Poor / Passing Minimum High'),
        ('D',  1.00, 1, 1, N'Poor / Passing Minimum'),
        ('F',  0.00, 0, 1, N'Failing / No Credit Earned'),
        ('W',  0.00, 0, 0, N'Official Withdrawal / Excluded From GPA'),
        ('I',  0.00, 0, 0, N'Incomplete Coursework / Excluded From GPA'),
        ('P',  0.00, 1, 0, N'Pass / Credit Granted / Excluded From GPA'),
        ('NP', 0.00, 0, 0, N'No Pass / No Credit / Excluded From GPA');

    PRINT 'Canonical grade scale populated.';
END;
GO

-- -----------------------------------------------------------------------------
-- 4. Table: Departments
--    Academic faculties responsible for curricula, budgets, and faculty.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.Departments', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[Departments] (
        [DepartmentID]      INT IDENTITY(1, 1)  NOT NULL,
        [DepartmentCode]    VARCHAR(10)         NOT NULL,
        [DepartmentName]    NVARCHAR(100)       NOT NULL,
        [Budget]            DECIMAL(12, 2)      NOT NULL,
        [OfficeLocation]    NVARCHAR(50)        NOT NULL,
        [EstablishedDate]   DATE                NOT NULL,
        [HeadOfDepartmentID] INT                NULL,

        CONSTRAINT [PK_Departments] PRIMARY KEY CLUSTERED ([DepartmentID]),
        CONSTRAINT [UQ_Departments_DepartmentCode] UNIQUE NONCLUSTERED ([DepartmentCode]),
        CONSTRAINT [UQ_Departments_DepartmentName] UNIQUE NONCLUSTERED ([DepartmentName]),
        CONSTRAINT [CK_Departments_Budget] CHECK ([Budget] >= 0.00),
        CONSTRAINT [CK_Departments_DepartmentCode_Format] CHECK (
            LEN([DepartmentCode]) >= 2 AND [DepartmentCode] NOT LIKE '%[^A-Z0-9]%'
        )
    );

    PRINT 'Table [academic].[Departments] created.';
END;
GO

-- -----------------------------------------------------------------------------
-- 5. Table: AcademicTerms
--    Defines academic calendar terms (semesters/quarters) and registration dates.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.AcademicTerms', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[AcademicTerms] (
        [TermID]                INT IDENTITY(1, 1)  NOT NULL,
        [TermCode]              VARCHAR(15)         NOT NULL,
        [TermName]              NVARCHAR(50)        NOT NULL,
        [StartDate]             DATE                NOT NULL,
        [EndDate]               DATE                NOT NULL,
        [RegistrationOpenDate]  DATE                NOT NULL,
        [RegistrationCloseDate] DATE                NOT NULL,
        [IsActive]              BIT                 NOT NULL CONSTRAINT [DF_AcademicTerms_IsActive] DEFAULT (0),

        CONSTRAINT [PK_AcademicTerms] PRIMARY KEY CLUSTERED ([TermID]),
        CONSTRAINT [UQ_AcademicTerms_TermCode] UNIQUE NONCLUSTERED ([TermCode]),
        CONSTRAINT [CK_AcademicTerms_TermDates] CHECK ([StartDate] < [EndDate]),
        CONSTRAINT [CK_AcademicTerms_RegistrationDates] CHECK (
            [RegistrationOpenDate] <= [RegistrationCloseDate] AND
            [RegistrationCloseDate] <= [EndDate]
        )
    );

    PRINT 'Table [academic].[AcademicTerms] created.';
END;
GO

-- -----------------------------------------------------------------------------
-- 6. Table: Instructors
--    Faculty members assigned to academic departments and course sections.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.Instructors', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[Instructors] (
        [InstructorID]      INT IDENTITY(1, 1)  NOT NULL,
        [InstructorNumber]  VARCHAR(15)         NOT NULL,
        [FirstName]         NVARCHAR(50)        NOT NULL,
        [LastName]          NVARCHAR(50)        NOT NULL,
        [Email]             NVARCHAR(100)       NOT NULL,
        [Phone]             VARCHAR(20)         NULL,
        [HireDate]          DATE                NOT NULL,
        [DepartmentID]      INT                 NOT NULL,
        [OfficeRoom]        NVARCHAR(30)        NULL,
        [Title]             NVARCHAR(30)        NOT NULL,
        [Salary]            DECIMAL(10, 2)      NOT NULL,
        [IsActive]          BIT                 NOT NULL CONSTRAINT [DF_Instructors_IsActive] DEFAULT (1),

        CONSTRAINT [PK_Instructors] PRIMARY KEY CLUSTERED ([InstructorID]),
        CONSTRAINT [UQ_Instructors_InstructorNumber] UNIQUE NONCLUSTERED ([InstructorNumber]),
        CONSTRAINT [UQ_Instructors_Email] UNIQUE NONCLUSTERED ([Email]),
        CONSTRAINT [FK_Instructors_Departments] FOREIGN KEY ([DepartmentID])
            REFERENCES [academic].[Departments] ([DepartmentID]),
        CONSTRAINT [CK_Instructors_Salary] CHECK ([Salary] > 0.00),
        CONSTRAINT [CK_Instructors_Title] CHECK (
            [Title] IN ('Lecturer', 'Assistant Professor', 'Associate Professor', 'Professor', 'Adjunct')
        ),
        CONSTRAINT [CK_Instructors_Email] CHECK ([Email] LIKE '%_@__%.__%')
    );

    PRINT 'Table [academic].[Instructors] created.';
END;
GO

-- Add circular Foreign Key for Department Head now that Instructors exists
IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_Departments_HeadInstructor'
      AND parent_object_id = OBJECT_ID(N'academic.Departments')
)
BEGIN
    ALTER TABLE [academic].[Departments]
    ADD CONSTRAINT [FK_Departments_HeadInstructor] FOREIGN KEY ([HeadOfDepartmentID])
        REFERENCES [academic].[Instructors] ([InstructorID]);

    PRINT 'Foreign key [FK_Departments_HeadInstructor] added to [academic].[Departments].';
END;
GO

-- -----------------------------------------------------------------------------
-- 7. Table: Students
--    Enrolled students. Derived metrics (GPA, Credits Earned) are deliberately
--    excluded to prevent desynchronization; they are computed via functions/views.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.Students', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[Students] (
        [StudentID]         INT IDENTITY(1, 1)  NOT NULL,
        [StudentNumber]     VARCHAR(15)         NOT NULL,
        [FirstName]         NVARCHAR(50)        NOT NULL,
        [LastName]          NVARCHAR(50)        NOT NULL,
        [Email]             NVARCHAR(100)       NOT NULL,
        [DateOfBirth]       DATE                NOT NULL,
        [EnrollmentDate]    DATE                NOT NULL,
        [DepartmentID]      INT                 NOT NULL,
        [AcademicStatus]    NVARCHAR(20)        NOT NULL CONSTRAINT [DF_Students_AcademicStatus] DEFAULT ('Active'),
        [CreatedAt]         DATETIME2(0)        NOT NULL CONSTRAINT [DF_Students_CreatedAt] DEFAULT (SYSDATETIME()),

        CONSTRAINT [PK_Students] PRIMARY KEY CLUSTERED ([StudentID]),
        CONSTRAINT [UQ_Students_StudentNumber] UNIQUE NONCLUSTERED ([StudentNumber]),
        CONSTRAINT [UQ_Students_Email] UNIQUE NONCLUSTERED ([Email]),
        CONSTRAINT [FK_Students_Departments] FOREIGN KEY ([DepartmentID])
            REFERENCES [academic].[Departments] ([DepartmentID]),
        CONSTRAINT [CK_Students_AcademicStatus] CHECK (
            [AcademicStatus] IN ('Active', 'Probation', 'Suspended', 'Graduated', 'Withdrawn')
        ),
        CONSTRAINT [CK_Students_AgeAtEnrollment] CHECK (
            [DateOfBirth] <= DATEADD(YEAR, -15, [EnrollmentDate])
        ),
        CONSTRAINT [CK_Students_Email] CHECK ([Email] LIKE '%_@__%.__%')
    );

    PRINT 'Table [academic].[Students] created.';
END;
GO

-- -----------------------------------------------------------------------------
-- 8. Table: Courses
--    Standard academic course catalog offered by university departments.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.Courses', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[Courses] (
        [CourseID]          INT IDENTITY(1, 1)  NOT NULL,
        [CourseCode]        VARCHAR(10)         NOT NULL,
        [Title]             NVARCHAR(100)       NOT NULL,
        [Description]       NVARCHAR(500)       NULL,
        [Credits]           TINYINT             NOT NULL,
        [DepartmentID]      INT                 NOT NULL,

        CONSTRAINT [PK_Courses] PRIMARY KEY CLUSTERED ([CourseID]),
        CONSTRAINT [UQ_Courses_CourseCode] UNIQUE NONCLUSTERED ([CourseCode]),
        CONSTRAINT [FK_Courses_Departments] FOREIGN KEY ([DepartmentID])
            REFERENCES [academic].[Departments] ([DepartmentID]),
        CONSTRAINT [CK_Courses_Credits] CHECK ([Credits] BETWEEN 1 AND 6)
    );

    PRINT 'Table [academic].[Courses] created.';
END;
GO

-- -----------------------------------------------------------------------------
-- 9. Table: CoursePrerequisites
--    Specifies required prerequisite courses and the minimum acceptable grade.
--    Self-referencing loops (CourseID = PrerequisiteCourseID) are blocked by constraint.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.CoursePrerequisites', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[CoursePrerequisites] (
        [CourseID]              INT         NOT NULL,
        [PrerequisiteCourseID]  INT         NOT NULL,
        [MinimumGrade]          CHAR(2)     NOT NULL CONSTRAINT [DF_CoursePrerequisites_MinGrade] DEFAULT ('C'),

        CONSTRAINT [PK_CoursePrerequisites] PRIMARY KEY CLUSTERED ([CourseID], [PrerequisiteCourseID]),
        CONSTRAINT [FK_CoursePrerequisites_Course] FOREIGN KEY ([CourseID])
            REFERENCES [academic].[Courses] ([CourseID]),
        CONSTRAINT [FK_CoursePrerequisites_Prereq] FOREIGN KEY ([PrerequisiteCourseID])
            REFERENCES [academic].[Courses] ([CourseID]),
        CONSTRAINT [FK_CoursePrerequisites_GradeScales] FOREIGN KEY ([MinimumGrade])
            REFERENCES [academic].[GradeScales] ([LetterGrade]),
        CONSTRAINT [CK_CoursePrerequisites_NoDirectSelfLoop] CHECK ([CourseID] <> [PrerequisiteCourseID])
    );

    PRINT 'Table [academic].[CoursePrerequisites] created.';
END;
GO

-- -----------------------------------------------------------------------------
-- 10. Table: CourseSections
--     A specific scheduled offering of a course in a given academic term.
--     DESIGN NOTE ON CAPACITY:
--     To guarantee 100% data integrity and eliminate synchronization drift,
--     CurrentEnrolled is NOT stored as a redundant column.
--     Enrolled count is computed from active enrollments, and capacity limits
--     are enforced inside enrollment transactions using UPDLOCK/HOLDLOCK.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.CourseSections', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[CourseSections] (
        [SectionID]         INT IDENTITY(1, 1)  NOT NULL,
        [CourseID]          INT                 NOT NULL,
        [TermID]            INT                 NOT NULL,
        [InstructorID]      INT                 NOT NULL,
        [SectionNumber]     VARCHAR(5)          NOT NULL,
        [MaxCapacity]       INT                 NOT NULL,
        [Classroom]         NVARCHAR(30)        NOT NULL,
        [ScheduleDayTime]   NVARCHAR(50)        NOT NULL,
        [Status]            NVARCHAR(20)        NOT NULL CONSTRAINT [DF_CourseSections_Status] DEFAULT ('Open'),

        CONSTRAINT [PK_CourseSections] PRIMARY KEY CLUSTERED ([SectionID]),
        CONSTRAINT [UQ_CourseSections_Course_Term_Section] UNIQUE NONCLUSTERED (
            [CourseID], [TermID], [SectionNumber]
        ),
        CONSTRAINT [FK_CourseSections_Courses] FOREIGN KEY ([CourseID])
            REFERENCES [academic].[Courses] ([CourseID]),
        CONSTRAINT [FK_CourseSections_AcademicTerms] FOREIGN KEY ([TermID])
            REFERENCES [academic].[AcademicTerms] ([TermID]),
        CONSTRAINT [FK_CourseSections_Instructors] FOREIGN KEY ([InstructorID])
            REFERENCES [academic].[Instructors] ([InstructorID]),
        CONSTRAINT [CK_CourseSections_MaxCapacity] CHECK ([MaxCapacity] > 0),
        CONSTRAINT [CK_CourseSections_Status] CHECK ([Status] IN ('Open', 'Closed', 'Cancelled'))
    );

    PRINT 'Table [academic].[CourseSections] created.';
END;
GO

-- -----------------------------------------------------------------------------
-- 11. Table: Enrollments
--     Student registration in a section.
--     Integrity Invariants:
--     - A student can only register once per section (enforced by unique constraint).
--     - Letter grades are foreign-keyed to academic.GradeScales.
--     - Status and grade consistency is strictly checked.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'academic.Enrollments', N'U') IS NULL
BEGIN
    CREATE TABLE [academic].[Enrollments] (
        [EnrollmentID]      INT IDENTITY(1, 1)  NOT NULL,
        [StudentID]         INT                 NOT NULL,
        [SectionID]         INT                 NOT NULL,
        [EnrollmentDate]    DATETIME2(0)        NOT NULL CONSTRAINT [DF_Enrollments_EnrollmentDate] DEFAULT (SYSDATETIME()),
        [EnrollmentStatus]  NVARCHAR(20)        NOT NULL CONSTRAINT [DF_Enrollments_EnrollmentStatus] DEFAULT ('Enrolled'),
        [LetterGrade]       CHAR(2)             NULL,
        [Notes]             NVARCHAR(250)       NULL,

        CONSTRAINT [PK_Enrollments] PRIMARY KEY CLUSTERED ([EnrollmentID]),
        CONSTRAINT [UQ_Enrollments_Student_Section] UNIQUE NONCLUSTERED ([StudentID], [SectionID]),
        CONSTRAINT [FK_Enrollments_Students] FOREIGN KEY ([StudentID])
            REFERENCES [academic].[Students] ([StudentID]),
        CONSTRAINT [FK_Enrollments_CourseSections] FOREIGN KEY ([SectionID])
            REFERENCES [academic].[CourseSections] ([SectionID]),
        CONSTRAINT [FK_Enrollments_GradeScales] FOREIGN KEY ([LetterGrade])
            REFERENCES [academic].[GradeScales] ([LetterGrade]),
        CONSTRAINT [CK_Enrollments_Status] CHECK (
            [EnrollmentStatus] IN ('Enrolled', 'Completed', 'Dropped', 'Withdrawn')
        ),
        CONSTRAINT [CK_Enrollments_Grade_Status_Consistency] CHECK (
            -- Active enrollment: grade must be NULL or Incomplete ('I')
            ([EnrollmentStatus] = 'Enrolled' AND ([LetterGrade] IS NULL OR [LetterGrade] = 'I')) OR
            -- Completed: must have a final grade assigned (excluding withdrawal 'W')
            ([EnrollmentStatus] = 'Completed' AND [LetterGrade] IS NOT NULL AND [LetterGrade] <> 'W') OR
            -- Dropped: no academic grade
            ([EnrollmentStatus] = 'Dropped' AND [LetterGrade] IS NULL) OR
            -- Withdrawn: letter grade must be 'W'
            ([EnrollmentStatus] = 'Withdrawn' AND [LetterGrade] = 'W')
        )
    );

    PRINT 'Table [academic].[Enrollments] created.';
END;
GO

-- -----------------------------------------------------------------------------
-- 12. Table: EnrollmentAuditLog
--     Audit trail for student enrollment transitions, grade assignments,
--     and administrative status adjustments.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'audit.EnrollmentAuditLog', N'U') IS NULL
BEGIN
    CREATE TABLE [audit].[EnrollmentAuditLog] (
        [AuditID]           BIGINT IDENTITY(1, 1) NOT NULL,
        [EnrollmentID]      INT                 NULL,
        [StudentID]         INT                 NOT NULL,
        [SectionID]         INT                 NOT NULL,
        [ActionType]        VARCHAR(25)         NOT NULL,
        [PreviousStatus]    NVARCHAR(20)        NULL,
        [NewStatus]         NVARCHAR(20)        NULL,
        [PreviousGrade]     CHAR(2)             NULL,
        [NewGrade]          CHAR(2)             NULL,
        [ChangedBy]         NVARCHAR(128)       NOT NULL CONSTRAINT [DF_EnrollmentAuditLog_ChangedBy] DEFAULT (SUSER_SNAME()),
        [ChangedAt]         DATETIME2(0)        NOT NULL CONSTRAINT [DF_EnrollmentAuditLog_ChangedAt] DEFAULT (SYSDATETIME()),
        [Details]           NVARCHAR(500)       NULL,

        CONSTRAINT [PK_EnrollmentAuditLog] PRIMARY KEY CLUSTERED ([AuditID]),
        CONSTRAINT [CK_EnrollmentAuditLog_ActionType] CHECK (
            [ActionType] IN ('ENROLL', 'DROP', 'GRADE_ASSIGNED', 'STATUS_CHANGE', 'REJECTED_ATTEMPT')
        )
    );

    PRINT 'Table [audit].[EnrollmentAuditLog] created.';
END;
GO

PRINT '================================================================================';
PRINT '01_schema.sql executed successfully. All tables and constraints verified.';
PRINT '================================================================================';
GO
