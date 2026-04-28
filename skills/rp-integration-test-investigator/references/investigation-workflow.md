# Investigation Workflow

Detailed step-by-step methodology for investigating RP integration test failures.

---

## Phase 0: Retry Filtering (MANDATORY FIRST STEP)

**Goal**: Filter out tests that passed on retry to focus only on blocking failures.

### Steps

1. **Get all test results** from the pipeline run
   ```
   ado-testplan_show_test_results_from_build_id:
     project: "One"
     buildid: {buildId}
   ```

2. **Group test results by test name** (tests may run multiple times due to retries)
   - Use fully qualified name: `Namespace.TestClass.TestMethod`

3. **Apply filtering logic**:
   ```
   For each distinct test name:
     outcomes = [all outcomes for this test]
     if "Passed" in outcomes:
       → SKIP (flaky but not blocking)
     else:
       → INVESTIGATE (consistent blocker)
   ```

4. **Report filtered summary**:
   ```markdown
   ## Retry Filtering Summary

   **Total test executions**: X
   **Distinct tests**: Y
   **Passed on retry (skipped)**: Z
   **Consistently failing (investigating)**: W

   ### Skipped - Passed on Retry
   | Test Name | Attempts | Passed On |
   |-----------|----------|-----------|
   | TestA | 3 | Retry 2 |

   ### Consistently Failing (Investigating)
   | Test Name | Attempts | Status |
   |-----------|----------|--------|
   | TestC | 3 | All Failed |
   ```

**Only proceed to Phase 1 for tests that failed ALL retry attempts.**

---

## Phase 1: Failure Understanding

**Goal**: Clearly understand what failed and why it matters.

### Steps

1. **Restate the failure** in your own words
   - What test failed?
   - What was the error message?
   - What was the stack trace?

2. **Identify assertion vs reality**:
   - What did the test expect?
   - What actually happened?

3. **Classify the failure type**:

| Classification | Indicators | Typical Causes |
|----------------|------------|----------------|
| Logic Bug | Consistent failure, wrong output | Code defect in RP |
| Flaky Test | Intermittent, passes on retry | Race conditions, timing |
| Environment/Config | Works locally, fails in CI | Missing config, permissions |
| Timing Issue | Timeout, async failures | Slow backends, no retry |
| Dependency Failure | External service errors | Backend unavailable |
| Data Setup | Missing test data | Setup not idempotent |
| Regression | Previously passing | Recent code change |
| Orchestration Failure | TaskHub errors | Orchestration stuck/failed |
| Backup/Restore Failure | BackupApiService errors | SQL timeout, storage issues, export failures |

### Finding Test Source

```bash
# Find test file
glob "**/{TestClassName}.cs" --path "Test/Bvt/ResourceProvider"

# Read test method
grep -A 50 "public.*{TestMethodName}" {test-file}
```

---

## Phase 1.5: Extract Service Name from Test Logs (CRITICAL)

**Goal**: Extract the APIM service name created by the test to use in Kusto queries.

> ⚠️ **CRITICAL**: You MUST extract the service name from test logs before running Kusto queries. Without the correct service name, Kusto queries will return no results.

### Step 1: Get Build Logs

```
ado-pipelines_get_build_log:
  project: "One"
  buildId: {buildId}
```

Identify log IDs for test execution (typically named "Run tests" or similar).

### Step 2: Retrieve Test Execution Logs

```
ado-pipelines_get_build_log_by_id:
  project: "One"
  buildId: {buildId}
  logId: {logId}
```

### Step 3: Search for Service Name Patterns

Look for these log patterns that contain the service name:

| Log Pattern | Example | Service Name |
|-------------|---------|--------------|
| `ServiceCreateOrUpdateStarting, message: Service {name}` | `ServiceCreateOrUpdateStarting, message: Service Int-Developer-697c2ff607088f073c781941` | `Int-Developer-697c2ff607088f073c781941` |
| `ServiceCreated, message: Service {name}` | `ServiceCreated, message: Service Int-Premium-abc123def456` | `Int-Premium-abc123def456` |
| `Creating service {name}` | `Creating service Int-Basic-xyz789` | `Int-Basic-xyz789` |
| `serviceName: {name}` | `serviceName: Int-Consumption-test123` | `Int-Consumption-test123` |
| `DeploymentName: {name}` | `DeploymentName: Int-Developer-697c2ff607088f073c781941` | `Int-Developer-697c2ff607088f073c781941` |

### Service Name Patterns

RP integration test services typically follow these naming patterns:

| Pattern | Description | Example |
|---------|-------------|---------|
| `Int-{SKU}-{guid}` | Standard integration test | `Int-Developer-697c2ff607088f073c781941` |
| `Int-{SKU}-{testname}` | Named test service | `Int-Premium-ScaleTest` |
| `apim-{random}` | Alternative pattern | `apim-test-abc123` |
| `test-{random}` | Test prefix pattern | `test-rp-xyz789` |

### Step 4: Record Service Name for Kusto Queries

Once extracted, use the service name in ALL Kusto queries:

```kql
// Replace {serviceName} with the extracted value
let svcName = "Int-Developer-697c2ff607088f073c781941";
All('Orchestration')
| where PreciseTimeStamp > ago(2h)
| where serviceName == svcName
| where Level < 3
| project PreciseTimeStamp, operationName, exception
| take 50
```

### Step 5: Extract Timestamp

Also extract the approximate timestamp when the test ran:

```
Look for: "Test started at {timestamp}" or use the log entry timestamp
```

This helps narrow down Kusto query time ranges.

### Example Extraction

**From test log:**
```
2026-01-30T10:15:23.456Z INFO ServiceCreateOrUpdateStarting, message: Service Int-Developer-697c2ff607088f073c781941 in region westus2
2026-01-30T10:15:24.123Z INFO Waiting for service activation...
2026-01-30T10:18:45.789Z ERROR Service activation failed with error: NullReferenceException
```

**Extracted values:**
- **Service Name**: `Int-Developer-697c2ff607088f073c781941`
- **Region**: `westus2`
- **Start Time**: `2026-01-30T10:15:23Z`
- **Failure Time**: `2026-01-30T10:18:45Z`

**Use in Kusto:**
```kql
let svcName = "Int-Developer-697c2ff607088f073c781941";
let startTime = datetime(2026-01-30T10:15:00Z);
let endTime = datetime(2026-01-30T10:20:00Z);
All('Orchestration')
| where PreciseTimeStamp between (startTime .. endTime)
| where serviceName == svcName
| where Level < 3
| project PreciseTimeStamp, operationName, exception, message
| order by PreciseTimeStamp asc
```

### Multiple Services in One Test

Some tests create multiple services. Extract ALL service names:

```
Service 1: Int-Developer-697c2ff607088f073c781941
Service 2: Int-Developer-abc123def456
```

Query each service separately or use `in` operator:

```kql
let serviceNames = dynamic(["Int-Developer-697c2ff607088f073c781941", "Int-Developer-abc123def456"]);
All('Orchestration')
| where PreciseTimeStamp > ago(2h)
| where serviceName in (serviceNames)
| where Level < 3
```

---

## Phase 2: Context & Scope Analysis

**Goal**: Understand the change landscape and assess risk.

### Steps

1. **Check recent changes** (last 7 days in affected areas):
   ```bash
   # Changes to test
   git log --oneline --since="7 days ago" -- Test/Bvt/ResourceProvider/

   # Changes to RP source
   git log --oneline --since="7 days ago" -- ResourceProvider/
   ```

2. **Isolation check**: Is this the only failing test or part of a pattern?
   - Same test class failing? → Shared setup issue
   - Same category failing (all SKUv2)? → Category-specific regression
   - Random tests failing? → Infrastructure issue
   - Same orchestration failing? → Orchestration bug

3. **Blast radius assessment**:
   - Does this block deployments?
   - What functionality is at risk if this is a real defect?
   - How many test categories are affected?

---

## Phase 3: Transient Detection

**Goal**: Identify known transient patterns to avoid filing unnecessary bugs.

### Check Against Known Patterns

See `known-errors.md` for full list. Key patterns:

| Pattern | Action |
|---------|--------|
| "There is ongoing RollingUpgrade" | SKIP - transient |
| "File lock" errors | SKIP - transient |
| 429 Too Many Requests | SKIP - throttling |
| 503 Service Unavailable | SKIP - transient |
| Consistent NullReferenceException | INVESTIGATE - real bug |
| Assert failure with specific values | INVESTIGATE - real bug |

### Decision

- **If transient**: Note in summary, do NOT file bug
- **If persistent**: Continue to Phase 4

---

## Phase 4: Hypothesis Generation

**Goal**: Generate ranked hypotheses with clear validation criteria.

### Structure Each Hypothesis

```markdown
### Hypothesis [N]: [Short description]

**Likelihood**: High / Medium / Low
**Assumption**: [What must be true for this to be the cause]
**Evidence For**: [What we've seen that supports this]
**Evidence Against**: [What we've seen that contradicts this]
**Validation**: [Concrete step to prove/disprove]
```

### Ranking Criteria (prioritize by)

1. Recent changes in the failure area (highest signal)
2. Known transient patterns
3. Similar historical failures (search ADO)
4. Environmental factors

### Example

