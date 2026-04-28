<#
.SYNOPSIS
    Format code review findings into a markdown summary.

.DESCRIPTION
    Takes an array of findings and generates a formatted markdown review summary.
    Groups findings by priority and includes counts and suggested actions.

.PARAMETER FindingsJson
    JSON string containing array of findings. Each finding should have:
    - priority: "critical", "important", or "suggestion"
    - category: e.g., "Security", "Testing", "Performance"
    - title: Brief title
    - file: File path
    - line: Line number (optional)
    - description: Detailed description
    - suggestedFix: Code suggestion (optional)
    - reference: Link to documentation (optional)

.PARAMETER RiskLevel
    Overall risk level: "Low", "Medium", or "High"

.PARAMETER SuggestedTags
    Comma-separated PR tags to suggest.

.PARAMETER FilesChanged
    Number of files changed.

.PARAMETER LinesAdded
    Number of lines added.

.PARAMETER LinesRemoved
    Number of lines removed.

.EXAMPLE
    $findings = '[{"priority":"important","category":"Testing","title":"Missing tests","file":"TokenValidation.cs","line":45,"description":"No tests for expired token scenario"}]'
    .\Format-ReviewSummary.ps1 -FindingsJson $findings -RiskLevel "Medium" -SuggestedTags "#Feature,#RiskMedium"
#>

param(
    [Parameter(Mandatory)]
    [string]$FindingsJson,
    
    [ValidateSet("Low", "Medium", "High")]
    [string]$RiskLevel = "Medium",
    
    [string]$SuggestedTags = "",
    
    [int]$FilesChanged = 0,
    [int]$LinesAdded = 0,
    [int]$LinesRemoved = 0
)

$ErrorActionPreference = "Stop"

# Parse findings
try {
    $findings = $FindingsJson | ConvertFrom-Json
} catch {
    Write-Error "Invalid JSON for findings: $_"
    exit 1
}

# Group by priority
$critical = @($findings | Where-Object { $_.priority -eq "critical" })
$important = @($findings | Where-Object { $_.priority -eq "important" })
$suggestions = @($findings | Where-Object { $_.priority -eq "suggestion" })

# Generate summary
$summary = @"
## Code Review Summary

### Overview
- **Files Changed**: $FilesChanged
- **Lines Added**: $LinesAdded / **Removed**: $LinesRemoved
- **Risk Level**: $RiskLevel
- **Suggested PR Tags**: $SuggestedTags

### Key Findings

| Priority | Count | Action Required |
|----------|-------|-----------------|
| CRITICAL | $($critical.Count) | Must fix before merge |
| IMPORTANT | $($important.Count) | Should address |
| SUGGESTION | $($suggestions.Count) | Nice to have |

"@

# Add critical findings
if ($critical.Count -gt 0) {
    $summary += @"
### CRITICAL Issues

"@
    foreach ($finding in $critical) {
        $location = if ($finding.line) { ", Line: $($finding.line)" } else { "" }
        $summary += @"
#### **[CRITICAL] $($finding.category): $($finding.title)**

File: ``$($finding.file)``$location

$($finding.description)

"@
        if ($finding.suggestedFix) {
            $summary += @"
**Suggested fix:**
``````
$($finding.suggestedFix)
``````

"@
        }
        if ($finding.reference) {
            $summary += "**Reference:** $($finding.reference)`n`n"
        }
    }
}

# Add important findings
if ($important.Count -gt 0) {
    $summary += @"
### IMPORTANT Issues

"@
    foreach ($finding in $important) {
        $location = if ($finding.line) { ", Line: $($finding.line)" } else { "" }
        $summary += @"
#### **[IMPORTANT] $($finding.category): $($finding.title)**

File: ``$($finding.file)``$location

$($finding.description)

"@
        if ($finding.suggestedFix) {
            $summary += @"
**Suggested fix:**
``````
$($finding.suggestedFix)
``````

"@
        }
    }
}

# Add suggestions
if ($suggestions.Count -gt 0) {
    $summary += @"
### Suggestions

"@
    foreach ($finding in $suggestions) {
        $location = if ($finding.line) { ", Line: $($finding.line)" } else { "" }
        $summary += @"
#### **[SUGGESTION] $($finding.category): $($finding.title)**

File: ``$($finding.file)``$location

$($finding.description)

"@
    }
}

# Add confirmation prompt
$summary += @"
---
**Ready to post these as PR comments?** [Yes/No/Select/Modify]
"@

Write-Output $summary
