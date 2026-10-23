# Automated Test Suite: SchoolDB_Test

Comprehensive regression and business-rule validation suite for the **University Course and Student Management Database** (`SchoolDB`), targeting **Microsoft SQL Server 2022+**.

---

## 1. Prerequisites

Before running the test suite, ensure:
1. **Microsoft SQL Server 2022+** is running locally or accessible on the network.
2. **`sqlcmd` utility** is installed and accessible in your system `PATH`.
3. The dedicated test database **`SchoolDB_Test`** exists and has been initialized with the project scripts:
   - `sql/01_schema.sql`
   - `sql/02_seed.sql`
   - `sql/03_views.sql`
   - `sql/04_queries.sql`
   - `sql/05_procedures.sql`
   - `sql/06_functions.sql`
   - `sql/07_indexes.sql`
   - `sql/08_bonus_optional.sql`
4. Windows Integrated Authentication (`-E`) has appropriate `db_owner` or administrative permissions on `SchoolDB_Test`.

> [!IMPORTANT]
> The test runner and test scripts strictly target `SchoolDB_Test` and will refuse to execute against any system database or production database (`SchoolDB`).

---

## 2. Test Execution

### Option A: Using the PowerShell Test Runner (Recommended)

From the project root directory or the `tests/` directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_tests.ps1
```

Or targeting a named SQL Server instance:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_tests.ps1 -ServerInstance "localhost\SQLEXPRESS"
```

### Option B: Using SQLCMD Directly

```cmd
sqlcmd -S localhost -d SchoolDB_Test -E -b -i .\tests\run_tests.sql
```

*(The `-b` flag ensures `sqlcmd` exits with a nonzero error code if any assertion fails).*

---

## 3. Test Coverage & Assertion Categories

The test suite evaluates **66 distinct assertions** across 8 critical architectural layers:

1. **Schema & Constraints (Asserts 1–10)**:
   - Table presence, column counts, and primary keys across all 10 core tables.
   - Domain check constraints (salary > 0, budget $\ge$ 0, capacity > 0, grade points between 0.00 and 4.00).
   - Relational invariants (unique student-section registration constraint `UQ_Enrollments_Student_Section`, prerequisite self-loop prevention `CK_CoursePrerequisites_NoDirectSelfLoop`).
   - Relational foreign key count verification (all 13 foreign keys across `academic` and `audit` schemas).

2. **Baseline Seed Data & Edge Cases (Asserts 11–21)**:
   - Baseline entities: exactly 5 departments, 4 terms, 1 active term, 11 instructors, 25 students, 15 courses, 8 prerequisites, and 15 grade scales.
   - Edge case validation: students with 0 enrollments, catalog courses with 0 scheduled sections, and fully occupied sections (Section 15 at 3/3 capacity).

3. **Operational Views (Asserts 22–28)**:
   - `vw_StudentAcademicSummary`: Completeness (preserves all 25 students via `LEFT JOIN`), accurate GPA calculations, and strict `NULL` policy for students with 0 GPA credits.
   - `vw_CourseEnrollmentStatus`: Real-time active headcount and accurate classification of `FULL` vs. `EMPTY` sections.
   - `vw_DepartmentPerformance`: Institutional metrics across all 5 academic departments.
   - `vw_StudentTranscripts`: Chronological academic course history and quality points calculations.

4. **User-Defined Functions (Asserts 29–34)**:
   - `academic.fn_CalculateStudentGPA`: Parity against summary view across all 25 students and `NULL` handling for non-enrolled students.
   - `academic.fn_CheckPrerequisitesSatisfied`: Evaluates passing ('A'), failing ('F'), and courses with zero prerequisites.
   - `academic.fn_GetStudentSchedule`: Active term course retrieval.

5. **Stored Procedures & Business Rules (Asserts 35–48)**:
   - `usp_EnrollStudent`: Valid enrollment, duplicate enrollment rejection, non-existent student rejection (51001), closed section rejection (51004), cancelled section rejection (51004), capacity limit enforcement (51008), unmet prerequisite rejection (51007), ineligible student rejection (51002).
   - `usp_DropEnrollment`: Status update to `'Dropped'`, administrative status preservation (does not reopen intentionally closed sections).
   - `usp_GetStudentTranscript`: Valid student execution and non-existent student rejection (51020).
   - `usp_GetCourseRoster`: Valid section execution and non-existent section rejection (51030).

6. **Audit Trail & Rollback Integrity (Asserts 49–52)**:
   - Successful enrollments and drops write audit records to `audit.EnrollmentAuditLog`.
   - Audit trail rejection isolation: rejected operations do not leave false audit records.
   - Deterministic cleanup: baseline audit log row count strictly preserved after teardown.

7. **Temporal History & Dynamic Data Masking (Asserts 53–59)**:
   - System versioning metadata (`temporal_type = 2`) on `academic.Students` and existence of companion history table `academic.StudentsHistory`.
   - Verification of `HIDDEN` period columns (`SysStartTime`, `SysEndTime`).
   - `FOR SYSTEM_TIME ALL` queryability across baseline records.
   - Active Dynamic Data Masking (`is_masked = 1`) on `Students.Email`, `Students.DateOfBirth`, and `Instructors.Salary`.

8. **Strategic Indexes & Key Column Integrity (Asserts 60–66)**:
   - Covering indexes with explicit key column order verification: `IX_Enrollments_SectionID_Status` (`SectionID`, `EnrollmentStatus`) and `IX_Enrollments_StudentID_Status` (`StudentID`, `EnrollmentStatus`).
   - Section term filter index `IX_CourseSections_TermID_Status` (`TermID`, `Status`).
   - Prerequisite reverse lookup index `IX_CoursePrerequisites_PrerequisiteCourseID`.
   - Foreign key department indexes (`IX_Students_DepartmentID`, `IX_Courses_DepartmentID`, `IX_Instructors_DepartmentID`).
   - Faculty section assignment index `IX_CourseSections_InstructorID`.
   - Audit log nonclustered indexes (`IX_EnrollmentAuditLog_StudentID_ChangedAt`, `IX_EnrollmentAuditLog_SectionID`).

---

## 4. Safety & Repeatability Design

- **Isolated Test Fixtures**: Dynamic test operations create dedicated temporary sections (`SectionNumber = 'T99'`, `'T98'`, `'T97'`) and use designated test students.
- **Deterministic Teardown**: The test suite guarantees that all temporary sections, enrollments, and related audit records are purged at completion.
- **Baseline Invariant Check**: The test harness measures baseline table counts at the start and asserts at the end that table counts are 100% identical.
- **Repeatable & Idempotent**: The suite can be executed repeatedly without causing database drift.
