---
name: code-reviewer-general
description: |
  Azure API Management code review assistant. Provides:
  - A structured review of changes (security, correctness, tests, performance, maintainability)
  - Review comments formatted by severity (Critical/Important/Suggestion)
  - Focus on APIM-specific patterns: policy engine, gateway, EF data access, ARM resource provider
  
  Tailored for the AAPT-APIManagement repository with specific attention to:
  - Thread-safety in concurrent collections and caches
  - Policy expression parsing security
  - Entity Framework transaction/retry patterns
  - Certificate authentication flows
---

# Code Reviewer (Azure API Management)

Provide consistent, high-signal code reviews for the Azure API Management codebase.

## How to Use

### Review a PR (Azure DevOps)
1. Run the diff script to get PR details and changes:
   ```powershell
   .\.github\skills\code-reviewer-general\scripts\Get-PrDiff.ps1 -PrUrl "<ADO PR URL>" -StatsOnly
   ```
2. Review the diff against the guidelines in `references/`
3. Format findings using the review summary script (see below)
4. Post comments via ADO MCP tools (`ado-repo_create_pull_request_thread`)

### Review local uncommitted changes
1. Run the local diff script:
   ```powershell
   .\.github\skills\code-reviewer-general\scripts\Get-LocalDiff.ps1 -UncommittedOnly
   ```
2. Or for staged changes only:
   ```powershell
   .\.github\skills\code-reviewer-general\scripts\Get-LocalDiff.ps1 -StagedOnly
   ```

### Review a branch vs main
1. Run the local diff script (auto-detects base branch):
   ```powershell
   .\.github\skills\code-reviewer-general\scripts\Get-LocalDiff.ps1 -StatsOnly
   ```
2. Or specify base branch explicitly:
   ```powershell
   .\.github\skills\code-reviewer-general\scripts\Get-LocalDiff.ps1 -BaseBranch "origin/main"
   ```

## Scripts

### Get-PrDiff.ps1
Fetches PR metadata and diff from Azure DevOps.

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `-PrUrl` | (Required) Azure DevOps PR URL |
| `-StatsOnly` | Show only diff stats, not full diff |
| `-DiffOnly` | Output only the diff content (no metadata) |

**Example:**
```powershell
.\Get-PrDiff.ps1 -PrUrl "https://dev.azure.com/msazure/One/_git/AAPT-APIManagement/pullrequest/123" -StatsOnly
```

**How it works:**
1. Parses the ADO PR URL to extract org, project, repo, and PR ID
2. Uses `az repos pr show` to get source/target branch names
3. Fetches branches via git and generates diff
4. Falls back to manual instructions if az CLI is not authenticated

### Get-LocalDiff.ps1
Gets git diff for local changes or branch comparisons.

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `-BaseBranch` | Base branch to compare against (auto-detects if not specified) |
| `-UncommittedOnly` | Show only uncommitted changes |
| `-StagedOnly` | Show only staged changes |
| `-StatsOnly` | Show only diff stats, not full diff |
| `-FilePath` | Filter diff to specific file or directory |

**Examples:**
```powershell
# Auto-detect base branch and compare current branch
.\Get-LocalDiff.ps1 -StatsOnly

# Show uncommitted changes
.\Get-LocalDiff.ps1 -UncommittedOnly

# Filter to specific component
.\Get-LocalDiff.ps1 -StatsOnly -FilePath "Proxy/Gateway.Policies"
```

### Format-ReviewSummary.ps1
Formats code review findings into a structured markdown summary.

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `-FindingsJson` | (Required) JSON array of findings |
| `-RiskLevel` | Overall risk: "Low", "Medium", or "High" (default: Medium) |
| `-SuggestedTags` | Comma-separated PR tags to suggest |
| `-FilesChanged` | Number of files changed |
| `-LinesAdded` | Number of lines added |
| `-LinesRemoved` | Number of lines removed |

**Finding JSON format:**
```json
{
  "priority": "critical|important|suggestion",
  "category": "Security|Testing|Performance|Maintainability|...",
  "title": "Brief title",
  "file": "path/to/file.cs",
  "line": 42,
  "description": "Detailed description",
  "suggestedFix": "Optional code suggestion",
  "reference": "Optional link to docs"
}
```

