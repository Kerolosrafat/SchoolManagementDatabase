/*
================================================================================
SCRIPT: 08_bonus_optional.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+
DESCRIPTION:
    Implements advanced, production-grade SQL Server enterprise features:
    1. System-Versioned Temporal Tables (ISO/IEC 9075:2011 standard) for academic.Students
       to maintain an immutable historical audit trail of student demographic and
       status changes over time.
    2. Dynamic Data Masking (DDM) for sensitive Personally Identifiable Information (PII)
       and compensation data (Student Email, DateOfBirth, Instructor Phone, Salary).

ARCHITECTURAL POLICIES & SAFETY:
    - Period columns (SysStartTime, SysEndTime) are marked HIDDEN to ensure
      100% backward compatibility with existing SELECT * queries and views.
    - Masking is strictly applied to non-key sensitive attributes; primary keys,
      foreign keys, and join predicates are NEVER masked.
    - Explains that DDM is a query-time presentation obfuscation tool, not physical
      encryption; full security requires database role authorization and encryption (TDE/AE).
    - Completely optional: the core database operates independently with or without this script.
================================================================================
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '================================================================================';
PRINT 'STARTING BONUS ENTERPRISE FEATURES DEPLOYMENT';
PRINT '================================================================================';
GO

-- =============================================================================
-- FEATURE 1: SYSTEM-VERSIONED TEMPORAL TABLE (academic.Students)
-- =============================================================================
/*
    EXPLANATION:
    Temporal tables automatically record the full history of data changes in a
    companion history table (academic.StudentsHistory). Whenever a student's
    academic status, email, or department major changes, SQL Server captures the
    prior state with precise UTC period validity timestamps (SysStartTime, SysEndTime).

    SCOPE NOTE:
    Temporal versioning applies strictly to academic.Students. It tracks changes to
    student attributes over time, but does NOT track changes to related tables
    (e.g., CourseSections or Enrollments), which maintain their own audit logs.
*/

IF NOT EXISTS (
    SELECT 1
    FROM sys.tables
    WHERE name = 'Students'
      AND schema_id = SCHEMA_ID('academic')
      AND temporal_type = 2 -- 2 = SYSTEM_VERSIONED_TEMPORAL_TABLE
)
BEGIN
    PRINT 'Enabling system-versioned temporal table on [academic].[Students]...';

    -- Step 1: Add period columns with HIDDEN attribute to avoid breaking existing queries
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID('academic.Students') AND name = 'SysStartTime'
    )
    BEGIN
        ALTER TABLE [academic].[Students]
        ADD
            [SysStartTime] DATETIME2(0) GENERATED ALWAYS AS ROW START HIDDEN
                CONSTRAINT [DF_Students_SysStartTime] DEFAULT '1900-01-01 00:00:00',
            [SysEndTime]   DATETIME2(0) GENERATED ALWAYS AS ROW END HIDDEN
                CONSTRAINT [DF_Students_SysEndTime]   DEFAULT '9999-12-31 23:59:59',
            PERIOD FOR SYSTEM_TIME ([SysStartTime], [SysEndTime]);

        PRINT 'Period columns [SysStartTime] and [SysEndTime] added to [academic].[Students].';
    END;

    -- Step 2: Enable System Versioning with explicit history table
    ALTER TABLE [academic].[Students]
    SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = [academic].[StudentsHistory]));

    PRINT 'System versioning successfully enabled. History table: [academic].[StudentsHistory].';
END
ELSE
BEGIN
    PRINT 'System versioning is already enabled on [academic].[Students]. Skipping.';
END;
GO

-- =============================================================================
-- FEATURE 2: DYNAMIC DATA MASKING (DDM)
-- =============================================================================
/*
    EXPLANATION:
    Dynamic Data Masking limits sensitive data exposure by masking it to
    non-privileged users at query execution time.
    - Students.Email: Masked with email() function (e.g. sXXX@XXXX.com).
    - Students.DateOfBirth: Masked with default() function (returns 1900-01-01).
    - Instructors.Phone: Masked with default() function (returns xxxx).
    - Instructors.Salary: Masked with default() function (returns 0.00).

    SECURITY LIMITATION:
    DDM is an obfuscation layer designed to prevent casual data snooping in
    reporting apps. It does NOT replace encryption or role-based security; users
    with UNMASK permissions or ad-hoc query capabilities can infer values through
    exhaustive brute-force WHERE predicates if not properly restricted.
*/

PRINT 'Configuring Dynamic Data Masking on sensitive PII and compensation attributes...';

-- Mask Students.Email
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('academic.Students') AND name = 'Email' AND is_masked = 0
)
BEGIN
    ALTER TABLE [academic].[Students]
    ALTER COLUMN [Email] ADD MASKED WITH (FUNCTION = 'email()');
    PRINT 'Masking applied to [academic].[Students].[Email].';
END;
GO

-- Mask Students.DateOfBirth
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('academic.Students') AND name = 'DateOfBirth' AND is_masked = 0
)
BEGIN
    ALTER TABLE [academic].[Students]
    ALTER COLUMN [DateOfBirth] ADD MASKED WITH (FUNCTION = 'default()');
    PRINT 'Masking applied to [academic].[Students].[DateOfBirth].';
END;
GO

