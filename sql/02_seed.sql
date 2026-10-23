/*
================================================================================
SCRIPT: 02_seed.sql
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+
DESCRIPTION:
    Seeds realistic, internally consistent sample data into the database.
    Includes comprehensive edge cases required for realistic testing:
    - Multi-tier prerequisite chains (CS and Math)
    - Students without any enrollments (freshly admitted students)
    - Courses without any scheduled sections
    - Instructors without assigned sections (sabbatical / research faculty)
    - A full section (at maximum capacity for testing concurrency/rejection)
    - Varied enrollment outcomes (A, B, C, D, F, I, W, Dropped, Active)
    - Students across diverse academic statuses (Active, Probation, Suspended, Graduated)
================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

-- -----------------------------------------------------------------------------
-- 1. Seed Departments
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [academic].[Departments] WHERE [DepartmentCode] = 'CS')
BEGIN
    INSERT INTO [academic].[Departments]
        ([DepartmentCode], [DepartmentName], [Budget], [OfficeLocation], [EstablishedDate])
    VALUES
        ('CS',   N'Computer Science & Engineering', 1850000.00, N'Turing Hall 300',     '1985-09-01'),
        ('MATH', N'Mathematics & Statistics',       1200000.00, N'Euler Science Bldg 2', '1970-08-15'),
        ('ENG',  N'Electrical Engineering',         1650000.00, N'Tesla Hall 101',       '1980-01-10'),
        ('BIO',  N'Biological Sciences',            1400000.00, N'Darwin Life Bldg 4',   '1975-06-01'),
        ('BUS',  N'School of Business',             2100000.00, N'Smith Hall 500',       '1990-09-15');

    PRINT 'Inserted 5 departments.';
END;
GO

-- -----------------------------------------------------------------------------
-- 2. Seed Academic Terms
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [academic].[AcademicTerms] WHERE [TermCode] = '2025-FALL')
BEGIN
    INSERT INTO [academic].[AcademicTerms]
        ([TermCode], [TermName], [StartDate], [EndDate], [RegistrationOpenDate], [RegistrationCloseDate], [IsActive])
    VALUES
        ('2025-FALL',   N'Fall Semester 2025',   '2025-08-25', '2025-12-19', '2025-06-01', '2025-09-05', 0),
        ('2026-SPRING', N'Spring Semester 2026', '2026-01-12', '2026-05-08', '2025-11-01', '2026-01-23', 0),
        ('2026-FALL',   N'Fall Semester 2026',   '2026-08-24', '2026-12-18', '2026-06-01', '2026-11-15', 1),
        ('2027-SPRING', N'Spring Semester 2027', '2027-01-11', '2027-05-07', '2026-11-01', '2027-01-22', 0);

    PRINT 'Inserted 4 academic terms.';
END;
GO

-- -----------------------------------------------------------------------------
-- 3. Seed Instructors
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [academic].[Instructors] WHERE [InstructorNumber] = 'INS-1001')
BEGIN
    DECLARE @DeptCS   INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'CS');
    DECLARE @DeptMATH INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'MATH');
    DECLARE @DeptENG  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'ENG');
    DECLARE @DeptBIO  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'BIO');
    DECLARE @DeptBUS  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'BUS');

    INSERT INTO [academic].[Instructors]
        ([InstructorNumber], [FirstName], [LastName], [Email], [Phone], [HireDate], [DepartmentID], [OfficeRoom], [Title], [Salary], [IsActive])
    VALUES
        ('INS-1001', N'Alan',      N'Turing',     N'a.turing@university.edu',     N'555-0101', '2010-08-15', @DeptCS,   N'TH-301', N'Professor',           135000.00, 1),
        ('INS-1002', N'Grace',     N'Hopper',     N'g.hopper@university.edu',     N'555-0102', '2012-01-10', @DeptCS,   N'TH-305', N'Professor',           132000.00, 1),
        ('INS-1003', N'Ada',       N'Lovelace',   N'a.lovelace@university.edu',   N'555-0103', '2018-08-20', @DeptCS,   N'TH-312', N'Associate Professor', 105000.00, 1),
        ('INS-1004', N'Donald',    N'Knuth',      N'd.knuth@university.edu',      N'555-0104', '2015-08-15', @DeptCS,   N'TH-318', N'Professor',           140000.00, 1),
        ('INS-1005', N'Leonhard',  N'Euler',      N'l.euler@university.edu',      N'555-0201', '2008-09-01', @DeptMATH, N'EB-201', N'Professor',           128000.00, 1),
        ('INS-1006', N'Carl',      N'Gauss',      N'c.gauss@university.edu',      N'555-0202', '2014-08-15', @DeptMATH, N'EB-205', N'Associate Professor', 102000.00, 1),
        ('INS-1007', N'Nikola',    N'Tesla',      N'n.tesla@university.edu',      N'555-0301', '2011-03-01', @DeptENG,  N'TE-102', N'Professor',           129000.00, 1),
        ('INS-1008', N'Claude',    N'Shannon',    N'c.shannon@university.edu',    N'555-0302', '2019-01-15', @DeptENG,  N'TE-108', N'Assistant Professor',  92000.00, 1),
        ('INS-1009', N'Rosalind',  N'Franklin',   N'r.franklin@university.edu',   N'555-0401', '2016-08-15', @DeptBIO,  N'DL-401', N'Associate Professor', 104000.00, 1),
        ('INS-1010', N'Adam',      N'Smith',      N'a.smith@university.edu',      N'555-0501', '2013-08-15', @DeptBUS,  N'SH-501', N'Professor',           125000.00, 1),
        -- Edge Case: Instructor on research sabbatical with NO teaching sections assigned
        ('INS-1011', N'Barbara',   N'Liskov',     N'b.liskov@university.edu',     N'555-0111', '2017-01-10', @DeptCS,   N'TH-325', N'Professor',           138000.00, 1);

    PRINT 'Inserted 11 instructors (including 1 sabbatical faculty with no sections).';

    -- Assign Department Heads
    UPDATE [academic].[Departments] SET [HeadOfDepartmentID] = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1001') WHERE DepartmentCode = 'CS';
    UPDATE [academic].[Departments] SET [HeadOfDepartmentID] = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1005') WHERE DepartmentCode = 'MATH';
    UPDATE [academic].[Departments] SET [HeadOfDepartmentID] = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1007') WHERE DepartmentCode = 'ENG';
    UPDATE [academic].[Departments] SET [HeadOfDepartmentID] = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1009') WHERE DepartmentCode = 'BIO';
    UPDATE [academic].[Departments] SET [HeadOfDepartmentID] = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1010') WHERE DepartmentCode = 'BUS';

    PRINT 'Department heads assigned.';
END;
GO

-- -----------------------------------------------------------------------------
-- 4. Seed Students
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [academic].[Students] WHERE [StudentNumber] = 'STU-2023-0001')
BEGIN
    DECLARE @DeptCS   INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'CS');
    DECLARE @DeptMATH INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'MATH');
    DECLARE @DeptENG  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'ENG');
    DECLARE @DeptBIO  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'BIO');
    DECLARE @DeptBUS  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'BUS');

    INSERT INTO [academic].[Students]
        ([StudentNumber], [FirstName], [LastName], [Email], [DateOfBirth], [EnrollmentDate], [DepartmentID], [AcademicStatus])
    VALUES
        -- Senior students (started 2023)
        ('STU-2023-0001', N'Sophia',    N'Chen',       N's.chen@student.edu',       '2004-03-15', '2023-08-20', @DeptCS,   'Active'),
        ('STU-2023-0002', N'Marcus',    N'Johnson',    N'm.johnson@student.edu',    '2003-11-22', '2023-08-20', @DeptCS,   'Active'),
        ('STU-2023-0003', N'Elena',     N'Rostova',    N'e.rostova@student.edu',    '2004-07-08', '2023-08-20', @DeptMATH, 'Active'),
        ('STU-2023-0004', N'David',     N'Kim',        N'd.kim@student.edu',        '2003-05-30', '2023-08-20', @DeptENG,  'Active'),
        ('STU-2023-0005', N'Maya',      N'Patel',      N'm.patel@student.edu',      '2004-01-14', '2023-08-20', @DeptBIO,  'Active'),

        -- Junior students (started 2024)
        ('STU-2024-0006', N'Liam',      N'O''Connor',  N'l.oconnor@student.edu',    '2005-09-12', '2024-08-18', @DeptCS,   'Active'),
        ('STU-2024-0007', N'Zoe',       N'Washington', N'z.washington@student.edu', '2004-12-03', '2024-08-18', @DeptCS,   'Active'),
        ('STU-2024-0008', N'Lucas',     N'Silva',      N'l.silva@student.edu',      '2005-04-25', '2024-08-18', @DeptMATH, 'Active'),
        ('STU-2024-0009', N'Aisha',     N'Al-Mansoor', N'a.almansoor@student.edu',  '2005-02-18', '2024-08-18', @DeptENG,  'Active'),
        ('STU-2024-0010', N'Benjamin',  N'Taylor',     N'b.taylor@student.edu',     '2004-10-09', '2024-08-18', @DeptBUS,  'Active'),

        -- Sophomore students (started 2025)
        ('STU-2025-0011', N'Noah',      N'Miller',     N'n.miller@student.edu',     '2006-06-19', '2025-08-22', @DeptCS,   'Active'),
        ('STU-2025-0012', N'Olivia',    N'Garcia',     N'o.garcia@student.edu',     '2006-08-14', '2025-08-22', @DeptCS,   'Active'),
        ('STU-2025-0013', N'Alexander', N'Wright',     N'a.wright@student.edu',     '2005-11-30', '2025-08-22', @DeptCS,   'Active'),
        ('STU-2025-0014', N'Emma',      N'Davis',      N'e.davis@student.edu',      '2006-03-27', '2025-08-22', @DeptMATH, 'Active'),
        ('STU-2025-0015', N'James',     N'Wilson',     N'j.wilson@student.edu',     '2005-08-04', '2025-08-22', @DeptENG,  'Active'),

        -- Edge Case: Student on Academic Probation (low cumulative GPA)
        ('STU-2024-0016', N'Devon',     N'Brooks',     N'd.brooks@student.edu',     '2004-06-20', '2024-08-18', @DeptCS,   'Probation'),

        -- Edge Case: Suspended student (cannot enroll)
        ('STU-2024-0017', N'Victor',    N'Stone',      N'v.stone@student.edu',      '2005-01-11', '2024-08-18', @DeptBUS,  'Suspended'),

        -- Edge Case: Graduated student
        ('STU-2022-0018', N'Rachel',    N'Green',      N'r.green@student.edu',      '2002-04-12', '2022-08-21', @DeptCS,   'Graduated'),

        -- Edge Case: Withdrawn student
        ('STU-2024-0019', N'Tyler',     N'Durden',     N't.durden@student.edu',     '2003-10-15', '2024-08-18', @DeptBUS,  'Withdrawn'),

        -- Freshman students (started 2026)
        ('STU-2026-0020', N'Chloe',     N'Bennett',    N'c.bennett@student.edu',    '2007-02-14', '2026-08-20', @DeptCS,   'Active'),
        ('STU-2026-0021', N'Daniel',    N'Morales',    N'd.morales@student.edu',    '2007-05-18', '2026-08-20', @DeptCS,   'Active'),
        ('STU-2026-0022', N'Hannah',    N'Abbott',     N'h.abbott@student.edu',     '2007-09-01', '2026-08-20', @DeptBIO,  'Active'),

        -- Edge Cases: Students with ZERO enrollments (admitted, but not yet registered)
        ('STU-2026-0023', N'Samuel',    N'Tarley',     N's.tarley@student.edu',     '2007-04-10', '2026-08-20', @DeptCS,   'Active'),
        ('STU-2026-0024', N'Arya',      N'Stark',      N'a.stark@student.edu',      '2007-12-05', '2026-08-20', @DeptMATH, 'Active'),
        ('STU-2026-0025', N'Jon',       N'Snow',       N'j.snow@student.edu',       '2006-10-31', '2026-08-20', @DeptENG,  'Active');

    PRINT 'Inserted 25 students (including active, probation, suspended, graduated, withdrawn, and 3 without enrollments).';
END;
GO

-- -----------------------------------------------------------------------------
-- 5. Seed Courses
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [academic].[Courses] WHERE [CourseCode] = 'CS101')
BEGIN
    DECLARE @DeptCS   INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'CS');
    DECLARE @DeptMATH INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'MATH');
    DECLARE @DeptENG  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'ENG');
    DECLARE @DeptBIO  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'BIO');
    DECLARE @DeptBUS  INT = (SELECT DepartmentID FROM [academic].[Departments] WHERE DepartmentCode = 'BUS');

    INSERT INTO [academic].[Courses]
        ([CourseCode], [Title], [Description], [Credits], [DepartmentID])
    VALUES
        -- Computer Science Prerequisite Tree
        ('CS101',   N'Introduction to Computer Science',   N'Fundamental concepts of programming and computational thinking.', 4, @DeptCS),
        ('CS201',   N'Data Structures & Algorithms',       N'Linear and non-linear data structures, complexity analysis.',      4, @DeptCS),
        ('CS301',   N'Database Management Systems',        N'Relational algebra, SQL, normalization, concurrency control.',     3, @DeptCS),
        ('CS305',   N'Operating Systems & Architecture',   N'Processes, threads, memory management, file systems.',             4, @DeptCS),
        ('CS401',   N'Advanced Software Engineering',      N'Architecture patterns, CI/CD, microservices, capstone project.',  3, @DeptCS),

        -- Mathematics Prerequisite Tree
        ('MATH101', N'Calculus I',                         N'Limits, derivatives, applications of differentiation.',            4, @DeptMATH),
        ('MATH201', N'Calculus II',                        N'Techniques of integration, infinite series, power series.',        4, @DeptMATH),
        ('MATH301', N'Linear Algebra',                     N'Vector spaces, linear transformations, eigenvalues, matrices.',    3, @DeptMATH),
        ('MATH350', N'Probability & Statistics',           N'Discrete and continuous distributions, estimation, hypothesis.',   3, @DeptMATH),

        -- Engineering
        ('ENG101',  N'Introduction to Circuits',           N'DC/AC circuit analysis, Ohm’s law, Kirchhoff’s laws.',             4, @DeptENG),
        ('ENG205',  N'Digital Logic Design',               N'Boolean algebra, combinational and sequential logic circuits.',    3, @DeptENG),

        -- Biology & Business
        ('BIO101',  N'General Biology I',                  N'Cellular biology, genetics, and molecular biology.',               4, @DeptBIO),
        ('BUS101',  N'Principles of Management',           N'Organizational behavior, managerial decision making.',             3, @DeptBUS),

        -- Edge Case: Course offered in catalog, but NEVER scheduled in any term/section
        ('CS499',   N'Senior Honors Thesis Research',      N'Independent original computational research under faculty chair.', 3, @DeptCS),
        ('BIO390',  N'Special Topics in Genomics',         N'Emerging computational techniques in CRISPR and gene editing.',    3, @DeptBIO);

    PRINT 'Inserted 15 courses (including 2 courses never offered in sections).';
END;
GO

-- -----------------------------------------------------------------------------
-- 6. Seed Course Prerequisites
--    Hierarchical chains:
--    CS101 -> CS201 -> CS301 -> CS401
--    MATH101 -> MATH201 -> MATH301
--    CS201 + MATH301 -> CS305
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [academic].[CoursePrerequisites])
BEGIN
    DECLARE @CS101   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS101');
    DECLARE @CS201   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS201');
    DECLARE @CS301   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS301');
    DECLARE @CS305   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS305');
    DECLARE @CS401   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS401');
    DECLARE @MATH101 INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'MATH101');
    DECLARE @MATH201 INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'MATH201');
    DECLARE @MATH301 INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'MATH301');
    DECLARE @MATH350 INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'MATH350');
    DECLARE @ENG205  INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'ENG205');
    DECLARE @ENG101  INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'ENG101');

    INSERT INTO [academic].[CoursePrerequisites]
        ([CourseID], [PrerequisiteCourseID], [MinimumGrade])
    VALUES
        (@CS201,   @CS101,   'C'),  -- Data Structures requires CS101 with >= C
        (@CS301,   @CS201,   'C'),  -- Database Systems requires CS201 with >= C
        (@CS305,   @CS201,   'C'),  -- OS requires Data Structures with >= C
        (@CS401,   @CS301,   'B'),  -- Adv SE requires Databases with >= B
        (@MATH201, @MATH101, 'C'),  -- Calc II requires Calc I with >= C
        (@MATH301, @MATH201, 'C'),  -- Linear Algebra requires Calc II with >= C
        (@MATH350, @MATH101, 'C'),  -- Prob & Stats requires Calc I with >= C
        (@ENG205,  @ENG101,  'C');  -- Digital Logic requires Intro Circuits with >= C

    PRINT 'Inserted 8 course prerequisite rules.';
END;
GO

-- -----------------------------------------------------------------------------
-- 7. Seed Course Sections
--    Spanning past terms (2025-FALL, 2026-SPRING) and active term (2026-FALL)
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [academic].[CourseSections])
BEGIN
    DECLARE @Term25Fall INT = (SELECT TermID FROM [academic].[AcademicTerms] WHERE TermCode = '2025-FALL');
    DECLARE @Term26Spr  INT = (SELECT TermID FROM [academic].[AcademicTerms] WHERE TermCode = '2026-SPRING');
    DECLARE @Term26Fall INT = (SELECT TermID FROM [academic].[AcademicTerms] WHERE TermCode = '2026-FALL');

    DECLARE @CS101   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS101');
    DECLARE @CS201   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS201');
    DECLARE @CS301   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS301');
    DECLARE @CS305   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS305');
    DECLARE @CS401   INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'CS401');
    DECLARE @MATH101 INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'MATH101');
    DECLARE @MATH201 INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'MATH201');
    DECLARE @MATH301 INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'MATH301');
    DECLARE @ENG101  INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'ENG101');
    DECLARE @BIO101  INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'BIO101');
    DECLARE @BUS101  INT = (SELECT CourseID FROM [academic].[Courses] WHERE CourseCode = 'BUS101');

    DECLARE @InsTuring   INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1001');
    DECLARE @InsHopper   INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1002');
    DECLARE @InsLovelace INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1003');
    DECLARE @InsKnuth    INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1004');
    DECLARE @InsEuler    INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1005');
    DECLARE @InsGauss    INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1006');
    DECLARE @InsTesla    INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1007');
    DECLARE @InsShannon  INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1008');
    DECLARE @InsFranklin INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1009');
    DECLARE @InsSmith    INT = (SELECT InstructorID FROM [academic].[Instructors] WHERE InstructorNumber = 'INS-1010');

    INSERT INTO [academic].[CourseSections]
        ([CourseID], [TermID], [InstructorID], [SectionNumber], [MaxCapacity], [Classroom], [ScheduleDayTime], [Status])
    VALUES
        -- Term 2025-FALL sections (Completed historical terms)
        (@CS101,   @Term25Fall, @InsTuring,   '01', 35, N'Turing Hall 101', N'MWF 09:00-10:00', 'Closed'), -- Sec 1
        (@MATH101, @Term25Fall, @InsEuler,    '01', 30, N'Euler Hall 201',  N'TR 10:00-11:30',  'Closed'), -- Sec 2
        (@ENG101,  @Term25Fall, @InsTesla,    '01', 25, N'Tesla Hall 105',  N'MWF 11:00-12:00', 'Closed'), -- Sec 3
        (@BIO101,  @Term25Fall, @InsFranklin, '01', 30, N'Darwin Hall 301', N'TR 13:00-14:30',  'Closed'), -- Sec 4

        -- Term 2026-SPRING sections (Completed historical terms)
        (@CS201,   @Term26Spr,  @InsHopper,   '01', 30, N'Turing Hall 102', N'MWF 10:00-11:00', 'Closed'), -- Sec 5
        (@MATH201, @Term26Spr,  @InsGauss,    '01', 28, N'Euler Hall 202',  N'TR 09:30-11:00',  'Closed'), -- Sec 6
        (@CS101,   @Term26Spr,  @InsLovelace, '01', 35, N'Turing Hall 101', N'TR 13:00-14:30',  'Closed'), -- Sec 7
        (@BUS101,  @Term26Spr,  @InsSmith,    '01', 40, N'Smith Hall 401',  N'MWF 14:00-15:00', 'Closed'), -- Sec 8

        -- Term 2026-FALL sections (CURRENT ACTIVE TERM)
        (@CS301,   @Term26Fall, @InsLovelace, '01', 25, N'Turing Hall 204', N'MWF 10:00-11:00', 'Open'),   -- Sec 9
        (@CS201,   @Term26Fall, @InsHopper,   '01', 30, N'Turing Hall 102', N'TR 10:00-11:30',  'Open'),   -- Sec 10
        (@CS101,   @Term26Fall, @InsTuring,   '01', 35, N'Turing Hall 101', N'MWF 09:00-10:00', 'Open'),   -- Sec 11
        (@MATH301, @Term26Fall, @InsEuler,    '01', 25, N'Euler Hall 205',  N'TR 14:00-15:30',  'Open'),   -- Sec 12
        (@ENG101,  @Term26Fall, @InsTesla,    '01', 25, N'Tesla Hall 105',  N'MWF 13:00-14:00', 'Open'),   -- Sec 13
        (@BUS101,  @Term26Fall, @InsSmith,    '01', 30, N'Smith Hall 401',  N'TR 11:00-12:30',  'Open'),   -- Sec 14

        -- Edge Case 1: FULL SECTION (Capacity = 3, exactly 3 active students)
        -- Used for testing capacity enforcement & race conditions
        (@CS401,   @Term26Fall, @InsKnuth,    '01',  3, N'Turing Seminar',  N'M 15:00-18:00',   'Closed'), -- Sec 15 (Full)

        -- Edge Case 2: SECTION WITH 0 ENROLLMENTS (Open, but no one enrolled)
        (@BIO101,  @Term26Fall, @InsFranklin, '01', 30, N'Darwin Hall 301', N'TR 08:30-10:00',  'Open');   -- Sec 16 (Empty)

    PRINT 'Inserted 16 course sections across 3 terms (including a full section and an empty section).';
END;
GO

-- -----------------------------------------------------------------------------
-- 8. Seed Enrollments
--    Demonstrates:
--    - Historical completed courses with letter grades (A, B, C, D, F)
--    - Active current enrollments
--    - Incomplete enrollment ('I')
--    - Dropped enrollment
--    - Official withdrawal ('W')
--    - Full section with 3 active enrollments
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [academic].[Enrollments])
BEGIN
    -- Student IDs
    DECLARE @S1  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2023-0001'); -- Sophia Chen
    DECLARE @S2  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2023-0002'); -- Marcus Johnson
    DECLARE @S3  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2023-0003'); -- Elena Rostova
    DECLARE @S4  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2023-0004'); -- David Kim
    DECLARE @S5  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2023-0005'); -- Maya Patel
    DECLARE @S6  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2024-0006'); -- Liam O'Connor
    DECLARE @S7  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2024-0007'); -- Zoe Washington
    DECLARE @S8  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2024-0008'); -- Lucas Silva
    DECLARE @S9  INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2024-0009'); -- Aisha Al-Mansoor
    DECLARE @S10 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2024-0010'); -- Benjamin Taylor
    DECLARE @S11 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2025-0011'); -- Noah Miller
    DECLARE @S12 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2025-0012'); -- Olivia Garcia
    DECLARE @S13 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2025-0013'); -- Alexander Wright
    DECLARE @S14 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2025-0014'); -- Emma Davis
    DECLARE @S15 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2025-0015'); -- James Wilson
    DECLARE @S16 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2024-0016'); -- Devon Brooks (Probation)
    DECLARE @S18 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2022-0018'); -- Rachel Green (Graduated)
    DECLARE @S19 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2024-0019'); -- Tyler Durden (Withdrawn)
    DECLARE @S20 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2026-0020'); -- Chloe Bennett (Freshman)
    DECLARE @S21 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2026-0021'); -- Daniel Morales (Freshman)
    DECLARE @S22 INT = (SELECT StudentID FROM [academic].[Students] WHERE StudentNumber = 'STU-2026-0022'); -- Hannah Abbott (Freshman)

    -- Section IDs
    DECLARE @Sec1_CS101_25F   INT = 1;
    DECLARE @Sec2_M101_25F    INT = 2;
    DECLARE @Sec3_E101_25F    INT = 3;
    DECLARE @Sec4_B101_25F    INT = 4;
    DECLARE @Sec5_CS201_26S   INT = 5;
    DECLARE @Sec6_M201_26S    INT = 6;
    DECLARE @Sec7_CS101_26S   INT = 7;
    DECLARE @Sec8_BUS101_26S  INT = 8;
    DECLARE @Sec9_CS301_26F   INT = 9;
    DECLARE @Sec10_CS201_26F  INT = 10;
    DECLARE @Sec11_CS101_26F  INT = 11;
    DECLARE @Sec12_M301_26F   INT = 12;
    DECLARE @Sec13_E101_26F   INT = 13;
    DECLARE @Sec14_BUS101_26F INT = 14;
    DECLARE @Sec15_CS401_26F  INT = 15; -- Full section (Cap: 3)
    DECLARE @Sec16_B101_26F   INT = 16; -- Empty section (Cap: 30)

    INSERT INTO [academic].[Enrollments]
        ([StudentID], [SectionID], [EnrollmentDate], [EnrollmentStatus], [LetterGrade], [Notes])
    VALUES
        -- ---------------------------------------------------------------------
        -- 2025-FALL Historical Enrollments (All completed/graded)
        -- ---------------------------------------------------------------------
        (@S1,  @Sec1_CS101_25F, '2025-08-26 09:00', 'Completed', 'A',  N'Honor roll performance.'),
        (@S2,  @Sec1_CS101_25F, '2025-08-26 09:05', 'Completed', 'B+', N'Solid analytical work.'),
        (@S3,  @Sec2_M101_25F,  '2025-08-26 09:10', 'Completed', 'A',  N'Top score in calculus.'),
        (@S4,  @Sec3_E101_25F,  '2025-08-26 09:15', 'Completed', 'B',  N'Strong lab work.'),
        (@S5,  @Sec4_B101_25F,  '2025-08-26 09:20', 'Completed', 'A-', N'Excellent biology notebook.'),
        (@S6,  @Sec1_CS101_25F, '2025-08-26 09:25', 'Completed', 'B',  N'Passed prerequisite.'),
        (@S7,  @Sec1_CS101_25F, '2025-08-26 09:30', 'Completed', 'A-', N'Excellent final project.'),
        (@S8,  @Sec2_M101_25F,  '2025-08-26 09:35', 'Completed', 'B+', N'Good grasp of integrals.'),
        (@S11, @Sec1_CS101_25F, '2025-08-26 09:40', 'Completed', 'C',  N'Met minimum prerequisite bar.'),
        (@S12, @Sec1_CS101_25F, '2025-08-26 09:45', 'Completed', 'B-', N'Good performance.'),
        (@S13, @Sec1_CS101_25F, '2025-08-26 09:50', 'Completed', 'C+', N'Competent work.'),

        -- Edge Case: Devon Brooks failed CS101 in 2025-FALL (F grade, 0 credit, GPA penalty)
        (@S16, @Sec1_CS101_25F, '2025-08-26 10:00', 'Completed', 'F',  N'Failed to attend final exam; probationary status triggered.'),

        -- Graduated student history
        (@S18, @Sec1_CS101_25F, '2025-08-26 10:05', 'Completed', 'A',  N'Graduation transcript component.'),

        -- ---------------------------------------------------------------------
        -- 2026-SPRING Historical Enrollments (Completed/graded)
        -- ---------------------------------------------------------------------
        (@S1,  @Sec5_CS201_26S,  '2026-01-14 09:00', 'Completed', 'A',  N'Mastered trees and graphs.'),
        (@S2,  @Sec5_CS201_26S,  '2026-01-14 09:05', 'Completed', 'A-', N'Great algorithmic project.'),
        (@S3,  @Sec6_M201_26S,   '2026-01-14 09:10', 'Completed', 'A',  N'Superior calculus mastery.'),
        (@S6,  @Sec5_CS201_26S,  '2026-01-14 09:15', 'Completed', 'B+', N'Passed.'),
        (@S7,  @Sec5_CS201_26S,  '2026-01-14 09:20', 'Completed', 'A',  N'Top marks in data structures.'),
        (@S8,  @Sec6_M201_26S,   '2026-01-14 09:25', 'Completed', 'B',  N'Good progress.'),
        (@S10, @Sec8_BUS101_26S, '2026-01-14 09:30', 'Completed', 'B+', N'Solid case analysis.'),

        -- Edge Case: Student with Incomplete grade resolved or standing
        (@S14, @Sec6_M201_26S,   '2026-01-14 09:35', 'Completed', 'C',  N'Met baseline requirements.'),

        -- Edge Case: Tyler Durden officially withdrew in Spring 2026
        (@S19, @Sec8_BUS101_26S, '2026-01-14 09:40', 'Withdrawn', 'W',  N'Formal withdrawal approved by dean.'),

        -- ---------------------------------------------------------------------
        -- 2026-FALL Active Term Enrollments
        -- ---------------------------------------------------------------------
        -- Section 9: CS301 (Databases) - Active students who completed CS201 prerequisite
        (@S1,  @Sec9_CS301_26F,   '2026-08-25 10:00', 'Enrolled', NULL, N'Active enrollment.'),
        (@S2,  @Sec9_CS301_26F,   '2026-08-25 10:05', 'Enrolled', NULL, N'Active enrollment.'),
        (@S6,  @Sec9_CS301_26F,   '2026-08-25 10:10', 'Enrolled', NULL, N'Active enrollment.'),
        (@S7,  @Sec9_CS301_26F,   '2026-08-25 10:15', 'Enrolled', NULL, N'Active enrollment.'),

        -- Section 10: CS201 (Data Structures) - Active students who completed CS101 prerequisite
        (@S11, @Sec10_CS201_26F,  '2026-08-25 10:20', 'Enrolled', NULL, N'Active enrollment.'),
        (@S12, @Sec10_CS201_26F,  '2026-08-25 10:25', 'Enrolled', NULL, N'Active enrollment.'),
        (@S13, @Sec10_CS201_26F,  '2026-08-25 10:30', 'Enrolled', NULL, N'Active enrollment.'),

        -- Section 11: CS101 (Intro CS) - Freshmen
        (@S20, @Sec11_CS101_26F,  '2026-08-25 11:00', 'Enrolled', NULL, N'Freshman active registration.'),
        (@S21, @Sec11_CS101_26F,  '2026-08-25 11:05', 'Enrolled', NULL, N'Freshman active registration.'),

        -- Edge Case: Retake attempt - Devon Brooks retaking CS101 after failing
        (@S16, @Sec11_CS101_26F,  '2026-08-25 11:10', 'Enrolled', NULL, N'Retaking after probationary fail.'),

        -- Edge Case: Incomplete grade in active enrollment
        (@S15, @Sec13_E101_26F,   '2026-08-25 11:15', 'Enrolled', 'I',  N'Medical incomplete extension granted.'),

        -- Edge Case: Student dropped during add/drop window
        (@S22, @Sec11_CS101_26F,  '2026-08-25 11:20', 'Dropped',  NULL, N'Dropped course during add/drop period.'),

        -- Section 12: MATH301 (Linear Algebra) - Completed MATH201 prerequisite
        (@S3,  @Sec12_M301_26F,   '2026-08-25 11:25', 'Enrolled', NULL, N'Active enrollment.'),
        (@S8,  @Sec12_M301_26F,   '2026-08-25 11:30', 'Enrolled', NULL, N'Active enrollment.'),

        -- ---------------------------------------------------------------------
        -- Section 15: CS401 (Advanced Software Engineering) - FULL SECTION
        -- MaxCapacity = 3. Exactly 3 active students enrolled!
        -- ---------------------------------------------------------------------
        (@S1,  @Sec15_CS401_26F,  '2026-08-25 12:00', 'Enrolled', NULL, N'Full section enrollment 1 of 3.'),
        (@S2,  @Sec15_CS401_26F,  '2026-08-25 12:05', 'Enrolled', NULL, N'Full section enrollment 2 of 3.'),
        (@S7,  @Sec15_CS401_26F,  '2026-08-25 12:10', 'Enrolled', NULL, N'Full section enrollment 3 of 3 (Section is now FULL).');

    PRINT 'Inserted 40 initial enrollment records across past and current terms.';
END;
GO

-- -----------------------------------------------------------------------------
-- 9. Seed Baseline Audit Log
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [audit].[EnrollmentAuditLog])
BEGIN
    INSERT INTO [audit].[EnrollmentAuditLog]
        ([EnrollmentID], [StudentID], [SectionID], [ActionType], [PreviousStatus], [NewStatus], [PreviousGrade], [NewGrade], [ChangedBy], [Details])
    VALUES
        (35, 22, 11, 'DROP', 'Enrolled', 'Dropped', NULL, NULL, SUSER_SNAME(), N'Student dropped CS101-01 during add/drop window.'),
        (12, 16, 1,  'GRADE_ASSIGNED', 'Enrolled', 'Completed', NULL, 'F', SUSER_SNAME(), N'Final failing grade recorded; probation flag set.'),
        (20, 19, 8,  'STATUS_CHANGE',  'Enrolled', 'Withdrawn', NULL, 'W', SUSER_SNAME(), N'Approved dean withdrawal with W notation.'),
        (37, 1,  15, 'ENROLL', NULL, 'Enrolled', NULL, NULL, SUSER_SNAME(), N'Enrolled in capstone CS401-01.'),
        (38, 2,  15, 'ENROLL', NULL, 'Enrolled', NULL, NULL, SUSER_SNAME(), N'Enrolled in capstone CS401-01.'),
        (39, 7,  15, 'ENROLL', NULL, 'Enrolled', NULL, NULL, SUSER_SNAME(), N'Enrolled in capstone CS401-01; reached maximum capacity.');

    PRINT 'Baseline audit entries logged.';
END;
GO

COMMIT TRANSACTION;
PRINT '================================================================================';
PRINT '02_seed.sql executed successfully. All seed data committed.';
PRINT '================================================================================';
GO