**Example:**
```powershell
$findings = '[{"priority":"important","category":"Testing","title":"Missing tests","file":"MyClass.cs","line":45,"description":"No tests for error scenario"}]'
.\Format-ReviewSummary.ps1 -FindingsJson $findings -RiskLevel "Medium" -FilesChanged 5 -LinesAdded 100 -LinesRemoved 20
```

## Recommended Workflow

1. **Get the diff**: Use `Get-PrDiff.ps1` or `Get-LocalDiff.ps1`
2. **Identify affected components**: Check which folders are modified (Proxy/, Management/, ResourceProvider/)
3. **Read applicable reference docs**:
   - **Always read**: `references/review-guidelines.md` for general APIM patterns
   - **For Gateway code** (`Proxy/**`): **Read `references/gateway-patterns.md`** - contains compression, pipeline, thread-safety patterns
4. **Review against guidelines**: Apply the specific checks from the reference documents
5. **Collect findings**: Build a JSON array of findings as you review
6. **Format summary**: Use `Format-ReviewSummary.ps1` to generate structured output
7. **Post comments**: Use ADO MCP tools to post inline and summary comments

## Output Format

1. **Summary** (2-5 bullets)
2. **Risk Level**: Low / Medium / High
3. **Findings** grouped by severity:
   - 🔴 Critical (block merge)
   - 🟡 Important (discuss/should fix)
   - 🟢 Suggestion (nice-to-have)
4. **Tests & Validation**: what to run, what seems missing

## Rubric

See `references/review-guidelines.md` for APIM-specific review guidelines.

### Reference Documents (MUST READ)

Before reviewing, **read the applicable reference documents** based on which folders are modified:

| If diff touches... | Then read... | Key topics |
|--------------------|--------------|------------|
| `Proxy/**` | `references/gateway-patterns.md` | Thread-safety, object pooling, compression, pipeline handlers, ValueTask patterns |
| `Proxy/Gateway.Pipeline.IO/**` | `references/gateway-patterns.md` | Buffer management, stream wrappers, **compression handling**, latency tracking |
| `Proxy/Gateway.Policies/**` | `references/gateway-patterns.md` | Policy implementation, XmlSerializer pools, expression security |
| `Test/Bvt/Gateway/**` | `references/gateway-patterns.md` | BVT test patterns, mocking conventions |
| `Management/**` | `references/review-guidelines.md` | EF patterns, API controllers, Autofac DI |
| `ResourceProvider/**` | `references/review-guidelines.md` | ARM lifecycle, Service Fabric patterns |

## Review Hotspots

| Area | What to Watch |
|------|---------------|
| `Proxy/Gateway.Policies/` | Thread-safety of XmlSerializer pools, expression injection vectors. See `references/gateway-patterns.md` |
| `Proxy/Gateway.Policies.Expressions/` | Security analyzers (AllowedTypesAnalyzer, CodeInjectionAnalyzer), type allow-lists |
| `Proxy/Gateway.Pipeline/` | Pipeline stage transitions, error handler composition, ValueTask patterns |
| `Proxy/Gateway.Pipeline.IO/` | Buffer management, stream wrappers, latency tracking placement |
| `Proxy/Gateway.Http.Client.DotNetty/` | Event loop patterns, channel pools, backpressure, Channel<T> usage |
| `Proxy/Gateway.Redis/` | Connection health, timeout handling, metrics tracking |
| `Proxy/Gateway.Policies.RateLimit/` | Distributed counter accuracy, SemaphoreSlim cleanup |
| `Proxy/Gateway.Policies.ConcurrencyLimit/` | Semaphore lifecycle, stale cleanup, neighbor discovery |
| `Management/Management.Api/Controllers/` | CancellationToken propagation, auth filter composition |
| `Management/Management.Data.Ef/` | Transaction/retry semantics, disposal in decorator chains |
| `ResourceProvider/` | ARM lifecycle, Service Fabric patterns |
| Certificate auth filters | Multiple variants - verify correct composition |
| `Test/Bvt/Gateway/` | BVT reliability, test coverage for new policy features |
| `appsettings.json` (Gateway) | Buffer sizes, connection pools, memory-impacting settings |

## Quality Gates

- **Code Coverage**: 50% diff coverage target (per `azurepipelines-coverage.yml`)
- **CodeQL**: Must pass static analysis (`.CodeQL.yml`)
- **SDL Compliance**: FxCop rules from `Sdl7.0_minimum.ruleset`
- **Approver Policy**: Minimum 1 approver on main/prodrelease/hotfix branches
