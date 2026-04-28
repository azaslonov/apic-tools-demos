# ADO Configuration

Configuration for Azure DevOps work item management.

---

## Project Configuration

| Setting | Value |
|---------|-------|
| **Organization** | msazure |
| **Project** | One |
| **Area Path** | `One\AAPT\Servers and Services\API Management\SMAPI` |
| **Parent Feature** | 31976785 |

---

## Work Item Settings

### Bug Creation

| Field | Value |
|-------|-------|
| **Work Item Type** | Bug |
| **Tags** | `SLA` |
| **Assigned To** | GitHub Copilot |
| **Assigned To ID** | `66dda6c5-07d0-4484-9979-116241219397@72f988bf-86f1-41af-91ab-2d7cd011db47` |

### Title Format

```
[SMAPI Caretaker Agent] {Component} - {Specific Bug Description}
```

> ⚠️ Title should describe the **actual bug**, not a generic SLA dip. Region is NOT in the title unless bug is region-specific.

Examples:
- ✅ `[SMAPI Caretaker Agent] SKUv2 - NullReferenceException in SubscriptionController.GetAsync`
- ✅ `[SMAPI Caretaker Agent] Consumption - Redis connection timeout missing retry logic`
- ✅ `[SMAPI Caretaker Agent] RP - ArgumentException when parsing malformed subscription ID`
- ❌ `[SMAPI Caretaker Agent] SKUv2 SLA dip in eastus` (too generic)

---

## Search Criteria

> ⚠️ **IMPORTANT:** Search ADO BEFORE deep investigation to avoid wasting time on known issues.

Before investigating or creating a bug, search for existing items:

```
Project: One
Area Path: One\AAPT\Servers and Services\API Management\SMAPI
Tags: SLA
State: NOT IN (Closed, Resolved, Removed)
```

**Also search by keywords:**
- Exception type (e.g., "NullReferenceException", "TimeoutException")
- Error message keywords
- Class/method names (e.g., "SubscriptionController")

If a matching item is found:
1. **Skip deep investigation** - no need to re-investigate known issues
2. Note the existing item in the summary with bug ID and URL
3. Do NOT create a duplicate bug
4. Optionally add a comment if you have new info (e.g., "Still occurring as of {date}")

---

## Bug Repro Steps Template

> ⚠️ **CRITICAL:** GitHub Copilot does NOT have access to logs. The bug must contain enough detail for Copilot to understand and fix the issue. Investigate further if more information is needed to create the bug.

Use **Repro Steps** field (not just Description) with this structure:

```
## Problem
{One sentence: what exception/error is occurring}

## Stack Trace
{Full or partial stack trace showing the error}
Example:
System.NullReferenceException: Object reference not set to an instance of an object.
   at Microsoft.Azure.ApiManagement.Management.Controllers.SubscriptionController.GetAsync()
   at Microsoft.Azure.ApiManagement.Management.Controllers.SubscriptionController.<>c__DisplayClass12_0.<Get>b__0()

## Root Cause Analysis
{Your analysis of WHY this is happening - be specific about the code path}
Example:
The code assumes TenantId is always populated, but for legacy subscriptions TenantId can be null.
Line 245 in SubscriptionController.cs calls tenantId.ToString() without null check.

## Affected
- Components: {SKUv1, SKUv2, etc.}
- Regions: {list of regions where this error appeared}
- Time Window: {when this occurred}
- Error Count: {approximate count}

## Kusto Query to Verify
{Paste the query that shows this error - user can run this to verify}

## Suggested Fix
{Specific recommendation for how to fix this}
```

---

## ADO API Usage

### Search for Existing Items

```
ado-search_workitem:
  searchText: "{error keywords}"
  project: ["One"]
  areaPath: ["One\\AAPT\\Servers and Services\\API Management\\SMAPI"]
  state: ["Active", "New", "Triaged"]
```

### Create Bug

```
ado-wit_create_work_item:
  project: "One"
  workItemType: "Bug"
  fields:
    - name: "System.Title"
      value: "[SMAPI Caretaker Agent] {title}"
    - name: "System.AreaPath"
      value: "One\\AAPT\\Servers and Services\\API Management\\SMAPI"
    - name: "System.Tags"
      value: "SLA"
    - name: "System.Description"
      value: "{description from template}"
      format: "Html"
```

### Link to Main Branch (BEFORE assignment)

> ⚠️ **Important:** Link the branch BEFORE assigning to GitHub Copilot, otherwise Copilot will not know where to work.

```
ado-wit_add_artifact_link:
  workItemId: {bugId}
  project: "One"
  linkType: "Branch"
  repositoryId: "{repo-id}"
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

### Link to Parent Feature

```
ado-wit_work_items_link:
  project: "One"
  updates:
    - id: {bugId}
      linkToId: 31976785
      type: "parent"
```

---

## Bug Creation Order

> ⚠️ **Critical:** Follow this order when creating bugs:
>
> 1. Create the bug (get bug ID)
> 2. Link to parent feature (31976785)
> 3. **Link to main branch** ← Must be before assignment!
> 4. Assign to GitHub Copilot ← Last step
>
> GitHub Copilot needs the branch link to know where to work.

---

## Notes

- **Check ADO FIRST** before investigating - skip investigation if existing bug covers the issue
- One bug per distinct root cause (not per region if same cause)
- Link all bugs to the parent feature (31976785)
- Include enough detail for GitHub Copilot to work on the fix
