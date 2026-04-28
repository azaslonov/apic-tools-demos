---
name: rp-integration-test-investigator
description: |
  Investigate RP integration test failures from ADO pipeline runs. Provides:
  - Retry filtering to focus on consistent failures (not flaky tests)
  - Owner-based filtering to investigate only tests assigned to you
  - Hypothesis-driven root cause analysis
  - ADO bug creation with detailed repro steps (max 3 per run)
  - Summary file generation
  
  Triggers: "investigate RP integration tests", "RP test failures", 
  "analyze RP pipeline", "investigate tests assigned to me",
  pipeline URLs containing "ResourceProvider.IntegrationTests"
---

# RP Integration Test Investigator

Automated investigation workflow for RP integration test failures with ADO bug filing.

## ⚠️ CRITICAL: Data Sources

> **Use ADO MCP tools for all pipeline and test data. Do NOT use GitHub MCP tools for logs or test results.**

| Data Type | Use This | NOT This |
|-----------|----------|----------|
| Build status | `ado-pipelines_get_build_status` | ❌ GitHub Actions |
| Test results | `ado-testplan_show_test_results_from_build_id` | ❌ GitHub API |
| Build logs | `ado-pipelines_get_build_log` | ❌ GitHub job logs |
| Work items/bugs | `ado-wit_*` and `ado-search_workitem` | ❌ GitHub Issues |
| Telemetry | `apim-kusto-agent` (task tool) | - |
| Test source code | `grep/glob` (local filesystem) | ✅ OK to use |

**Why**: RP integration tests run in Azure DevOps pipelines, not GitHub Actions. All logs, test results, and work items are in ADO.

## ⚠️ Prerequisites

Before starting an investigation, **start the apim-kusto-agent** for Kusto queries:

```
/agent apim-kusto-agent
```

This enables automated Kusto telemetry queries during root cause analysis.

---

## Session State & Resume

Investigation state is saved to allow resuming if interrupted:

**Session Directory**: `.caretaker/sessions/rp-investigation-{buildId}/`

| File | Purpose |
|------|---------|
| `state.json` | Current investigation progress and test list |
| `test-results.json` | Cached test results from ADO |
| `investigated-tests.json` | Tests already investigated with findings |
| `bugs-filed.json` | Bugs created during this session |

### Resume an Interrupted Session

```
Resume RP integration test investigation for build 151222318
```

The skill will:

1. Check for existing session at `.caretaker/sessions/rp-investigation-{buildId}/`
2. Load cached test results and progress
3. Continue from the last investigated test
4. Skip tests already investigated

### Session State Schema

```json
// state.json
{
  "buildId": "151222318",
  "startedAt": "2026-01-30T10:00:00Z",
  "lastUpdatedAt": "2026-01-30T10:15:00Z",
  "status": "in_progress",
  "totalTests": 5,
  "investigatedCount": 2,
  "currentTestIndex": 2,
  "ownerFilter": "johndoe"
}

// investigated-tests.json
[
  {
    "testName": "TestClass.TestMethod",
    "investigatedAt": "2026-01-30T10:10:00Z",
    "rootCause": "Service activation timeout",
    "hypothesis": "High",
    "bugFiled": true,
    "bugId": 12345678,
    "isTransient": false
  }
]

// bugs-filed.json
[
  {
    "bugId": 12345678,
    "title": "[RP Integration Test] SKUv1 - Activation timeout",
    "testNames": ["TestClass.TestMethod"],
    "createdAt": "2026-01-30T10:12:00Z"
  }
]
```

---

## Quick Start

### Investigate all failures

```
Investigate RP integration test failures: https://dev.azure.com/msazure/One/_build/results?buildId=151222318
```

### Investigate only tests assigned to me

```
Investigate RP integration test failures assigned to me: https://dev.azure.com/msazure/One/_build/results?buildId=151222318
My alias is: johndoe
```

### Investigate tests assigned to a specific owner

```
Investigate RP integration test failures owned by nimak: https://dev.azure.com/msazure/One/_build/results?buildId=151222318
```

---

## Workflow

