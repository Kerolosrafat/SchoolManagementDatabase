# University Course and Student Management Database (`SchoolDB`)

A robust, enterprise-grade relational database management project implemented from scratch in **Microsoft SQL Server (T-SQL)**. This project models an academic institution's lifecycle, featuring relational normalization, deterministic GPA calculations, concurrency-safe course registration, automated audit logging, system-versioned temporal history, dynamic data masking, workload-aligned indexing, and a comprehensive automated PowerShell test suite.

---

## 1. Project Overview & Scope

The **University Course and Student Management Database** (`SchoolDB`) provides a centralized, relational data management architecture for higher-education operations. It handles student admissions, academic departments, faculty appointments, course catalog management, term scheduling, multi-condition prerequisite enforcement, transactional enrollment workflows, and official transcript generation.

### System Scope & Operational Boundaries
- **Target Platform**: Microsoft SQL Server 2022+ (Enterprise, Standard, or Developer Edition).
- **Core Schemas**:
  - `academic`: Operational tables, catalog management, course sections, grades, views, procedures, and user-defined functions.
  - `audit`: Immutable historical audit logs tracking lifecycle status changes.
- **Scope Limitations**: This repository contains pure database-tier engineering (DDL, DML, stored procedures, functions, views, query optimizations, and automated test harnesses). It is designed as a backend relational core and does not include a web application frontend or middle-tier API.

---

## 2. Key Features & Technical Highlights

- **Relational Integrity & Normalization**: 10 normalized tables across `academic` and `audit` schemas enforcing 50+ relational constraints (primary keys, foreign keys, check constraints, and unique indexes).
- **Canonical Grade Scale Architecture**: Decouples letter grades (`A+` through `F`, `P`, `W`, `I`) into dedicated entities with numeric grade points (`0.00` to `4.00`), passing status, credit-bearing indicators, and GPA inclusion rules.
- **Deterministic GPA Engine**: A schema-bound, deterministic scalar UDF (`academic.fn_CalculateStudentGPA`) and reporting views (`academic.vw_StudentAcademicSummary`) that strictly exclude non-credit grades (`W`, `I`) and handle zero-credit edge cases cleanly by returning `NULL`.
- **Concurrency-Safe Enrollment**: Stored procedure `academic.usp_EnrollStudent` uses pessimistic locks (`UPDLOCK, HOLDLOCK`) within atomic transactions to prevent race conditions during concurrent registrations for the last seat in a section.
- **Administrative vs. Dynamic Capacity Separation**: Section administrative status (`Open`, `Closed`, `Cancelled`) is decoupled from real-time occupancy. Dropping an enrollment does not inadvertently reopen an administratively closed section.
- **Auditing & Traceability**: Dedicated `audit.EnrollmentAuditLog` records lifecycle transitions (`ENROLL`, `DROP`, `WITHDRAW`) with timestamp, executing user, previous status, and business justification.
- **Temporal Table Time-Travel**: System-versioned temporal table configuration on `academic.Students` utilizing `HIDDEN` period columns (`SysStartTime`, `SysEndTime`) and companion history table `academic.StudentsHistory` for audit compliance and point-in-time state recovery.
- **Dynamic Data Masking (DDM)**: Masks sensitive PII and compensation data (`Students.Email`, `Students.Phone`, `Students.DateOfBirth`, `Instructors.Salary`) for unprivileged users.
- **Workload-Aligned Indexing**: 10 nonclustered and covering indexes designed around high-frequency queries, multi-table joins, and recursive prerequisite traversals.
- **Automated PowerShell Test Runner**: Cross-platform test suite (`tests/run_tests.ps1`) executing 66 assertions with zero data drift and exit code propagation.

---

## 3. Database Architecture & Entity Relationships

### 3.1 Entity Relationship Diagram (ERD)

