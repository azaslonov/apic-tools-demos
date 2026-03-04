---
name: create-pull-request
description: Guide for creating pull requests that meet Azure API Management repository standards. Enforces branch-specific PR templates, ensures latest changes are merged, covers title format, pre-submit checklists, and Azure DevOps workflow.
---

# Create Pull Request

This skill guides the creation of pull requests (PRs) that meet repository standards and enforces branch-specific templates.

## Workflow Steps

### 1. Identify Target Branch and Work Item

**Before starting**, confirm the target branch:
- **main** - Standard development (most common)
- **release-gw** / **release-rp** / **release-mgmt** / **release-shgw** - Component releases
- **hotfix** / **hotfix-gw** / **hotfix-rp** / **hotfix-mgmt** / **hotfix-shgw** - Emergency fixes
- **prodrelease** - Production release

**Ask the user to confirm the target branch if not explicitly stated.**

**Work Item (Optional but Recommended):**
- Ask: "Is there a work item associated with this change?"
- If yes, get the work item ID (e.g., 12345)
- This helps with:
  - Building clear PR title and description
  - Automatic linking for tracking
  - Context for reviewers

### 2. Check for Existing PR

Before creating a new PR, check if one already exists for this branch:

```bash
az repos pr list --source-branch <your-branch> --status active
```

**If an active PR exists**: Update it instead of creating a new one (see "Updating Existing PR" section).

**If PR was abandoned**: 
- **DO NOT automatically recreate it**
- Inform the user that a PR was abandoned
- **Ask**: "The previous PR was abandoned. Would you like me to create a new one?"
- Only proceed if user explicitly confirms

### 3. Sync with Target Branch

**CRITICAL:** Always ensure your branch has latest changes from the target branch.

```bash
# Fetch latest from remote
git fetch origin

# Check current branch
git branch --show-current

# Merge latest changes from target branch
git merge origin/<target-branch>

# If conflicts, resolve them before proceeding
```

**If user wants to target a branch other than `main`, ASK FIRST:**
- "You're creating a PR against `<target-branch>`. Have you confirmed this is correct?"
- "Have you merged the latest changes from `origin/<target-branch>` into your branch?"

### 4. Review Changes Locally

**Run code review BEFORE opening the PR** to catch issues early.

Ask: **"Review my changes against `origin/<target-branch>`"**

This will invoke the **code-reviewer-general** skill to analyze your diff.

**Address all 🔴 CRITICAL issues before proceeding.**

### 5. Commit Changes

**DO NOT auto-commit changes unless explicitly permitted by the user.**

Show the user what changes will be committed:
```bash
git status
git diff --staged  # if changes are staged
```

**Ask for permission**: "Ready to commit and push these changes?"

Only proceed with commit/push after explicit user approval.

### 6. Select Correct PR Template

**Templates are located in:** `.azuredevops/pull_request_template/branches/`

| Target Branch Pattern | Template File | Key Requirements |
|----------------------|---------------|------------------|
| `main` | `main.md` | Problem, Solution, Design link, Validation, Feature flag |
| `release-gw` | `release-gw.md` | Same as main + Risk assessment |
| `release-rp` | `release-rp.md` | Same as main + Risk assessment |
| `release-mgmt` | `release-mgmt.md` | Same as main + Risk assessment |
| `release-shgw` | `release-shgw.md` | Same as main + Risk assessment |
| `release` | `release.md` | Same as main + Risk assessment |
| `hotfix` | `hotfix.md` | Security, Impact, Urgency, Rollback, Tests |
| `hotfix-gw` | `hotfix-gw.md` | Same as hotfix |
| `hotfix-rp` | `hotfix-rp.md` | Same as hotfix |
| `hotfix-mgmt` | `hotfix-mgmt.md` | Same as hotfix |
| `hotfix-shgw` | `hotfix-shgw.md` | Same as hotfix |
| `hotfixes` | `hotfixes.md` | Same as hotfix |
| `prodrelease` | `prodrelease.md` | Same as main + Risk assessment |

### 7. Fill PR Template

**Read the template file from `.azuredevops/pull_request_template/branches/<target>.md`** and use it as the PR description.

**Use Work Item Information (if available):**
- **Problem**: Reference the work item description/title
- **Solution**: Explain how the changes address the work item
- **Validation**: Include acceptance criteria from work item

**IMPORTANT - Keep Description Concise:**
- Be brief and to-the-point in all sections
- Avoid lengthy explanations - focus on key information
- Use bullet points instead of paragraphs
- Azure DevOps has character limits for PR descriptions
- Link to external docs instead of copying content

### 8. Determine PR Tags

**REQUIRED: Ask the user to classify the change in ONE bundled prompt:**