```
0. Prerequisites → Start apim-kusto-agent with /agent apim-kusto-agent
1. Init Session  → Create/load session state at .caretaker/sessions/rp-investigation-{buildId}/
2. Get Results   → Use ADO MCP tools to fetch test results, apply retry filtering
3. Filter Owner  → (Optional) Filter to tests owned by specified alias
4. Investigate   → Root cause analysis using ADO logs + apim-kusto-agent (save progress after each test)
5. File Bugs     → Check ADO, create bugs for new issues (max 3)
6. Report        → Save summary file and mark session complete
```

> ⚠️ **IMPORTANT**: All data comes from ADO. Do NOT call GitHub MCP tools for build/test information.

---

## Step 1: Get Test Results

### 1a. Parse Pipeline URL

Extract `buildId` from URL patterns:

- `https://dev.azure.com/msazure/One/_build/results?buildId={buildId}`
- `https://msazure.visualstudio.com/One/_build/results?buildId={buildId}`

### 1b. Initialize or Resume Session

**Check for existing session:**

```
Check if .caretaker/sessions/rp-investigation-{buildId}/ exists
```

**If session exists (resume):**

1. Load `state.json` to get current progress
2. Load `test-results.json` for cached test data  
3. Load `investigated-tests.json` to skip already-investigated tests
4. Load `bugs-filed.json` to track bug count
5. Report resume status to user:

   ```
   Resuming investigation for build {buildId}
   Progress: {investigatedCount}/{totalTests} tests investigated
   Last updated: {lastUpdatedAt}
   ```

**If no session (new):**

1. Create session directory: `.caretaker/sessions/rp-investigation-{buildId}/`
2. Initialize `state.json` with buildId and timestamp
3. Continue to fetch test results

### 1c. Get Build Status

```
ado-pipelines_get_build_status:
  project: "One"
  buildId: {extracted buildId}
```

### 1d. Get Test Results

```
ado-testplan_show_test_results_from_build_id:
  project: "One"
  buildid: {buildId}
```

**Save test results to session:**

```
Save results to .caretaker/sessions/rp-investigation-{buildId}/test-results.json
```

### 1e. Apply Retry Filtering (CRITICAL)

**Only investigate tests that failed ALL retry attempts.**

For each distinct test name:

1. Group all test executions by fully qualified name
2. If ANY execution passed → **SKIP** (flaky but passed)
3. If ALL executions failed → **INVESTIGATE**

**Update session state:**

```
Update state.json with totalTests count and status
```

```markdown
## Retry Filtering Summary

**Total test executions**: X
**Distinct tests**: Y
**Passed on retry (skipped)**: Z
**Consistently failing (investigating)**: W
```

### 1f. Extract Test Names from Logs (if needed)

If test results API doesn't return test names, extract from build logs:

```
ado-pipelines_get_build_log:
  project: "One"
  buildId: {buildId}
```

Look for patterns:

- `Failed   TestNamespace.TestClass.TestMethod`
- `Error Message:` followed by test context
- Stack traces containing test method names

---

## Step 1.5: Filter by Test Owner (Optional)

> Use this step when investigating only tests assigned to you or a specific owner.

### When to Use Owner Filtering

- "Investigate tests assigned to me"
- "Investigate tests owned by {alias}"
- When you only want to focus on tests you're responsible for

### Step 1: Get User Alias

If the user says "assigned to me", ask for their alias:

```
What is your alias? (e.g., johndoe)
```

### Step 2: Find Test Files with Owner Attribute

Search for test files with the `[Owner("alias")]` attribute:

```bash
# Find all tests owned by a specific alias
grep -r '\[Owner("{alias}"\)' Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/ --include="*.cs" -l
```

### Step 3: Extract Owned Test Methods

For each file found, extract the test method names:

```bash
# Get test methods from a file
grep -B5 '\[TestMethod\]' {test-file} | grep -E '\[Owner\("{alias}"\)|public.*void|public.*async.*Task'
```

### Step 4: Match Against Failing Tests

Compare the owned test methods against the failing tests from Step 1d:

```
For each failing test (from retry filtering):
  - Extract test class and method name
  - Check if test file has [Owner("{alias}")] attribute
  - If owned by user → INCLUDE in investigation
  - If not owned → SKIP (note in summary)
```

### Step 5: Report Filtered Results

```markdown
## Owner Filtering Summary

**Owner Alias**: {alias}
**Total failing tests**: X
**Tests owned by {alias}**: Y
**Tests owned by others (skipped)**: Z

### Tests to Investigate (Owned by {alias})
| Test Name | File |
|-----------|------|
| TestClass.TestMethod | SKUv2/TestClass.cs |

### Tests Skipped (Different Owner)
| Test Name | Owner | File |
|-----------|-------|------|
| OtherClass.OtherMethod | otheruser | General/OtherClass.cs |
```

