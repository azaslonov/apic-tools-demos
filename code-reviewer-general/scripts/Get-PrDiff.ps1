<#
.SYNOPSIS
    Parse ADO PR URL and fetch PR details and diff.

.DESCRIPTION
    Parses an Azure DevOps pull request URL and retrieves PR metadata.
    Uses az CLI to get source/target branches, then fetches diff via git.
    Falls back to instructions for MCP tools if CLI methods fail.

.PARAMETER PrUrl
    The Azure DevOps pull request URL.
    Format: https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}

.PARAMETER DiffOnly
    If specified, only outputs the diff without stats or metadata.

.PARAMETER StatsOnly
    If specified, only outputs the diff stats without full diff.

.EXAMPLE
    .\Get-PrDiff.ps1 -PrUrl "https://dev.azure.com/msazure/One/_git/AAPT-APIManagement/pullrequest/123"

.EXAMPLE
    .\Get-PrDiff.ps1 -PrUrl "https://dev.azure.com/msazure/One/_git/AAPT-APIManagement/pullrequest/123" -StatsOnly
#>

param(
    [Parameter(Mandatory)]
    [string]$PrUrl,

    [switch]$DiffOnly,

    [switch]$StatsOnly
)

$ErrorActionPreference = "Stop"

# Parse the ADO PR URL
# Expected format: https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}
# Or: https://{org}.visualstudio.com/{project}/_git/{repo}/pullrequest/{id}

$pattern = 'https://(?:dev\.azure\.com/([^/]+)|([^.]+)\.visualstudio\.com)/([^/]+)/_git/([^/]+)/pullrequest/(\d+)'

if ($PrUrl -match $pattern) {
    $org = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
    $project = $Matches[3]
    $repo = $Matches[4]
    $prId = $Matches[5]
} else {
    Write-Error "Invalid ADO PR URL format. Expected: https://dev.azure.com/{org}/{project}/_git/{repo}/pullrequest/{id}"
    exit 1
}

if (-not $DiffOnly) {
    Write-Host "## PR Details" -ForegroundColor Cyan
    Write-Host "Organization: $org"
    Write-Host "Project: $project"
    Write-Host "Repository: $repo"
    Write-Host "PR ID: $prId"
    Write-Host ""
}

# Output parsed values as JSON for programmatic use
$result = @{
    organization = $org
    project = $project
    repository = $repo
    pullRequestId = [int]$prId
    url = $PrUrl
}

if (-not $DiffOnly) {
    Write-Host "### Parsed URL Components"
    $result | ConvertTo-Json
    Write-Host ""
}

$sourceBranch = $null
$targetBranch = $null
$prTitle = $null
$prAuthor = $null

# Try to get PR details via az CLI to get source/target branches
try {
    $azCheck = az --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        if (-not $DiffOnly) {
            Write-Host "### Fetching PR metadata via az CLI..." -ForegroundColor Cyan
        }
        
        # az repos pr show uses --org only (auto-detects project from repo or uses defaults)
        $prJson = az repos pr show --id $prId --org "https://dev.azure.com/$org" --detect false 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $prData = $prJson | ConvertFrom-Json
            
            # Extract branch names (remove refs/heads/ prefix)
            $sourceBranch = $prData.sourceRefName -replace '^refs/heads/', ''
            $targetBranch = $prData.targetRefName -replace '^refs/heads/', ''
            $prTitle = $prData.title
            $prAuthor = $prData.createdBy.displayName
            
            if (-not $DiffOnly) {
                Write-Host "Title: $prTitle"
                Write-Host "Author: $prAuthor"
                Write-Host "Source Branch: $sourceBranch"
                Write-Host "Target Branch: $targetBranch"
                Write-Host "Status: $($prData.status)"
                Write-Host ""
            }
            
            # Update result with branch info
            $result.sourceBranch = $sourceBranch
            $result.targetBranch = $targetBranch
            $result.title = $prTitle
            $result.author = $prAuthor
        } else {
            if (-not $DiffOnly) {
                Write-Host "az CLI PR fetch failed: $prJson" -ForegroundColor Yellow
            }
        }
    }
} catch {
    if (-not $DiffOnly) {
        Write-Host "az CLI not available: $_" -ForegroundColor Yellow
    }
}

# Try to fetch PR diff via git if we have branch info
$diffSuccess = $false
try {
    $gitRoot = git rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -eq 0) {
        if ($sourceBranch -and $targetBranch) {
            if (-not $DiffOnly) {
                Write-Host "### Fetching branches and generating diff..." -ForegroundColor Cyan
            }

            # Fetch both branches
            git fetch origin "$sourceBranch" 2>$null
            git fetch origin "$targetBranch" 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                $diffSuccess = $true
                
                if (-not $DiffOnly) {
                    Write-Host "### Diff Summary" -ForegroundColor Cyan
                    $stats = git diff --stat "origin/$targetBranch...origin/$sourceBranch" 2>&1
                    Write-Host $stats
                    Write-Host ""
                }
                
                if (-not $StatsOnly) {
                    if (-not $DiffOnly) {
                        Write-Host "### Diff" -ForegroundColor Cyan
                    }
                    $diff = git diff "origin/$targetBranch...origin/$sourceBranch" 2>&1
                    Write-Host $diff
                }
            }
        } else {
            # Fallback: try common default branches if we don't have branch info
            if (-not $DiffOnly) {
                Write-Host "Branch info not available. Trying to infer from remote..." -ForegroundColor Yellow
            }
            
            # Check if there's a branch that looks like it matches the PR
            $remoteBranches = git branch -r 2>&1
            
            # Common target branches to try
            $targetCandidates = @("origin/main", "origin/master", "origin/dev", "origin/develop")
            
            foreach ($target in $targetCandidates) {
                $exists = git rev-parse --verify $target 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $targetBranch = $target -replace '^origin/', ''
                    break
                }
            }
            
            if ($targetBranch) {
                if (-not $DiffOnly) {
                    Write-Host "Using inferred target branch: $targetBranch" -ForegroundColor Yellow
                    Write-Host "Note: Source branch unknown. Use az CLI login or provide branch info manually." -ForegroundColor Yellow
                }
            }
        }
    }
} catch {
    if (-not $DiffOnly) {
        Write-Host "git error: $_" -ForegroundColor Yellow
    }
}

# Show fallback instructions if diff wasn't successful
if (-not $diffSuccess -and -not $DiffOnly) {
    Write-Host ""
    Write-Host "### Manual Instructions" -ForegroundColor Yellow
    Write-Host @"
If the automatic diff failed, try these options:

1. Login to az CLI and retry:
   az login
   az devops configure --defaults organization=https://dev.azure.com/$org project="$project"

2. Fetch branches manually (if you know the branch names):
   git fetch origin <source-branch>
   git fetch origin <target-branch>
   git diff origin/<target-branch>...origin/<source-branch>

3. Use ADO MCP tools to get PR details:
   ado-repo_get_repo_by_name_or_id: project="$project", repositoryNameOrId="$repo"
   ado-repo_get_pull_request_by_id: repositoryId=<GUID>, pullRequestId=$prId
"@
}

# Return result object for programmatic use
if (-not $DiffOnly -and -not $StatsOnly) {
    Write-Host ""
    Write-Host "### Result Object" -ForegroundColor Cyan
    $result | ConvertTo-Json
}