-- Mask Instructors.Phone
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('academic.Instructors') AND name = 'Phone' AND is_masked = 0
)
BEGIN
    ALTER TABLE [academic].[Instructors]
    ALTER COLUMN [Phone] ADD MASKED WITH (FUNCTION = 'default()');
    PRINT 'Masking applied to [academic].[Instructors].[Phone].';
END;
GO

-- Mask Instructors.Salary
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('academic.Instructors') AND name = 'Salary' AND is_masked = 0
)
BEGIN
    ALTER TABLE [academic].[Instructors]
    ALTER COLUMN [Salary] ADD MASKED WITH (FUNCTION = 'default()');
    PRINT 'Masking applied to [academic].[Instructors].[Salary].';
END;
GO

-- =============================================================================
-- FEATURE 3: VERIFICATION AND DEMONSTRATION SUITE
-- =============================================================================

PRINT '================================================================================';
PRINT 'DEMONSTRATION 1: TEMPORAL POINT-IN-TIME & FULL HISTORY QUERIES';
PRINT '================================================================================';
GO

-- -----------------------------------------------------------------------------
-- Query 1A: Querying the complete version history of a student using FOR SYSTEM_TIME ALL
-- Shows how a student''s major or academic status progressed chronologically.
-- -----------------------------------------------------------------------------
SELECT
    s.StudentID,
    s.StudentNumber,
    s.FirstName + N' ' + s.LastName AS StudentFullName,
    s.AcademicStatus,
    s.SysStartTime AS ValidFromUTC,
    s.SysEndTime AS ValidToUTC,
    CASE
        WHEN s.SysEndTime >= '9999-12-31' THEN 'CURRENT VERSION'
        ELSE 'HISTORICAL VERSION'
    END AS RecordState
FROM [academic].[Students] FOR SYSTEM_TIME ALL s
WHERE s.StudentID = 23 -- Samuel Tarley
ORDER BY s.SysStartTime ASC;
GO

PRINT '================================================================================';
PRINT 'DEMONSTRATION 2: DYNAMIC DATA MASKING (PRIVILEGED VS. RESTRICTED USER)';
PRINT '================================================================================';
GO

-- Create an isolated temporary test user without login to demonstrate masked views
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'DemoMaskedUser')
BEGIN
    CREATE USER [DemoMaskedUser] WITHOUT LOGIN;
END;
GO

-- Grant read-only access to academic views and tables
GRANT SELECT ON [academic].[Students] TO [DemoMaskedUser];
GRANT SELECT ON [academic].[Instructors] TO [DemoMaskedUser];
GO

-- -----------------------------------------------------------------------------
-- Query 2A: Privileged Administrator View (Unmasked)
-- -----------------------------------------------------------------------------
PRINT '--- A. Privileged User View (Full Cleartext Access) ---';
SELECT TOP 3
    s.StudentNumber,
    s.FirstName + N' ' + s.LastName AS StudentName,
    s.Email,
    s.DateOfBirth,
    s.AcademicStatus
FROM [academic].[Students] s
ORDER BY s.StudentNumber;

SELECT TOP 3
    i.InstructorNumber,
    i.FirstName + N' ' + i.LastName AS FacultyName,
    i.Phone,
    i.Salary
FROM [academic].[Instructors] i
ORDER BY i.InstructorNumber;
GO

-- -----------------------------------------------------------------------------
-- Query 2B: Restricted Application User View (Masked at Presentation Layer)
-- -----------------------------------------------------------------------------
PRINT '--- B. Restricted User View (Masked PII & Salary Data) ---';
EXECUTE AS USER = 'DemoMaskedUser';

SELECT TOP 3
    s.StudentNumber,
    s.FirstName + N' ' + s.LastName AS StudentName,
    s.Email,
    s.DateOfBirth,
    s.AcademicStatus
FROM [academic].[Students] s
ORDER BY s.StudentNumber;

SELECT TOP 3
    i.InstructorNumber,
    i.FirstName + N' ' + i.LastName AS FacultyName,
    i.Phone,
    i.Salary
FROM [academic].[Instructors] i
ORDER BY i.InstructorNumber;

REVERT;
GO

-- Cleanup temporary demo principal
DROP USER IF EXISTS [DemoMaskedUser];
PRINT 'Temporary demo principal [DemoMaskedUser] cleaned up.';
GO

/*
================================================================================
APPENDIX: ROLLBACK & DE-PROVISIONING GUIDE (OPTIONAL)
If you ever wish to remove the bonus features and return to baseline DDL:

-- 1. Disable and remove Temporal Versioning:
ALTER TABLE [academic].[Students] SET (SYSTEM_VERSIONING = OFF);
ALTER TABLE [academic].[Students] DROP PERIOD FOR SYSTEM_TIME;
ALTER TABLE [academic].[Students] DROP COLUMN [SysStartTime], [SysEndTime];
DROP TABLE IF EXISTS [academic].[StudentsHistory];

-- 2. Drop Dynamic Data Masking:
ALTER TABLE [academic].[Students] ALTER COLUMN [Email] DROP MASKED;
ALTER TABLE [academic].[Students] ALTER COLUMN [DateOfBirth] DROP MASKED;
ALTER TABLE [academic].[Instructors] ALTER COLUMN [Phone] DROP MASKED;
ALTER TABLE [academic].[Instructors] ALTER COLUMN [Salary] DROP MASKED;
================================================================================
*/

PRINT '================================================================================';
PRINT '08_bonus_optional.sql executed successfully. All bonus features verified.';
PRINT '================================================================================';
GO