### Owner Attribute Patterns

Tests use MSTest `[Owner]` attribute:

```csharp
[TestClass]
public class MyTests
{
    [Owner("johndoe")]
    [TestMethod]
    public void MyTest_ShouldPass()
    {
        // ...
    }
    
    [Owner("janesmith")]
    [TestMethod]
    public async Task AnotherTest_Async()
    {
        // ...
    }
}
```

**Note**: The `[Owner]` attribute can be at:

- **Method level**: Applies to that specific test
- **Class level**: Applies to all tests in the class (unless overridden at method level)

### Handling Missing Owner Attributes

If a test doesn't have an `[Owner]` attribute:

- Check git history for the test file: `git log --oneline -5 -- {test-file}`
- The most recent committer may be the de-facto owner
- Note as "Owner: Unknown" in the summary

---

## Step 2: Investigate Failures

For each consistently failing test, follow hypothesis-driven root cause analysis.

### 2a. Extract Service Name from Test Logs (CRITICAL)

> ⚠️ **CRITICAL**: Before running any Kusto queries, you MUST extract the service name from test logs.

Search test logs for patterns like:

```
ServiceCreateOrUpdateStarting, message: Service Int-Developer-697c2ff607088f073c781941
```

**Common service name patterns:**

- `Int-{SKU}-{guid}` (e.g., `Int-Developer-697c2ff607088f073c781941`)
- `Int-{SKU}-{testname}` (e.g., `Int-Premium-ScaleTest`)

Use the extracted service name in ALL subsequent Kusto queries. See `references/investigation-workflow.md` Phase 1.5 for detailed extraction steps.

### 2b. Understand the Failure

| Question | How to Answer |
|----------|---------------|
| What did the test expect? | Read test source code |
| What actually happened? | Check error message and stack trace |
| What category is this test? | Check `[TestCategory]` attribute |

**Test Categories:**

- General, Scalability, SKUv1, SKUv2, Consumption, PremiumV2
- WorkspaceGateway, KubernetesManagedGateway, AIPlatform, GatewayV2

### 2c. Check for STOP Patterns (Manual Action Required)

> ⛔ **CRITICAL**: Check for these patterns FIRST. If found, STOP and prompt for manual action.

**Test Framework Timeout (3 hours)**:

```
timed out after 10800000ms
```

If this pattern is found:

1. **STOP** - Do NOT proceed with automated investigation
2. **Do NOT file a bug** - This is not a product bug
3. **Prompt for manual action** with this message:

```
⛔ MANUAL ACTION REQUIRED

The test `{TestName}` timed out after 3 hours (10800000ms).

This is a test infrastructure issue, not a product bug. Please investigate manually:
1. Check if any orchestrations are stuck for this service
2. Verify the test environment health
3. Check if external dependencies (DNS, KeyVault, etc.) are responding
4. Consider if the test needs timeout optimization

Service Name: {serviceName}
Build: {buildId}
Test Owner: {ownerAlias}
```

### 2d. Check for Transient Patterns

See `references/known-errors.md` for patterns to SKIP:

- Rolling upgrade in progress
- File access conflicts
- Queue deletion errors
- Throttling (429)

**If transient:** Note in summary, do NOT file bug.

### 2e. Query Kusto for Telemetry (AUTOMATED - apim-kusto-agent)

> ⚠️ **CRITICAL**: Use the `apim-kusto-agent` to automatically run Kusto queries for root cause analysis. The agent will independently execute queries and return findings.

#### Starting the apim-kusto-agent

**Invoke the apim-kusto-agent with the task tool:**

```
task(
  agent_type: "apim-kusto-agent",
  description: "Investigate {TestName} failure telemetry",
  prompt: "<detailed prompt with context>"
)
```

#### Required Context to Provide to apim-kusto-agent

When invoking the kusto agent, **ALWAYS provide the following context**:

1. **Service Name**: The APIM service name extracted from test logs (e.g., `Int-Developer-697c2ff607088f073c781941`)
2. **Time Range**: Start and end timestamps from the test execution
3. **SKU Type**: Which SKU the test targets (SKUv1, SKUv2, Consumption, etc.)
4. **Failure Type**: What kind of failure occurred (activation, backup, restore, scaling, etc.)
5. **Error Message**: The specific error or exception from test logs
6. **Orchestration Name** (if known): e.g., `ActivateApiService`, `BackupApiService`, `RestoreApiService`

#### apim-kusto-agent Prompt Template

```
Investigate RP integration test failure in APIMTest database.

**Context:**
- Service Name: {serviceName}
- Time Window: {startTime} to {endTime}
- SKU Type: {skuType}
- Test Category: {testCategory}
- Failure Type: {failureType}
- Error from test logs: {errorMessage}

**Investigation Tasks:**
1. Query the Orchestration table for errors related to this service
2. Check for any failed orchestration events (Level < 3)
3. Look for specific exception messages or stack traces
4. Identify the root cause of the failure
5. Provide a summary with:
   - What failed and when
   - The specific error/exception
   - Root cause hypothesis
   - Evidence supporting the hypothesis

**Important:**
- Use All('TableName') syntax for all queries
- Database: APIMTest (test environment)
- Focus on Level < 3 (Error and Warning) entries
- Look for patterns like: {operationPattern}
```

#### SKU-Specific Query Strategy

| SKU Type | Primary Tables | Focus Areas |
|----------|----------------|-------------|
| SKUv1 (Developer, Basic, Standard, Premium) | `All('Orchestration')`, `All('ResourceProvider')`, `All('Mapi')`, `All('HttpIncomingRequests')`, `All('ApiSvcHost')`, `All('MapiInfra')` | Activation orchestration, DSC events, VMSS provisioning |
| SKUv2 (BasicV2, StandardV2, PremiumV2) | `All('Orchestration')`, `All('ResourceProvider')`, `All('Mapi')`, `All('HttpIncomingRequests')`, `All('ManagementKpi')`, `All('ProxyRequest')` | PreProvisioned activation, SKUv2 orchestrations |
| Consumption | `All('Orchestration')`, `All('ResourceProvider')`, `All('Mapi')` + Antares tables | Website provisioning, Consumption activation |
| Workspace Gateway | `All('Orchestration')`, `All('GatewayControlPlaneRequests')` | Gateway provisioning, workspace operations |

#### Example apim-kusto-agent Invocations

**For Activation Failures:**

```
task(
  agent_type: "apim-kusto-agent",
  description: "Investigate activation failure",
  prompt: "Investigate RP integration test failure in APIMTest database.

**Context:**
- Service Name: Int-Developer-697c2ff607088f073c781941
- Time Window: 2026-01-30T10:15:00Z to 2026-01-30T10:25:00Z
- SKU Type: SKUv1 (Developer)
- Failure Type: Service activation timeout

**Investigation:**
1. Query All('Orchestration') for serviceName='Int-Developer-697c2ff607088f073c781941' with Level < 3
2. Look for ActivateApiService orchestration failures
3. Check for any exceptions or stuck orchestration instances
4. Identify what step in activation failed and why

Provide root cause analysis with supporting evidence."
)
```

**For Backup/Restore Failures:**

> ⚠️ **Backup Test Operations**: The Backup test performs 3 main operations:
>
> 1. **Create Database** - Uses COPY AS SQL command with 30-minute timeout
> 2. **Export Contents** - Exports to storage account
> 3. **Export BacPac** - Exports DB to storage as BacPac file with 1-hour timeout