"Please classify this PR:
1. Component tag (required - choose ONE): MSRC, Security, Compliance, Feature, Fix, Test, LiveSite, Chore, Performance, Dependencies, Deployment, or CI
2. Change type: Internal or CustomerFacing?
3. [If CustomerFacing] Which SKUs apply? (AllSKU, SKUv1, SKUv2, Consumption, CNAG, Self-Hosted, Workspace, AOAIHub)"

**Tag Application Rules:**
- **Always apply**: Component tag + Change type tag
- **SKU tags**: Apply if CustomerFacing

**IMPORTANT - Keep Description Concise:**
- Be brief and to-the-point in all sections
- Avoid lengthy explanations - focus on key information
- Use bullet points instead of paragraphs
- Azure DevOps has character limits for PR descriptions
- Link to external docs instead of copying content

## PR Title Format

`<type>(<scope>): <description>`

### Types
- `feat` - New feature
- `fix` - Bug fix
- `chore` - Maintenance, build changes
- `refactor` - Code restructuring without behavior change
- `test` - Adding or updating tests
- `docs` - Documentation only
- `perf` - Performance improvements
- `ci` - CI/CD pipeline changes
- `deps` - Dependency updates
- `security` - Security fixes/improvements
- `livesite` - Production incident response

### Scopes (Components)
Use lowercase for PR titles:
- `gateway` - API Gateway
- `rp` - Resource Provider
- `rcm` - Resource Capacity Manager
- `portal` - Developer Portal
- `shgw` - Self-Hosted Gateway
- `aoai-hub` - Azure OpenAI Hub
- `bootstrapper` - Bootstrapper
- `smapi` - Service Management API
- `deployment` - Deployment/ExpressV2
- `kudu` - Kudu/SCM
- `copilot` - GitHub Copilot CLI skills/agents
- `other` - Other components

### Examples
- `feat(gateway): Add WebSocket policy support`
- `fix(rp): Resolve orchestration deadlock`
- `deps(gateway): Update Microsoft.Identity.Client to 4.82.0`
- `security(portal): Fix XSS vulnerability in API console`
- `livesite(shgw): Patch memory leak in connection pool`
- `chore(deployment): Update ExpressV2 rollout configuration`
- `feat(copilot): Add create-pull-request skill`

## PR Template Usage

**The PR description MUST follow the template for the target branch.**

**DO NOT copy/paste templates into the skill.** Instead:
1. **Read the template** from `.azuredevops/pull_request_template/branches/<target>.md`
2. **Use it verbatim** as the PR description
3. **Fill in all required sections**
4. **Keep it concise** - brief explanations, bullet points, avoid long paragraphs

Common template sections:
- **Problem/Solution** - Brief, clear description (2-3 sentences max)
- **Design link** - URL only or "N/A"
- **Validation** - Bullet points of key tests
- **Checklist** - Check applicable boxes
- **Risk** - Select one: High/Medium/Small
- **Hotfix-specific** - Brief answers only

## Branch Naming

`<username>/<component>/<short-description>`

Examples: `alice/gateway/websocket-support`, `bob/rp/fix-deadlock`

## Pre-Submit Checklist

### Code Quality
- [ ] Builds without warnings
- [ ] Tests pass locally
- [ ] No unused code (imports, variables, methods)
- [ ] No `TODO`/`FIXME` (or tracked in work items)

### Standards
- [ ] `.editorconfig` formatting
- [ ] Async methods have `Async` suffix
- [ ] No `.Result`, `.Wait()` blocking calls
- [ ] Structured logging with event IDs
- [ ] Exception handling patterns followed

### Component-Specific

**ResourceProvider:**
- [ ] Orchestrations use `context.CurrentUtcDateTime`, `context.NewGuid()`
- [ ] Activities are idempotent
- [ ] New features use `BETAFeature` enum flags
- [ ] ARM compliance verified

**ResourceCapacityManager:**
- [ ] Activity inputs implement `IActivityInput`
- [ ] Logging uses `ToEventId()` and scopes
- [ ] Settings in both `appsettings.json` AND Bicep
- [ ] Log table mappings in `DependencyInjectionExtensions.cs`

**Gateway:**
- [ ] Policy changes tested
- [ ] Performance assessed
- [ ] SKU compatibility verified

### Security
- [ ] No hardcoded credentials
- [ ] Input validation for endpoints
- [ ] SQL injection risks mitigated

## Creating the PR

**IMPORTANT: Only create PR when explicitly instructed by the user.**

**Pre-flight checks:**
1. ✅ No existing active PR for this branch (checked in Step 2)
2. ✅ Branch synced with latest target branch
3. ✅ Correct template identified for target branch
4. ✅ **Code reviewed locally** (Step 4)
5. ✅ **Changes committed and pushed** (Step 5 - with user permission)
6. ✅ Template fully filled out (concisely)
7. ✅ All checklists completed
8. ✅ **PR tags determined** (Step 8)
9. ✅ **Work item ID** (if applicable - from Step 1)
10. ✅ **User confirmed PR creation** (especially if previous PR was abandoned)

