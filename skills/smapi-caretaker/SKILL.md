---
name: smapi-caretaker
description: |
  Automated caretaking for SMAPI/Control Plane SLA monitoring. Monitors SLA metrics,
  investigates issues, creates ADO bugs, and posts summary to Teams.
  
  Triggers: "run caretaking", "SMAPI caretaker", "check control plane SLA"
---

# SMAPI/Control Plane Caretaker

Daily caretaking workflow for Control Plane SLA monitoring.

## Quick Start

```
Run SMAPI caretaking for the past 24 hours
```

---

## Workflow

```
1. Query SLA → Get metrics for all 5 components
2. Investigate → For each dip < 99.9%, find errors and root causes
3. File Bugs  → Check ADO, create bugs for new issues (max 3)
4. Report     → Save summary file, post to Teams
```

---

## Step 1: Query SLA Metrics

Query all 5 components using `apim-kusto-agent`. See `references/sla-queries.md`.

| Component | Source |
|-----------|--------|
| SMAPI SKUv1 | `ManagementKpiNormalized` |
| SMAPI SKUv2 | `ManagementKpiNormalized` |
| SMAPI Consumption | `ManagementKpiNormalized` |
| RP SLA | `All('HttpIncomingRequests')` |
| RP Only SLA | `All('HttpIncomingRequests')` |

**If all components show SLA ≥ 99.9% everywhere:** Report healthy status and skip to Step 4.

---

## Step 2: Investigate Issues

For each region/component with SLA < 99.9%:

### 2a. Get Top Errors

Query top errors with stack traces. See `references/investigation-patterns.md`.

### 2b. Identify Root Cause

Analyze stack traces and code to understand WHY errors are happening.
See `references/known-errors.md` for common patterns and investigation guidance.

> ⚠️ **Think holistically:** As you investigate, look for patterns:
> - Same stack trace across regions → likely code bug (1 bug, not N)
> - Different errors with common dependency (DB, Redis) → might be same root cause
> - Same error type but different code paths → separate bugs

### 2c. Skip Non-Actionable Issues

Do NOT file bugs for:
- Customer errors (400-level responses from bad input)
- Transient issues that self-resolved
- External dependencies outside our control (Azure platform issues)
- Issues already mitigated by the time you're investigating

---

## Step 3: Check ADO and Create Bugs

For each distinct root cause you identified:

### 3a. Search ADO

```
ado-search_workitem:
  searchText: "{error type} {class/method}"
  project: ["One"]
  areaPath: ["One\\AAPT\\Servers and Services\\API Management\\SMAPI"]
```

- **If existing bug found:** Note it in summary, move on
- **If no bug found:** Create one (see `references/ado-config.md`)

### 3b. Bug Limit

Create maximum **3 new bugs** per run. Prioritize by SLA impact.

If more than 3 new issues found, note the extras in the summary without creating bugs.

---

## Step 4: Output Summary

### 4a. Save to File

Save to `.caretaker/smapi-caretaker-summary-{YYYY-MM-DD}.md`

### 4b. Post to Teams

Post **identical** content to Teams channel. See `references/summary-template.md`.

```
teams-mcp-server-create-message-in-channel:
  teamId: "48dcdab4-70a0-46b2-a680-aa8e200a9126"
  channelId: "19:44217d8380eb405bbdc70a4171925447@thread.skype"
```

---

## References

| Reference | Purpose |
|-----------|---------|
| `references/sla-queries.md` | KQL queries for SLA metrics |
| `references/investigation-patterns.md` | Diagnostic queries and patterns |
| `references/known-errors.md` | Error categories and investigation guidance |
| `references/ado-config.md` | Bug creation settings and templates |
| `references/summary-template.md` | Output format for file and Teams |

---

## File Locations

- **Summary:** `.caretaker/smapi-caretaker-summary-{date}.md`
- **Temp files:** `.caretaker/temp/` (not repo root)