```mermaid
erDiagram
    Departments ||--o{ Instructors : "employs"
    Departments ||--o{ Students : "major department"
    Departments ||--o{ Courses : "offers"
    Instructors ||--o| Departments : "heads (HeadInstructorID)"
    Instructors ||--o{ CourseSections : "teaches"
    Courses ||--o{ CoursePrerequisites : "has prerequisite"
    Courses ||--o{ CoursePrerequisites : "is prerequisite for"
    Courses ||--o{ CourseSections : "scheduled as"
    AcademicTerms ||--o{ CourseSections : "scheduled during"
    Students ||--o{ Enrollments : "registers"
    CourseSections ||--o{ Enrollments : "class roster"
    GradeScales ||--o{ CoursePrerequisites : "minimum grade"
    GradeScales ||--o{ Enrollments : "grade awarded"
    Students ..o{ EnrollmentAuditLog : "audited student"
    CourseSections ..o{ EnrollmentAuditLog : "audited section"

    Departments {
        INT DepartmentID PK
        CHAR(4) DepartmentCode UK
        VARCHAR(100) DepartmentName
        INT HeadInstructorID FK
        DECIMAL(12_2) Budget
        NVARCHAR(100) BuildingOffice
        DATETIME2 CreatedAt
    }

    Instructors {
        INT InstructorID PK
        INT DepartmentID FK
        VARCHAR(15) InstructorNumber UK
        NVARCHAR(50) FirstName
        NVARCHAR(50) LastName
        VARCHAR(100) Email UK
        DATE HireDate
        DECIMAL(10_2) Salary
        VARCHAR(30) Title
        BIT IsActive
        DATETIME2 CreatedAt
    }

    Students {
        INT StudentID PK
        INT DepartmentID FK
        VARCHAR(15) StudentNumber UK
        NVARCHAR(50) FirstName
        NVARCHAR(50) LastName
        VARCHAR(100) Email UK
        VARCHAR(20) Phone
        DATE DateOfBirth
        DATE EnrollmentDate
        VARCHAR(20) AcademicStatus
        DATETIME2 CreatedAt
    }

    AcademicTerms {
        INT TermID PK
        VARCHAR(15) TermCode UK
        VARCHAR(50) TermName
        DATE StartDate
        DATE EndDate
        DATE RegistrationOpenDate
        DATE RegistrationCloseDate
        BIT IsActive
        DATETIME2 CreatedAt
    }

    Courses {
        INT CourseID PK
        INT DepartmentID FK
        VARCHAR(10) CourseCode UK
        NVARCHAR(100) Title
        TINYINT Credits
        NVARCHAR(500) Description
        BIT IsActive
        DATETIME2 CreatedAt
    }

    CoursePrerequisites {
        INT CourseID PK_FK
        INT PrerequisiteCourseID PK_FK
        VARCHAR(3) MinimumGrade FK
        DATETIME2 CreatedAt
    }

    CourseSections {
        INT SectionID PK
        INT CourseID FK
        INT TermID FK
        INT InstructorID FK
        VARCHAR(10) SectionNumber
        INT MaxCapacity
        VARCHAR(50) Classroom
        VARCHAR(50) ScheduleDayTime
        VARCHAR(20) Status
        DATETIME2 CreatedAt
    }

    GradeScales {
        INT GradeScaleID PK
        VARCHAR(3) LetterGrade UK
        DECIMAL(5_2) MinPercentage
        DECIMAL(5_2) MaxPercentage
        DECIMAL(3_2) GradePoints
        BIT IsPassing
        BIT IsCreditBearing
        BIT IsIncludedInGPA
        DATETIME2 CreatedAt
    }

    Enrollments {
        INT EnrollmentID PK
        INT StudentID FK
        INT SectionID FK
        DATETIME2 EnrollmentDate
        VARCHAR(20) EnrollmentStatus
        VARCHAR(3) LetterGrade FK
        DECIMAL(5_2) FinalGradePercentage
        DATETIME2 CreatedAt
    }

    EnrollmentAuditLog {
        BIGINT AuditID PK
        INT EnrollmentID
        INT StudentID
        INT SectionID
        VARCHAR(20) ActionType
        VARCHAR(20) PreviousStatus
        VARCHAR(20) NewStatus
        NVARCHAR(128) ChangedBy
        DATETIME2 ChangedAt
        NVARCHAR(255) ChangeReason
    }
```

