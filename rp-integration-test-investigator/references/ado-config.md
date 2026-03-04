# ADO Configuration

Configuration for Azure DevOps work item management for RP integration test failures.

---

## Project Configuration

| Setting | Value |
|---------|-------|
| **Organization** | msazure |
| **Project** | One |
| **Area Path** | `One\AAPT\Servers and Services\API Management\Platform` |
| **Parent Feature** | 36600929 |

---

## Work Item Settings

### Bug Creation

| Field | Value |
|-------|-------|
| **Work Item Type** | Bug |
| **Tags** | `RP-Integration-Test` |
| **Assigned To** | GitHub Copilot |
| **Assigned To ID** | `66dda6c5-07d0-4484-9979-116241219397@72f988bf-86f1-41af-91ab-2d7cd011db47` |

### Title Format

```
[RP Integration Test] {TestCategory} - {Specific Bug Description}
```

> ⚠️ Title should describe the **actual bug**, not a generic test failure. Include test category.

Examples:
- ✅ `[RP Integration Test] SKUv2 - NullReferenceException in TenantValidator during CreateApiService`
- ✅ `[RP Integration Test] Consumption - Timeout during scale-out operation in ScaleApiServiceTest`
- ✅ `[RP Integration Test] General - ArgumentException when parsing malformed subscription ID`
- ❌ `[RP Integration Test] Test failed` (too generic)
- ❌ `[RP Integration Test] SKUv1 test failure in eastus` (region not in title unless region-specific)

---

## Search Criteria

> ⚠️ **IMPORTANT:** Search ADO BEFORE deep investigation to avoid wasting time on known issues.

Before investigating or creating a bug, search for existing items:

```
Project: One
Area Path: One\AAPT\Servers and Services\API Management\Platform
Tags: RP-Integration-Test
State: NOT IN (Closed, Resolved, Removed)
```

**Also search by keywords:**
- Exception type (e.g., "NullReferenceException", "TimeoutException")
- Error message keywords
- Test class/method names (e.g., "CreateApiServiceTest")
- RP component names (e.g., "TenantValidator", "OrchestrationManager")

If a matching item is found:
1. **Skip deep investigation** - no need to re-investigate known issues
2. Note the existing item in the summary with bug ID and URL
3. Do NOT create a duplicate bug
4. Optionally add a comment if you have new info (e.g., "Still occurring as of {date}")

---

## Bug Repro Steps Template

> ⚠️ **CRITICAL:** GitHub Copilot does NOT have access to external links, logs, or Kusto. The bug MUST contain ALL information inline:
> - **Complete stack trace** from ADO test results (not truncated)
> - **Kusto query results** pasted inline (not just the query)
> - **Error messages** in full
> 
> Copilot can ONLY work with information directly in the work item. Links to builds, test runs, or Kusto dashboards are useless to Copilot.

Use **Microsoft.VSTS.TCM.ReproSteps** field with this structure:

