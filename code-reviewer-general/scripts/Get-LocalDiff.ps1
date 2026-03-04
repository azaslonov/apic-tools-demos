<#
.SYNOPSIS
    Get local git diff for code review.

.DESCRIPTION
    Retrieves git diff comparing local changes against a base branch.
    Supports uncommitted changes, staged changes, or branch comparison.
    Auto-detects the default branch (main/master/dev) if not specified.

.PARAMETER BaseBranch
    The base branch to compare against. If not specified, auto-detects 
    the default branch by checking main, master, then dev.

.PARAMETER UncommittedOnly
    If specified, only show uncommitted changes (git diff).

.PARAMETER StagedOnly
    If specified, only show staged changes (git diff --cached).

.PARAMETER StatsOnly
    If specified, only show diff stats without full diff content.

.PARAMETER FilePath
    Optional path to limit diff to specific file or directory.

.EXAMPLE
    .\Get-LocalDiff.ps1
    # Auto-detects base branch and compares current branch
    
.EXAMPLE
    .\Get-LocalDiff.ps1 -BaseBranch "main"
    
.EXAMPLE
    .\Get-LocalDiff.ps1 -UncommittedOnly
    
.EXAMPLE
    .\Get-LocalDiff.ps1 -StagedOnly -FilePath "src/Data"

.EXAMPLE
    .\Get-LocalDiff.ps1 -StatsOnly
#>

param(
    [string]$BaseBranch,
    [switch]$UncommittedOnly,
    [switch]$StagedOnly,
    [switch]$StatsOnly,
    [string]$FilePath
)

$ErrorActionPreference = "Stop"

# Verify we're in a git repository
try {
    $gitRoot = git rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not in a git repository"
        exit 1
    }
} catch {
    Write-Error "Git is not available: $_"
    exit 1
}

# Auto-detect base branch if not specified
if (-not $BaseBranch -and -not $UncommittedOnly -and -not $StagedOnly) {
    $candidates = @("main", "master", "dev", "develop")
    foreach ($candidate in $candidates) {
        $exists = git rev-parse --verify "origin/$candidate" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $BaseBranch = "origin/$candidate"
            Write-Host "Auto-detected base branch: $BaseBranch" -ForegroundColor DarkGray
            break
        }
    }
    
    if (-not $BaseBranch) {
        Write-Error "Could not auto-detect base branch. Please specify -BaseBranch parameter."
        exit 1
    }
}

# Build the git diff command
if ($UncommittedOnly) {
    $diffArgs = @("diff")
    $description = "Uncommitted changes"
} elseif ($StagedOnly) {
    $diffArgs = @("diff", "--cached")
    $description = "Staged changes"
} else {
    # Compare current branch to base branch
    $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
    $diffArgs = @("diff", "$BaseBranch...$currentBranch")
    $description = "Changes from $BaseBranch to $currentBranch"
}

# Add file path filter if specified
if ($FilePath) {
    $diffArgs += @("--", $FilePath)
    $description += " (filtered: $FilePath)"
}

# Get the diff
Write-Host "## Local Diff: $description" -ForegroundColor Cyan
Write-Host ""

$diff = git @diffArgs 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get diff: $diff"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($diff)) {
    Write-Host "No changes found." -ForegroundColor Yellow
} else {
    # Get summary stats
    $statsArgs = @("diff", "--stat") + @($diffArgs | Select-Object -Skip 1)
    $stats = git @statsArgs 2>&1
    
    Write-Host "### Summary"
    Write-Host $stats
    Write-Host ""
    
    if (-not $StatsOnly) {
        Write-Host "### Diff"
        Write-Host $diff
    }
}