### 3.2 Schema Invariants & Design Decisions
1. **Prerequisite Grade Comparison**: Prerequisite evaluation compares numeric `GradePoints` (e.g., `2.00` for `'C'`), preventing invalid alphabetical comparisons where `'B'` would incorrectly compare after `'A'`. Direct self-prerequisite loops (`CourseID = PrerequisiteCourseID`) are blocked by check constraints.
2. **Nullable Head of Department**: The circular foreign key relationship between `Departments` and `Instructors` is resolved by allowing `Departments.HeadInstructorID` to be nullable, enabling clean initial seeding without foreign key disabling.
3. **Audit Log Persistence**: `audit.EnrollmentAuditLog` retains `StudentID` and `SectionID` as standalone integers rather than cascading deletes, ensuring audit trails remain intact even if an enrollment record is removed.

---

## 4. Repository Structure

```text
├── sql/
│   ├── 01_schema.sql        # Core DDL: Schemas, 10 tables, and 50+ relational constraints
│   ├── 02_seed.sql          # Deterministic sample dataset: Departments, faculty, students, catalog, edge cases
│   ├── 03_views.sql         # Reporting views: Summaries, capacities, transcripts, institutional metrics
│   ├── 04_queries.sql       # Advanced analytical queries: Joins, aggregations, recursive CTEs, window functions
│   ├── 05_procedures.sql    # Stored procedures: usp_EnrollStudent, usp_DropEnrollment, usp_GetStudentTranscript, usp_GetCourseRoster
│   ├── 06_functions.sql     # UDFs: fn_CalculateStudentGPA, fn_CheckPrerequisitesSatisfied, fn_GetStudentSchedule
│   ├── 07_indexes.sql       # 10 workload-aligned nonclustered and covering indexes
│   └── 08_bonus_optional.sql# System-versioned temporal table configuration and dynamic data masking
├── tests/
│   ├── run_tests.sql        # 66-assertion automated SQL regression and validation test suite
│   ├── run_tests.ps1        # Cross-platform PowerShell execution harness with error code propagation
│   └── README.md            # Detailed test suite documentation and architectural verification
├── .gitignore               # SQL Server temporary files, backups, and OS artifacts
└── README.md                # Project documentation and engineering specification
```

---

## 5. Prerequisites & Environment Setup

### Prerequisites
- **Database Engine**: Microsoft SQL Server 2022+ (Developer, Enterprise, or Standard Edition).
- **Client Tools**:
  - `sqlcmd` utility (included with SQL Server command-line utilities or SQL Server Management Studio).
  - PowerShell 5.1+ or PowerShell Core (pwsh 7+).
  - SQL Server Management Studio (SSMS 19+) or Azure Data Studio (optional, for visual querying).
- **Authentication**: Windows Integrated Authentication (`-E`) or SQL Server Authentication with `sysadmin` or `db_owner` permissions.

---

## 6. Installation & Execution Guide

### Step 1: Create the Target Database
Launch `sqlcmd` or SSMS to create a fresh development database:

```sql
-- Create a fresh database for development or testing
CREATE DATABASE SchoolDB;
GO
```

*(For running the automated test suite, create `SchoolDB_Test` instead).*

```sql
CREATE DATABASE SchoolDB_Test;
GO
```

### Step 2: Deploy Scripts in Strict Dependency Order

Execute the SQL scripts sequentially against the target database:

```cmd
:: 1. Deploy schemas, tables, and constraints
sqlcmd -S localhost -d SchoolDB -E -i .\sql\01_schema.sql

:: 2. Seed baseline reference and transactional data
sqlcmd -S localhost -d SchoolDB -E -i .\sql\02_seed.sql

:: 3. Create analytical and reporting views
sqlcmd -S localhost -d SchoolDB -E -i .\sql\03_views.sql

:: 4. (Optional) Run sample analytical queries
sqlcmd -S localhost -d SchoolDB -E -i .\sql\04_queries.sql

:: 5. Deploy transactional stored procedures
sqlcmd -S localhost -d SchoolDB -E -i .\sql\05_procedures.sql

:: 6. Deploy scalar and table-valued functions
sqlcmd -S localhost -d SchoolDB -E -i .\sql\06_functions.sql

:: 7. Build workload-aligned indexes
sqlcmd -S localhost -d SchoolDB -E -i .\sql\07_indexes.sql

:: 8. Apply temporal versioning and dynamic data masking
sqlcmd -S localhost -d SchoolDB -E -i .\sql\08_bonus_optional.sql
```