```
task(
  agent_type: "apim-kusto-agent",
  description: "Investigate backup failure",
  prompt: "Investigate RP integration test Backup failure using ONLY the Orchestration table.

**Context:**
- Service Name: Int-Premium-abc123
- Time Window: 2026-01-30T14:00:00Z to 2026-01-30T14:30:00Z
- SKU Type: SKUv1 (Premium)
- Failure Type: Backup operation failed
- Tenant: {tenant from test logs, e.g., api-am2-prod-01}

**Investigation - Use Orchestration Table Only:**

1. **Check for Database Creation Issues** (30-min timeout):
   Query to find database creation failures during backup:
   ```kql
   let period = 1d;
   let svcName = 'Int-Premium-abc123';  // Use actual service name
   All('Orchestration')
   | where eventType == 'UpdatingApiServiceContainer'
   | where PreciseTimeStamp > ago(period)
   | where serviceName == svcName
   | project PreciseTimeStamp, instanceId, eventType, duration, message, serviceName
   | order by PreciseTimeStamp desc
   | join kind=inner (
       All('Orchestration') 
       | where eventType == 'BackupApiServiceOrchestrationFailed' and PreciseTimeStamp > ago(period)
       | where serviceName == svcName
       | project PreciseTimeStamp, instanceId, eventType, message, exception, serviceName
   ) on instanceId
   | extend messageJson = parse_json(message)
   | extend region = tostring(messageJson['MasterLocation'])
   | project PreciseTimeStamp, region, instanceId, serviceName
   | summarize count() by bin(PreciseTimeStamp, 1h), region, serviceName
   ```

1. **Check for Export/BacPac Failures** (1-hour timeout):
   Query to find SQL Import/Export operation failures:

   ```kql
   let _startTime = ago(1d);
   let _endTime = now();
   let clusterName = '{tenant}';
   let svcName = 'Int-Premium-abc123';  // Use actual service name
   All('Orchestration')
   | where eventType in ('BackupApiServiceOrchestrationFailed', 'BackupApiServiceOrchestrationFailedDueToInvalidInput')
   | where PreciseTimeStamp between (_startTime .. _endTime)
   | where Tenant == clusterName
   | where serviceName == svcName
   | project PreciseTimeStamp, Region, eventType, instanceId, serviceName, subscriptionId, exceptionMessage = substring(exception, 0, 600)
   | join kind=inner (
       All('Orchestration')
       | where PreciseTimeStamp between (_startTime .. _endTime)
       | where Tenant == clusterName
       | where serviceName == svcName
       | where eventType in ('WaitForSqlImportExportOperationRunning')
       | extend mjson = parse_json(message)
       | extend pollingLocation = tostring(mjson['PollingLocation'])
       | extend requestId = tostring(mjson['AsyncOperation']['properties']['requestId'])
       | extend queuedTime = todatetime(mjson['AsyncOperation']['properties']['queuedTime'])
       | extend serverName = tostring(mjson['AsyncOperation']['properties']['serverName'])
       | extend databaseName = tostring(mjson['AsyncOperation']['properties']['databaseName'])
       | extend requestStatus = tostring(mjson['AsyncOperation']['properties']['status'])
   ) on instanceId
   | project PreciseTimeStamp, subscriptionId, serviceName, requestId, queuedTime, serverName, databaseName, codeVersion, Tenant, exceptionMessage, requestStatus, pollingLocation
   | summarize count(), min(PreciseTimeStamp), max(PreciseTimeStamp) by requestId, queuedTime, Tenant, subscriptionId, serviceName, serverName, databaseName, codeVersion, exceptionMessage
   ```

2. **Identify Failure Type**:
   - If UpdatingApiServiceContainer has long duration → Database creation timeout
   - If WaitForSqlImportExportOperationRunning shows 'Failed' status → Export failure
   - Check exception messages for specific error causes

Provide root cause analysis with supporting evidence. Focus on whether this is a transient SQL/storage issue or a code bug."
)

```

**For Consumption SKU Failures:**
```

task(
  agent_type: "apim-kusto-agent",
  description: "Investigate Consumption activation",
  prompt: "Investigate RP integration test failure in APIMTest database.

**Context:**

- Service Name: Int-Consumption-test456
- Time Window: 2026-01-30T09:00:00Z to 2026-01-30T09:15:00Z
- SKU Type: Consumption
- Failure Type: Website provisioning failed

**Investigation:**

1. Query All('Orchestration') for ActivateConsumptionServiceOrchestration events
2. Check for DeployWebsiteOrchestration failures
3. Look for Antares/App Service provisioning errors
4. Check websiteSubscriptionId and resource quota issues

Provide root cause analysis with supporting evidence."
)

```

#### Interpreting apim-kusto-agent Results

The kusto agent will return:
- **Query results** with relevant telemetry data
- **Summary of findings** explaining what the data shows
- **Root cause hypothesis** based on evidence
- **Kusto queries** used (for reproduction)

Use the agent's findings to:
1. Confirm or refine your hypothesis
2. Determine if the failure is transient vs persistent
3. Decide whether to file a bug or skip
4. Include evidence in the bug report

### 2e. Gather Additional Evidence