### Step 1: Create the PR

**Prepare description** (use temp file for multiline support):
```powershell
$description = @'
<filled-template-content>
'@
$description | Out-File -FilePath "pr_desc.txt" -Encoding utf8 -NoNewline

# Create PR with work item linking
$workItemId = <work-item-id>  # Optional, omit --work-items if not available

az repos pr create \
  --title "<type>(<scope>): <description>" \
  --description "@pr_desc.txt" \
  --source-branch <your-branch> \
  --target-branch <target-branch> \
  --work-items $workItemId  # Optional: include if work item exists

# Clean up
Remove-Item "pr_desc.txt" -Force
```

**If no work item:** Omit the `--work-items` parameter entirely.

### Step 2: Configure Auto-Complete and Tags

**After creating the PR**, configure auto-complete and apply tags based on target branch and user input:

**For `main` branch** (squash merge):
```powershell
$prId = <pr-id-from-creation>
$orgUrl = "https://dev.azure.com/msazure"
$project = "One"
$repo = "AAPT-APIManagement"

# Configure auto-complete
az repos pr update --id $prId `
  --auto-complete true `
  --squash true `
  --delete-source-branch true

# Apply tags using REST API
$token = az account get-access-token --resource "499b84ac-1321-427f-aa17-267ca6975798" --query accessToken -o tsv
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Component tag (required - user selected from allowed list)
$componentTag = "<Component>"  # e.g., Feature, Fix, Chore, Security
$body = @{ "name" = $componentTag } | ConvertTo-Json
Invoke-RestMethod -Uri "$orgUrl/$project/_apis/git/repositories/$repo/pullRequests/$prId/labels?api-version=7.1-preview.1" -Method POST -Headers $headers -Body $body

# Change type tag (always apply)
$changeTypeTag = "<Internal|CustomerFacing>"
$body = @{ "name" = $changeTypeTag } | ConvertTo-Json
Invoke-RestMethod -Uri "$orgUrl/$project/_apis/git/repositories/$repo/pullRequests/$prId/labels?api-version=7.1-preview.1" -Method POST -Headers $headers -Body $body

# If CustomerFacing, add SKU tags
if ($changeTypeTag -eq "CustomerFacing") {
    $skuTags = @("<SKU1>", "<SKU2>")  # e.g., AllSKU, SKUv1, Consumption
    foreach ($sku in $skuTags) {
        $body = @{ "name" = $sku } | ConvertTo-Json
        Invoke-RestMethod -Uri "$orgUrl/$project/_apis/git/repositories/$repo/pullRequests/$prId/labels?api-version=7.1-preview.1" -Method POST -Headers $headers -Body $body
    }
}
```

**For all other branches** (merge, no fast-forward):
```powershell
$prId = <pr-id-from-creation>
$orgUrl = "https://dev.azure.com/msazure"
$project = "One"
$repo = "AAPT-APIManagement"

# Configure auto-complete
az repos pr update --id $prId `
  --auto-complete true `
  --squash false `
  --delete-source-branch true

# Apply tags using REST API (same as above, plus allow-merge-no-fast-forward)
$token = az account get-access-token --resource "499b84ac-1321-427f-aa17-267ca6975798" --query accessToken -o tsv
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Add allow-merge-no-fast-forward tag
$body = @{ "name" = "allow-merge-no-fast-forward" } | ConvertTo-Json
Invoke-RestMethod -Uri "$orgUrl/$project/_apis/git/repositories/$repo/pullRequests/$prId/labels?api-version=7.1-preview.1" -Method POST -Headers $headers -Body $body

# Add component tag, change type tag, and SKU tags (same as above)
```

### Azure DevOps Web UI
1. **Repos** > **Pull Requests** > **New Pull Request**
2. Select source branch and **verify target branch**
3. Fill title (use format above)
4. **View template** at `.azuredevops/pull_request_template/branches/<target>.md`
5. **Copy template content** into PR description field
6. Complete ALL template sections (use work item info if available)
7. **Link work items** (if available - click "Add work item" and enter ID)
8. Add reviewers (see `owners.txt`)
9. Click **Create**
10. **Add tags**:
    - Component tag (from scope)
    - `Internal` or `CustomerFacing`
    - If CustomerFacing: SKU tags (AllSKU, SKUv1, SKUv2, Consumption, CNAG, Self-Hosted, Workspace, AOAIHub)
11. **Enable auto-complete**:
    - For `main`: Select "Squash commit"
    - For other branches: Select "Merge (no fast-forward)" and add label "allow-merge-no-fast-forward"