---

## 7. Automated Testing

The automated test suite runs against a dedicated test database (`SchoolDB_Test`) to guarantee that testing operations never impact production data.

### 7.1 Executing the PowerShell Test Runner

Run the test harness from PowerShell:

```powershell
# From the project root or tests/ directory:
powershell -ExecutionPolicy Bypass -File .\tests\run_tests.ps1
```

To target a named instance:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_tests.ps1 -ServerInstance "localhost\SQLEXPRESS" -Database "SchoolDB_Test"
```

### 7.2 Safety Invariants & Repeatability
- **Safety Lock**: `run_tests.sql` validates `DB_NAME()` at startup and immediately aborts if executed against any database other than `SchoolDB_Test`.
- **Isolated Fixtures**: Tests create dedicated temporary section records (`SectionNumber IN ('T97', 'T98', 'T99')`).
- **Deterministic Teardown**: Temporary sections, enrollments, and related audit records are purged in foreign-key dependency order upon test completion.
- **Zero Row Drift**: The test harness snapshots baseline row counts at initialization and verifies that all core seed table row counts remain 100% identical at the conclusion of the test.
- **Exit Code Propagation**: If any assertion fails, the suite throws SQL Error `59999`, triggering `sqlcmd -b` to return a non-zero exit code to the caller.

### 7.3 Latest Observed Test Results

```text
================================================================================
TEST EXECUTION SUMMARY
================================================================================
Total Assertions : 66
Passed           : 66
Failed           : 0
--------------------------------------------------------------------------------
Elapsed Time     : 0.61 seconds
Overall Result   : PASSED
Database Drift   : 0 rows (Baseline seed row counts verified 100% intact)
```

---

## 8. Sample Usage & API Demonstrations

### 8.1 Transactional Student Enrollment (`usp_EnrollStudent`)

```sql
USE SchoolDB;
GO

DECLARE @NewEnrollmentID INT;

-- Enroll Student 1 into Section 1 (CS101-01)
EXEC [academic].[usp_EnrollStudent]
    @StudentID = 1,
    @SectionID = 1,
    @EnrolledBy = N'RegistrarUser',
    @NewEnrollmentID = @NewEnrollmentID OUTPUT;

SELECT @NewEnrollmentID AS GeneratedEnrollmentID;
```

*Error handling: If the section is full, the student is suspended, prerequisites are unmet, or the section is closed, a descriptive business exception (Errors `51001`–`51008`) is raised and the transaction is cleanly rolled back.*

### 8.2 Dropping an Enrollment (`usp_DropEnrollment`)

```sql
EXEC [academic].[usp_DropEnrollment]
    @StudentID = 1,
    @SectionID = 1,
    @Reason = N'Student schedule conflict',
    @DroppedBy = N'RegistrarUser';
```

*Administrative status is preserved: if the section was administratively marked `'Closed'`, dropping a student does NOT inadvertently revert it to `'Open'`.*

### 8.3 Student Transcript Generation (`usp_GetStudentTranscript`)

```sql
-- Retrieve official two-part transcript for Sophia Chen (StudentID = 1)
EXEC [academic].[usp_GetStudentTranscript] @StudentID = 1;
```

*Returns two result sets:*
1. *Academic Profile Summary: Cumulative GPA (`4.00`), total credits earned (`8`), and GPA credits attempted (`8`).*
2. *Chronological Course History: Course codes, titles, terms, grades, quality points, and credit-bearing flags.*

### 8.4 Section Roster Retrieval (`usp_GetCourseRoster`)

```sql
-- Retrieve active class roster and capacity statistics for Section 1
EXEC [academic].[usp_GetCourseRoster]
    @SectionID = 1,
    @IncludeInactive = 0;