| Source | Tool | What to Look For |
|--------|------|------------------|
| Test source | `grep/glob` in `Test/Bvt/ResourceProvider/` | Assertions, setup, dependencies |
| Recent changes | `git log --since="7 days ago"` | Changes to test or RP code |
| Build logs | `ado-pipelines_get_build_log` | Full error context, **service name** |

### 2e. Generate Hypotheses

For each failure, rank hypotheses by likelihood:

```markdown
### Hypothesis 1: [Description]
- **Likelihood**: High / Medium / Low
- **Evidence For**: [What supports this]
- **Evidence Against**: [What contradicts this]
- **Validation**: [How to prove/disprove]
```

### 2e. Identify Root Cause

```markdown
## Root Cause

**Cause**: [Clear statement]
**Confidence**: High / Medium / Low
**Evidence**:
- [Evidence 1]
- [Evidence 2]
```

### 2f. Save Investigation Progress (After Each Test)

**After completing investigation for each test, save progress to session:**

```
Append to .caretaker/sessions/rp-investigation-{buildId}/investigated-tests.json:
{
  "testName": "{fully qualified test name}",
  "investigatedAt": "{timestamp}",
  "rootCause": "{root cause summary}",
  "hypothesis": "{confidence level}",
  "bugFiled": false,
  "bugId": null,
  "isTransient": {true/false}
}

Update .caretaker/sessions/rp-investigation-{buildId}/state.json:
- investigatedCount++
- currentTestIndex++
- lastUpdatedAt = {timestamp}
```

This ensures that if investigation is interrupted, progress is preserved and can be resumed.

---

## Step 3: Check ADO and Create Bugs

For each distinct root cause identified:

### 3a. Search ADO First

> ⚠️ **IMPORTANT:** Search ADO BEFORE creating bugs to avoid duplicates.

```
ado-search_workitem:
  searchText: "{error type} {class/method}"
  project: ["One"]
  areaPath: ["One\\AAPT\\Servers and Services\\API Management\\Platform"]
  state: ["Active", "New", "Triaged"]
```

- **If existing bug found:** Note in summary, move on
- **If no bug found:** Create one (see below)

### 3b. Create Bug (if new issue)

See `references/ado-config.md` for full configuration and repro steps template.

> ⚠️ **CRITICAL - Include ALL Data Inline:** GitHub Copilot cannot access external links, logs, or Kusto. You MUST include:
>
> - **Complete stack trace** from ADO (not truncated)
> - **Full error message** from ADO
> - **Kusto query results** pasted inline (not just the query)
> - **Test owner** from `[Owner("alias")]` attribute
>
> Links to builds, test runs, or "see Kusto" are useless to Copilot!

```
ado-wit_create_work_item:
  project: "One"
  workItemType: "Bug"
  fields:
    - name: "System.Title"
      value: "[RP Integration Test] {Category} - {Specific Description}"
    - name: "System.AreaPath"
      value: "One\\AAPT\\Servers and Services\\API Management\\Platform"
    - name: "System.Tags"
      value: "RP-Integration-Test"
    - name: "Microsoft.VSTS.TCM.ReproSteps"
      value: "{repro steps with COMPLETE stack trace, error message, Kusto results inline}"
      format: "Html"
```

### 3c. Link to Parent and Branch, Then Assign to GitHub Copilot

> ⚠️ **CRITICAL ORDER:** You MUST follow this exact order:
>
> 1. Link to parent feature
> 2. Link to main branch ← **Required before assignment!**
> 3. Assign to GitHub Copilot ← **Last step!**
>
> GitHub Copilot cannot start working without the branch link. Do NOT assign to the test owner.

```
# Step 1: Link to parent feature
ado-wit_work_items_link:
  project: "One"
  updates:
    - id: {bugId}
      linkToId: 36600929
      type: "parent"

# Step 2: Link to main branch (MUST be before assignment)
ado-wit_add_artifact_link:
  workItemId: {bugId}
  project: "One"
  linkType: "Branch"
  repositoryId: "141a6ca5-3ad0-4c0f-9992-e52cc9d7a8f9"
  branchName: "main"

# Step 3: Assign to GitHub Copilot (MUST be after branch link)
ado-wit_update_work_item:
  id: {bugId}
  updates:
    - path: "/fields/System.AssignedTo"
      value: "66dda6c5-07d0-4484-9979-116241219397@72f988bf-86f1-41af-91ab-2d7cd011db47"
```