```html
<h2>Problem</h2>
<p>{One sentence: what test is failing and what exception/error is occurring}</p>

<h2>Test Details</h2>
<ul>
<li><b>Test Class:</b> {Namespace.TestClass}</li>
<li><b>Test Method:</b> {TestMethodName}</li>
<li><b>Test Category:</b> {SKUv1/SKUv2/Consumption/General/etc.}</li>
<li><b>Test Owner:</b> {ownerAlias} (from [Owner("alias")] attribute)</li>
<li><b>Pipeline:</b> <a href="{pipelineUrl}">Build {buildId}</a></li>
</ul>

<h2>Complete Error Message</h2>
<pre>{FULL error message from ADO test results - do NOT truncate}</pre>

<h2>Complete Stack Trace</h2>
<pre>{COMPLETE stack trace from ADO test results - include ALL frames, do NOT truncate}

Example:
   at Azure.Core.OperationInternal`1.GetResponseFromState(OperationState`1 state)
   at Azure.Core.OperationInternal`1.UpdateStatusAsync(Boolean async, CancellationToken cancellationToken)
   at ResourceProvider.IntegrationTests.IntegrationTestBase.CreateOrUpdateApimUsing20230301Preview(...)
   at ResourceProvider.IntegrationTests.SKUv2.SkuV2Tests.TestCreateApimBasicV2_ThenUpdateCustomDomains()
   ... (include ALL frames)
</pre>

<h2>Kusto Telemetry (Inline Results)</h2>
<p>Query used:</p>
<pre>{The Kusto query that was run}</pre>
<p>Results:</p>
<pre>{PASTE the actual query results here - do NOT just provide the query}

Example:
| PreciseTimeStamp | operationName | exception |
|------------------|---------------|-----------|
| 2026-01-30 10:15:00 | ActivateApiService | NullReferenceException at line 245 |
| 2026-01-30 10:15:01 | UpdateHostnames | CustomHostnameOwnershipCheckFailed |
</pre>

<h2>Root Cause Analysis</h2>
<p>{Your analysis of WHY this is happening - be specific about the code path}</p>
<p>Example: The code assumes TenantId is always populated, but for legacy subscriptions TenantId can be null. Line 245 in TenantValidator.cs calls tenantId.ToString() without null check.</p>

<h2>Affected</h2>
<ul>
<li><b>Test Categories:</b> {SKUv1, SKUv2, etc.}</li>
<li><b>RP Components:</b> {Orchestration, Controller, etc.}</li>
<li><b>Build ID:</b> {buildId}</li>
<li><b>Failure Count:</b> {count} failures in this build</li>
</ul>

<h2>Suggested Fix</h2>
<p>{Specific recommendation for how to fix this}</p>

<h2>Test Source Location</h2>
<p>{Path to test file, e.g., Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/SKUv2/CreateApiServiceTest.cs}</p>
```

### What to Include Inline (REQUIRED)

| Data | Source | Why Required |
|------|--------|--------------|
| **Complete Stack Trace** | ADO test results `stackTrace` field | Copilot needs full call stack to identify the failing code |
| **Full Error Message** | ADO test results `errorMessage` field | Copilot needs exact error to understand the failure |
| **Kusto Results** | Run query via apim-kusto-agent, paste results | Copilot cannot access Kusto - must have data inline |
| **Relevant Code Snippets** | From repo via grep/view | Copilot needs to see the problematic code |

### What NOT to Include (Links are useless)

| ❌ Don't Do This | Why It Fails |
|------------------|--------------|
| "See build logs at {link}" | Copilot cannot click links |
| "Query Kusto with this query" | Copilot cannot run queries |
| "Stack trace available in test run" | Copilot cannot access test runs |

### Finding Test Owner

Look for the `[Owner("alias")]` attribute in the test file:

```bash
# Search for Owner attribute near the test method
grep -B10 "TestMethodName" Test/Bvt/ResourceProvider/**/*.cs | grep -i "Owner"
```

The owner attribute can be at method level or class level. Include the owner alias in the bug for context, even though the bug is assigned to GitHub Copilot.

---

## ADO API Usage

### Search for Existing Items

```
ado-search_workitem:
  searchText: "{error keywords}"
  project: ["One"]
  areaPath: ["One\\AAPT\\Servers and Services\\API Management\\Platform"]
  state: ["Active", "New", "Triaged"]
```

### Create Bug

```
ado-wit_create_work_item:
  project: "One"
  workItemType: "Bug"
  fields:
    - name: "System.Title"
      value: "[RP Integration Test] {Category} - {title}"
    - name: "System.AreaPath"
      value: "One\\AAPT\\Servers and Services\\API Management\\Platform"
    - name: "System.Tags"
      value: "RP-Integration-Test"
    - name: "Microsoft.VSTS.TCM.ReproSteps"
      value: "{repro steps from template}"
      format: "Html"
```

### Link to Parent Feature (AFTER creation)

```
ado-wit_work_items_link:
  project: "One"
  updates:
    - id: {bugId}
      linkToId: 36600929
      type: "parent"
```

### Link to Main Branch (BEFORE assignment)

> ⚠️ **Important:** Link the branch BEFORE assigning to GitHub Copilot, otherwise Copilot will not know where to work.

```
ado-wit_add_artifact_link:
  workItemId: {bugId}
  project: "One"
  linkType: "Branch"
  repositoryId: "141a6ca5-3ad0-4c0f-9992-e52cc9d7a8f9"
  branchName: "main"
```

### Assign to GitHub Copilot (AFTER branch link)

```
ado-wit_update_work_item:
  id: {bugId}
  updates:
    - path: "/fields/System.AssignedTo"
      value: "66dda6c5-07d0-4484-9979-116241219397@72f988bf-86f1-41af-91ab-2d7cd011db47"
```

---

## Bug Creation Order

> ⚠️ **Critical:** Follow this order when creating bugs:
>
> 1. Create the bug (get bug ID)
> 2. Link to parent feature (36600929)
> 3. **Link to main branch** ← Must be before assignment!
> 4. Assign to GitHub Copilot ← Last step
>
> GitHub Copilot needs the branch link to know where to work.

---

## Notes

- **Check ADO FIRST** before investigating - skip investigation if existing bug covers the issue
- One bug per distinct root cause (not per test if same cause)
- Link all bugs to the parent feature (36600929)
- Include enough detail for GitHub Copilot to work on the fix
- Maximum **3 bugs per pipeline run** - prioritize by impact