```

### 8.5 Scalar Function: GPA Calculation (`fn_CalculateStudentGPA`)

```sql
-- Query student GPA directly
SELECT
    StudentID,
    StudentNumber,
    FirstName + N' ' + LastName AS StudentName,
    [academic].[fn_CalculateStudentGPA](StudentID) AS CumulativeGPA
FROM [academic].[Students]
WHERE StudentID IN (1, 16, 23);
```

### 8.6 Table-Valued Function: Student Schedule (`fn_GetStudentSchedule`)

```sql
-- Get active term schedule for Student 1
SELECT * FROM [academic].[fn_GetStudentSchedule](1, NULL);
```

### 8.7 Reporting View: Section Capacity (`vw_CourseEnrollmentStatus`)

```sql
SELECT
    CourseCode,
    SectionNumber,
    InstructorName,
    MaxCapacity,
    ActiveEnrolledCount,
    SeatsAvailable,
    CapacityStatus
FROM [academic].[vw_CourseEnrollmentStatus]
WHERE TermCode = '2026-FALL';
```

---

## 9. Security, Temporal Tables & Data Masking Details

### 9.1 Temporal Table History (`FOR SYSTEM_TIME`)
System versioning is enabled on `academic.Students` using `academic.StudentsHistory`.
- **Querying Historical States**:
  ```sql
  -- Query student details as of a specific point in time
  SELECT StudentID, StudentNumber, FirstName, LastName, AcademicStatus, SysStartTime, SysEndTime
  FROM [academic].[Students]
  FOR SYSTEM_TIME AS OF '2026-10-23 18:00:00';
  ```
- **Period Columns**: `SysStartTime` and `SysEndTime` are configured as `HIDDEN`, preventing them from appearing in `SELECT *` or breaking existing view contracts.
- **Scope Note**: System versioning applies strictly to `academic.Students`. It does not track changes to child tables (`Enrollments`, `CourseSections`), which are tracked via `audit.EnrollmentAuditLog`.

### 9.2 Dynamic Data Masking (DDM) Policy
Dynamic Data Masking obfuscates sensitive data in query results for unprivileged users:
- `Students.Email`: Masked using `email()` (`sXXX@XXXX.com`).
- `Students.Phone`: Masked using `default()`.
- `Students.DateOfBirth`: Masked using `default()` (`1900-01-01`).
- `Instructors.Salary`: Masked using `default()` (`0.00`).

> [!WARNING]
> **Data Masking is NOT Access Control**: Dynamic Data Masking is a presentation-layer obfuscation feature intended to prevent casual data exposure. It does not encrypt data at rest, and users with `SELECT` permissions on unmasked columns or ad-hoc query capabilities can infer values through brute-force WHERE clauses unless proper column-level permissions (`REVOKE UNMASK`) and role-based access control (RBAC) are strictly enforced.

---

## 10. Future Improvements

1. **Waitlist Management Engine**: Extend `CourseSections` and `Enrollments` with an automated FIFO waitlist that promotes students when seats become available.
2. **Degree Audit Subsystem**: Add major/minor core curriculum requirements and evaluate graduation eligibility dynamically.
3. **Role-Based Access Control (RBAC) Scripting**: Provide dedicated database roles (`RegistrarRole`, `AdvisorRole`, `FacultyRole`, `StudentRole`) with granular object permissions.
4. **Partitioning Strategy**: Partition `audit.EnrollmentAuditLog` and `academic.StudentsHistory` by calendar year to support petabyte-scale archival.
5. **CI/CD Integration**: Add a GitHub Actions workflow using Docker (`mcr.microsoft.com/mssql/server:2022-latest`) to execute `tests/run_tests.ps1` automatically on pull requests.

---

## 11. Attribution & License

- **Author**: Kerolosrafat
- **Target Platform**: Microsoft SQL Server 2022+
- **License**: MIT License (educational and portfolio demonstration use).