## PR Title Best Practices

**Use work item information when available:**
- If work item exists: Incorporate work item title/summary
- Keep title clear and descriptive
- Follow semantic format: `<type>(<scope>): <description>`

**Examples:**
- With work item: `feat(gateway): Add WebSocket policy support for #12345`
- Without work item: `feat(gateway): Add WebSocket policy support`
- Bug fix with work item: `fix(rp): Resolve orchestration deadlock (fixes #67890)`

## PR Tags Reference

### Component Tags (Required for PR Labels)

**All PRs must have ONE component tag from:**
- `MSRC` - Security response center issues
- `Security` - Security improvements
- `Compliance` - Compliance-related changes
- `Feature` - New features
- `Fix` - Bug fixes
- `Test` - Test additions/updates
- `LiveSite` - Production incident fixes
- `Chore` - Maintenance tasks
- `Performance` - Performance improvements
- `Dependencies` - Dependency updates
- `Deployment` - Deployment changes
- `CI` - CI/CD pipeline changes

**Note:** These component tags are separate from PR title scopes (gateway, rp, rcm, etc.). Always ask user to select the appropriate component tag.

### Change Type Tags
- `Internal` - Changes not visible to customers (internal refactoring, tooling, tests)
- `CustomerFacing` - Changes visible to customers (features, bug fixes, API changes)

### SKU Tags (for CustomerFacing changes)
- `AllSKU` - Applies to all SKUs
- `SKUv1` - SKU v1 (Developer, Basic, Standard, Premium)
- `SKUv2` - SKU v2 (Standard v2, Premium v2)
- `Consumption` - Consumption tier
- `CNAG` - Cloud-native API Gateway
- `Self-Hosted` - Self-hosted gateway
- `Workspace` - Workspace
- `AOAIHub` - Azure OpenAI Hub

**Reference:** https://eng.ms/docs/coreai/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-team-docs/fundamentals/development/pr-tags

## Reviewer Selection

Consult `owners.txt`:
- **ResourceProvider:** RP team
- **Gateway:** Gateway team
- **RCM:** RCM team
- **Cross-component:** Multiple teams
- **Breaking changes:** Engineering leads

## After Creating PR

1. Monitor CI/CD pipeline - fix failures immediately
2. Respond to feedback promptly
3. Keep updated - merge `main` if conflicts
4. Link to work items

**IMPORTANT - Post-PR Actions:**
- ✅ **Sign "Proof of Presence"** - Required for all PRs
- ✅ **Fill in PR Questionnaire** - Answer all questions

These are mandatory steps after creating the PR!

## Updating Existing PR

**When pushing new changes to a branch with an existing PR**, always update the PR description:

```powershell
# Get PR ID for your branch
$prId = (az repos pr list --source-branch <your-branch> --status active --query "[0].pullRequestId" -o tsv)

# Prepare updated description
$description = @'
<updated-template-content>
'@
$description | Out-File -FilePath "pr_desc.txt" -Encoding utf8 -NoNewline

# Update PR description
az repos pr update --id $prId --description "@pr_desc.txt"

# Clean up
Remove-Item "pr_desc.txt" -Force
```

**Update description when:**
- Problem/solution changes
- New validation steps added
- Risk level changes
- Scope expands or changes

**Keep updates concise** - same guidelines as initial description.

## PR Size Guidelines

- **Ideal:** < 400 lines
- **Large PRs:** Break into multiple (discuss with team)
- **Exceptions:** Generated code, dependency updates, approved large refactors

## Common Pitfalls

❌ **Avoid:**
- Mixing unrelated changes
- Commented-out code without explanation
- Debug logs/console output
- Failing tests
- Broad unrelated formatting changes
- **Automatically recreating abandoned PRs without user confirmation**

✅ **Do:**
- Single logical change per PR
- Clear commit messages
- Test edge cases
- Update tests with code changes
- Communicate breaking changes
- Respond to feedback
- **Ask user before creating new PR if previous one was abandoned**

## Hotfix Process

For critical production issues:
1. **Confirm target:** Which hotfix branch? (`hotfix`, `hotfix-gw`, `hotfix-rp`, `hotfix-mgmt`, `hotfix-shgw`)
2. **Sync branch:** `git merge origin/<hotfix-branch>`
3. **Minimal fix only**
4. **Use hotfix template:** Must justify urgency, customer impact, rollback plan
5. **Title:** `fix(HOTFIX): <description>`
6. **Tests required:** Unit test, BVT, Scenario test
7. **Tag leads** for immediate review
8. **Coordinate deployment** with ops

## Resources

- Component conventions: `.github/instructions/`
- Build/test: `README.md`
- Past PRs for examples