### 3d. Save Bug to Session

**After creating a bug, save to session state:**

```
Append to .caretaker/sessions/rp-investigation-{buildId}/bugs-filed.json:
{
  "bugId": {bugId},
  "title": "{bug title}",
  "testNames": ["{test1}", "{test2}"],
  "createdAt": "{timestamp}"
}

Update investigated-tests.json entry:
- bugFiled = true
- bugId = {bugId}
```

### 3e. Bug Limit

Create maximum **3 new bugs** per run. Prioritize by:

1. Tests blocking multiple scenarios
2. Tests with clear root cause
3. Tests with highest failure count

If more than 3 new issues found, note extras in summary without creating bugs.

---

## Step 4: Generate Summary and Complete Session

Save summary to `.caretaker/rp-integration-test-summary-{buildId}.md`

See `references/summary-template.md` for full format.

```markdown
# RP Integration Test Investigation - Build {buildId}

**Pipeline**: {URL}
**Build ID**: {buildId}
**Status**: {Failed/PartiallySucceeded}
**Investigated**: {timestamp}

## Retry Filtering Summary
...

## Executive Summary
...

## Issue 1: {Root Cause}
...

## Work Items Summary
...
```

**Mark session complete:**

```
Update .caretaker/sessions/rp-investigation-{buildId}/state.json:
- status = "completed"
- completedAt = {timestamp}
```

The session directory is preserved for reference. To clean up old sessions:

```
Remove sessions older than 7 days from .caretaker/sessions/
```

---

## Test Source Locations

| Category | Location |
|----------|----------|
| General | `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/` |
| SKUv1 | `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/SKUv1/` |
| SKUv2 | `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/SKUv2/` |
| Consumption | `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/Consumption/` |
| Gateway | `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/Gateway/` |
| Infra | `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/Infra/` |
| Upgrade | `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/Upgrade/` |

## Finding Test Owners

Look for `[Owner("alias")]` attribute in test files:

```bash
grep -B5 "TestMethodName" <test-file-path> | grep -i "Owner"
```

---

## References

| Reference | Purpose |
|-----------|---------|
| `references/ado-config.md` | ADO bug creation settings and templates |
| `references/investigation-workflow.md` | Detailed investigation methodology |
| `references/kusto-queries.md` | RP-specific Kusto queries for APIMTest |
| `references/known-errors.md` | Common error patterns (transient vs persistent) |
| `references/summary-template.md` | Output format template |

---

## MCP Tools Used

### ✅ ADO Tools (USE THESE)

| Tool | Purpose |
|------|---------|
| `ado-pipelines_get_build_status` | Get build details and status |
| `ado-pipelines_get_build_log` | Get build/test logs |
| `ado-testplan_show_test_results_from_build_id` | Get test results |
| `ado-search_workitem` | Search for existing bugs |
| `ado-wit_create_work_item` | Create new bugs |
| `ado-wit_work_items_link` | Link bugs to parent feature |
| `ado-wit_add_artifact_link` | Link bugs to branch |
| `ado-wit_update_work_item` | Assign bugs |

### ✅ Other Tools (USE THESE)

| Tool | Purpose |
|------|---------|
| `apim-kusto-agent` (via task tool) | Query APIMTest for telemetry |
| `grep/glob` | Find test source code in local repo |
| `git` | Analyze recent changes |

### ❌ GitHub Tools (DO NOT USE)

Do NOT use these tools - RP integration tests are in ADO, not GitHub:

- `github-mcp-server-actions_*` - GitHub Actions (wrong CI system)
- `github-mcp-server-get_job_logs` - GitHub job logs (wrong CI system)
- `github-mcp-server-list_*` for workflows/runs - GitHub workflows (wrong CI system)

---

## File Locations

- **Session Directory**: `.caretaker/sessions/rp-investigation-{buildId}/`
  - `state.json` - Investigation progress
  - `test-results.json` - Cached ADO test results
  - `investigated-tests.json` - Completed investigations
  - `bugs-filed.json` - Bugs created
- **Summary**: `.caretaker/rp-integration-test-summary-{buildId}.md`
- **Test Source**: `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/`
- **Pipeline Definition**: `Test/Bvt/ResourceProvider/.pipelines/templates/run-integration-test.yml`