```markdown
### Hypothesis 1: Recent change to TenantValidator broke null handling

**Likelihood**: High
**Assumption**: The recent commit abc123 changed TenantValidator logic
**Evidence For**: Stack trace shows NullReferenceException in TenantValidator.Validate()
**Evidence Against**: None yet
**Validation**: Check if commit abc123 touched TenantValidator.cs
```

---

## Phase 5: Evidence Gathering

**Goal**: Collect evidence to validate/invalidate hypotheses.

### Data Sources

| Source | Tool | What to Look For |
|--------|------|------------------|
| Test source | `grep/glob` | Assertions, setup, mocks |
| RP source | `grep/glob` | Implementation being tested |
| Kusto | `apim-kusto-agent` | Orchestration errors, service telemetry |
| Build logs | `ado-pipelines_get_build_log` | Full error context, timing |
| Git history | `git log`, `git show` | Recent changes, authors |
| ADO | `ado-search_workitem` | Similar past bugs |

### Using apim-kusto-agent for Automated Telemetry Analysis

> ⚠️ **CRITICAL**: The apim-kusto-agent is the primary tool for Kusto-based root cause analysis. It can independently execute queries and provide analysis.

**Invoke the agent with comprehensive context:**

```
task(
  agent_type: "apim-kusto-agent",
  description: "Root cause analysis for {TestName}",
  prompt: "Investigate RP integration test failure in APIMTest database.

**Context:**
- Service Name: {serviceName from Phase 1.5}
- Time Window: {startTime} to {endTime}
- SKU Type: {SKUv1/SKUv2/Consumption}
- Test Category: {testCategory}
- Failure Type: {activation/backup/restore/scaling/etc.}
- Error from test logs: {errorMessage}
- Orchestration Name (if known): {e.g., ActivateApiService}

**Investigation Tasks:**
1. Query All('Orchestration') for errors related to this service (Level < 3)
2. Check for failed orchestration events with exceptions
3. Look for specific error patterns: {errorPattern}
4. Identify timeout or stuck orchestration instances
5. Check ResourceProvider and HttpIncomingRequests for related errors

**Analysis Required:**
- Root cause hypothesis with evidence
- Classification: transient vs persistent failure
- Confidence level: High/Medium/Low
- Kusto queries used for reproduction"
)
```

**The apim-kusto-agent will:**
1. Execute appropriate Kusto queries against APIMTest
2. Analyze the telemetry data for error patterns
3. Identify the root cause with supporting evidence
4. Provide queries that can be re-run for verification
5. Classify whether the failure is transient or persistent

### Kusto Query Reference

See `kusto-queries.md` for RP-specific query templates. Key tables:
- `All('Orchestration')` - Orchestration execution logs
- `All('HttpIncomingRequests')` - HTTP request telemetry
- `All('ResourceProvider')` - RP operation logs
- `All('Mapi')` - Management API logs
- `All('CfgSvcRequestTrace')` - Configuration service traces

---

## Phase 6: Root Cause Identification

**Goal**: Converge on the most likely root cause with evidence.

### Steps

1. Execute investigation plan from Phase 4
2. Update hypotheses with findings
3. Document why alternatives were ruled out
4. State root cause with confidence level

### Template

```markdown
## Root Cause

**Identified Cause**: [Clear statement]
**Confidence**: High / Medium / Low
**Evidence**: 
- [Evidence point 1]
- [Evidence point 2]

**Ruled Out**:
- Hypothesis 2: Disproved because [reason]
- Hypothesis 3: Disproved because [reason]
```

---

## Phase 7: Bug Filing Decision

**Goal**: Decide whether to file a bug and prepare content.

### File Bug If

- ✅ Consistent failure (not transient)
- ✅ Clear root cause identified
- ✅ Actionable fix exists
- ✅ No existing bug covers this issue

### Do NOT File Bug If

- ❌ Transient infrastructure issue
- ❌ Customer/external dependency error
- ❌ Existing bug already tracks this
- ❌ Issue self-resolved by time of investigation
- ❌ Bug limit (3) already reached for this run

### Bug Content

See `ado-config.md` for templates. Key elements:
- Clear title with test category
- Stack trace
- Root cause analysis
- Suggested fix
- Kusto query to verify

---

## Phase 8: Summary Generation

**Goal**: Document findings for the summary report.

### Per-Issue Summary

```markdown
## Issue: {TestClassName.TestMethodName}

**Category**: {SKUv1/SKUv2/General/etc.}
**Classification**: {Logic Bug/Flaky/Environment/etc.}
**Root Cause**: {One sentence summary}

**Evidence**:
- {Key evidence point 1}
- {Key evidence point 2}

**Action**:
- ✅ Bug #12345 created
- OR: ⏭️ Skipped - {reason}
```

See `summary-template.md` for full report format.
