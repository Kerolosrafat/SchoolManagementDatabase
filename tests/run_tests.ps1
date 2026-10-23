<#
================================================================================
SCRIPT: tests/run_tests.ps1
PROJECT: University Course and Student Management Database (SchoolDB)
AUTHOR: Kerolosrafat
TARGET: Microsoft SQL Server 2022+ (Database: SchoolDB_Test)
DESCRIPTION:
    Automated test runner executing the complete SQL Server assertion suite
    against the dedicated test database [SchoolDB_Test].

BEHAVIOR & SAFETY:
    - Strictly targets [SchoolDB_Test] using Windows Integrated Authentication.
    - Resolves absolute script paths dynamically regardless of working directory.
    - Captures sqlcmd return codes and raises non-zero exit codes on failure.
    - Formats clear, colored console summaries of assertion outcomes.
================================================================================
#>

[CmdletBinding()]
param (
    [string]$ServerInstance = "localhost",
    [string]$Database = "SchoolDB_Test"
)

# Enforce strict error handling
$ErrorActionPreference = "Stop"

# Strict safety verification - tests must ONLY run against SchoolDB_Test
if ($Database -ne "SchoolDB_Test") {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host " FATAL SAFETY ERROR: Test runner targets [SchoolDB_Test] only." -ForegroundColor Red
    Write-Host " Provided target database: [$Database]" -ForegroundColor Red
    Write-Host " Refusing to execute test suite against non-test or production databases." -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Red
    exit 1
}

# Resolve robust paths regardless of current working directory
$ScriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = Split-Path -Parent $ScriptDirectory
$SqlDirectory = Join-Path $ProjectRoot "sql"
$SqlTestFile = Join-Path $ScriptDirectory "run_tests.sql"

if (-not (Test-Path $SqlTestFile)) {
    Write-Host "[ERROR] Test script not found: $SqlTestFile" -ForegroundColor Red
    exit 1
}

# Verify sql/ folder integrity
$ExpectedScripts = @(
    "01_schema.sql",
    "02_seed.sql",
    "03_views.sql",
    "04_queries.sql",
    "05_procedures.sql",
    "06_functions.sql",
    "07_indexes.sql",
    "08_bonus_optional.sql"
)

foreach ($script in $ExpectedScripts) {
    $scriptPath = Join-Path $SqlDirectory $script
    if (-not (Test-Path $scriptPath)) {
        Write-Host "[WARNING] Expected SQL script not found at path: $scriptPath" -ForegroundColor Yellow
    }
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " EXECUTING AUTOMATED SQL SERVER TEST SUITE" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " Project Root    : $ProjectRoot" -ForegroundColor Yellow
Write-Host " SQL Directory   : $SqlDirectory" -ForegroundColor Yellow
Write-Host " Test File       : $SqlTestFile" -ForegroundColor Yellow
Write-Host " Target Database : $Database" -ForegroundColor Yellow
Write-Host " Target Server   : $ServerInstance" -ForegroundColor Yellow
Write-Host " Auth Mode       : Windows Integrated Authentication (-E)" -ForegroundColor Yellow
Write-Host " Started At      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray

# Execute sqlcmd with -b (on error exit with non-zero status code)
$startTime = Get-Date

try {
    # Capture both stdout and stderr
    $output = & sqlcmd -S $ServerInstance -d $Database -E -b -i $SqlTestFile 2>&1
    $exitCode = $LASTEXITCODE
}
catch {
    $output = $_.Exception.Message
    $exitCode = 1
}

$elapsedTime = (Get-Date) - $startTime

# Display SQL execution output
Write-Host ""
$output | ForEach-Object {
    if ($_ -match "FAIL" -or $_ -match "Msg " -or $_ -match "ERROR:") {
        Write-Host $_ -ForegroundColor Red
    }
    elseif ($_ -match "PASS" -or $_ -match "SUCCESS") {
        Write-Host $_ -ForegroundColor Green
    }
    elseif ($_ -match "===" -or $_ -match "---") {
        Write-Host $_ -ForegroundColor Cyan
    }
    else {
        Write-Host $_
    }
}

Write-Host ""
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
Write-Host " EXECUTION SUMMARY" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
Write-Host " Elapsed Time : $($elapsedTime.TotalSeconds.ToString('F2')) seconds"

if ($exitCode -eq 0) {
    Write-Host " Overall Result: PASSED" -ForegroundColor Green
    Write-Host " All assertions passed without failure. Test database remains clean." -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Cyan
    exit 0
}
else {
    Write-Host " Overall Result: FAILED (Exit Code: $exitCode)" -ForegroundColor Red
    Write-Host " One or more assertions failed or a SQL batch error occurred." -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Cyan
    exit $exitCode
}
