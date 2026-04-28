---
name: test-failure-investigator
description: |
  Investigate ADO pipeline test failures for Azure API Management using a structured,
  hypothesis-driven approach. Use when you need to:
  - Analyze test failures from an ADO pipeline run URL
  - Apply systematic root cause analysis (not just log reading)
  - Generate ranked hypotheses and validate with evidence
  - Query Kusto telemetry (APIMTest) for runtime diagnostics
  - Identify recent changes and assess blast radius
  - Get actionable fix strategies with verification plans
  
  **Retry Filtering**: This skill automatically filters out tests that pass on retry.
  Only tests that fail the build AND fail on ALL retries are investigated.
  
  Triggers: "investigate test failure", "analyze pipeline", "why did tests fail",
  "debug test", "root cause", pipeline URLs like dev.azure.com/msazure/One/_build/results
---

# Test Failure Investigator

A Principal Software Engineer approach to investigating test failures: structured, hypothesis-driven, and evidence-based.

## How to Use

### Investigate a pipeline run
```
Investigate test failures in this pipeline: https://dev.azure.com/msazure/One/_build/results?buildId=149441611
```

### Deep-dive a specific failure
```
Why is BasicApiServiceLifecycleTest failing in build 149441611? Do a full root cause analysis.
```

### Assess failure severity
```
Are the failures in build 149441611 blocking? What's the blast radius?
```

---

## Critical: Retry Filtering

**Before investigating any test failure, apply retry filtering to focus only on real blockers.**

### Tests to SKIP (Do NOT investigate)
- Tests that **passed on retry** in the same pipeline run
- Tests that show `outcome: "Passed"` in any retry attempt
- Tests marked as "PassedOnRerun" or similar in ADO test results

### Tests to INVESTIGATE (Focus on these)
- Tests that **failed all retry attempts**
- Tests that contribute to the overall build failure
- Tests with no successful retry within the same build

### How to Identify Retry Status

1. **Get all test results** from the build using `ado-testplan_show_test_results_from_build_id`
2. **Group by test name** - a test may appear multiple times if retried
3. **Check for ANY passing outcome** per test:
   - If any execution of a test passed → SKIP (flaky but passed)
   - If ALL executions failed → INVESTIGATE (consistent failure)
4. **Cross-reference with build status**:
   - Only failed builds need investigation
   - Focus on tests that caused the build to fail

### Filtering Logic

```
For each distinct test name in test results:
  - Collect all outcomes (may have multiple runs due to retries)
  - If ANY outcome == "Passed":
      → SKIP - this test passed on retry
  - If ALL outcomes == "Failed":
      → INVESTIGATE - this test consistently fails
```

### Report Template for Filtered Tests

In the investigation report, include:
```markdown
## Retry Filtering Summary

**Total test executions**: X
**Distinct tests**: Y
**Passed on retry (skipped)**: Z
**Consistently failing (investigating)**: W

### Skipped (Passed on Retry)
| Test Name | Attempts | Passed On |
|-----------|----------|-----------|
| TestA | 3 | Retry 2 |
| TestB | 2 | Retry 1 |

### Investigating (Failed All Retries)
| Test Name | Attempts | All Failed |
|-----------|----------|------------|
| TestC | 3 | ✓ |
| TestD | 2 | ✓ |
```

---

## Investigation Framework

Follow this structured, hypothesis-driven flow for each distinct failure. See `references/investigation-methodology.md` for detailed guidance.

### Phase 0: Retry Filtering (MANDATORY FIRST STEP)

**Goal**: Filter out tests that passed on retry to focus only on blocking failures.

1. **Get all test results** from the pipeline run
2. **Group test results by test name** (tests may run multiple times due to retries)
3. **Apply filtering logic**:
   - If any run of a test passed → **SKIP** (flaky but not blocking)
   - If all runs of a test failed → **INVESTIGATE** (consistent blocker)
4. **Report filtered summary** showing skipped vs investigated tests

**Only proceed to Phase 1 for tests that failed ALL retry attempts.**

### Phase 1: Failure Understanding

**Goal**: Clearly understand what failed and why it matters.

1. **Restate the failure** in your own words
2. **Identify assertion vs reality**: What did the test expect? What actually happened?
3. **Classify the failure type**:

| Classification | Indicators | Typical Causes |
|----------------|------------|----------------|
| Logic Bug | Consistent failure, wrong output | Code defect in SUT |
| Flaky Test | Intermittent, passes on retry | Race conditions, timing |
| Environment/Config | Works locally, fails in CI | Missing config, permissions |
| Timing Issue | Timeout, async failures | Slow backends, no retry |
| Dependency Failure | External service errors | Backend unavailable |
| Data Setup | Missing test data | Setup not idempotent |
| Regression | Previously passing | Recent code change |

### Phase 2: Context & Scope Analysis

**Goal**: Understand the change landscape and assess risk.

1. **Recent changes** (last 7 days in affected areas):
   ```bash
   git log --oneline --since="7 days ago" -- <test-path>
   git log --oneline --since="7 days ago" -- <source-path>
   ```

2. **Isolation check**: Is this the only failing test or part of a pattern?
   - Same test class failing? → Shared setup issue
   - Same component failing? → Component regression
   - Random tests failing? → Infrastructure issue

3. **Blast radius assessment**:
   - Does this block deployments?
   - What functionality is at risk if this is a real defect?
   - Who are the downstream consumers?

### Phase 3: Hypothesis Generation

**Goal**: Generate ranked hypotheses with clear validation criteria.

Structure each hypothesis as:

```markdown
### Hypothesis [N]: [Short description]

**Likelihood**: High / Medium / Low
**Assumption**: [What must be true for this to be the cause]
**Evidence For**: [What we've seen that supports this]
**Evidence Against**: [What we've seen that contradicts this]
**Validation**: [Concrete step to prove/disprove]
```

**Ranking criteria**:
1. Recent changes in the failure area (highest signal)
2. Known transient patterns (see `references/transient-errors.md`)
3. Similar historical failures
4. Environmental factors

### Phase 4: Investigation Plan

**Goal**: Define fastest-feedback-first validation steps.

Order investigations by:
1. **Immediate** (seconds): Check transient patterns, recent commits
2. **Quick** (minutes): Kusto queries, log analysis
3. **Medium** (10+ min): Source code deep-dive, reproduction
4. **Slow** (hours): Local debugging, reduced test case

```markdown
## Investigation Plan

| Step | Action | Expected Outcome | Time |
|------|--------|------------------|------|
| 1 | Check transient patterns | Rule out known flakes | 30s |
| 2 | Query Kusto for service errors | Find runtime exceptions | 2m |
| 3 | Review test source code | Understand assertions | 5m |
| 4 | Check recent commits | Identify potential culprit | 3m |
| 5 | ... | ... | ... |
```

### Phase 5: Root Cause Identification

**Goal**: Converge on the most likely root cause with evidence.

1. Execute investigation plan
2. Update hypotheses with findings
3. Document why alternatives were ruled out
4. State the root cause with confidence level

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

### Phase 6: Fix Strategy

**Goal**: Propose minimal, correct fix.

Consider:
- **Test fix**: Is the test wrong or too brittle?
- **Code fix**: Is there a defect in the system under test?
- **Both**: Does the test need hardening AND code needs fixing?

```markdown
## Fix Strategy

**Recommended Fix**: [What to change]
**Change Type**: Test / Code / Configuration / Both

**Implementation**:
1. [Step 1]
2. [Step 2]

**Risks**:
- [Risk and mitigation]

**Alternatives Considered**:
- [Alternative 1]: Rejected because [reason]
```

### Phase 7: Verification & Prevention

**Goal**: Validate fix and prevent recurrence.

```markdown
## Verification Plan

1. [ ] Run failing test locally with fix
2. [ ] Run full test suite for affected component
3. [ ] Verify in CI pipeline
4. [ ] Monitor next N pipeline runs

## Prevention Recommendations

- [ ] Add assertion for [edge case]
- [ ] Improve error message for [scenario]
- [ ] Add retry logic for [transient condition]
- [ ] Create alert for [early warning signal]
```

---

## Data Gathering Tools

### Step 1: Parse Pipeline URL and Get Build Status

Extract buildId from URL patterns:
- `dev.azure.com/msazure/One/_build/results?buildId={buildId}`
- `msazure.visualstudio.com/One/_build/results?buildId={buildId}`

```
ado-pipelines_get_build_status(project="One", buildId=<extracted>)
```

### Step 2: Get Test Results

```
ado-testplan_show_test_results_from_build_id(project="One", buildid=<buildId>)
```

### Step 2.5: Apply Retry Filtering (CRITICAL)

After getting test results, apply retry filtering before investigating:

1. **Group results by test name** (fully qualified name like `Namespace.Class.Method`)
2. **For each distinct test**:
   - Count total executions (may be >1 due to retries)
   - Check if ANY execution has `outcome: "Passed"`
   - If yes → Add to "Skipped (Passed on Retry)" list
   - If no (all failed) → Add to "Investigate" list
3. **Only investigate tests in the "Investigate" list**

**Important**: Do NOT spend time investigating tests that passed on retry. These are flaky but did not block the build.

### Step 2.6: Extract Test Names from Build Logs (When API is Insufficient)

The ADO test results API may return only `testCaseReferenceId` without test names. In this case, extract test names from build logs:

1. **Get build logs**: `ado-pipelines_get_build_log(project="One", buildId=<buildId>)`
2. **Identify test execution log IDs** from the log list
3. **Retrieve specific logs**: `ado-pipelines_get_build_log_by_id(project="One", buildId=<buildId>, logId=<logId>)`
4. **Parse for test names** using patterns:
   - `Failed   TestNamespace.TestClass.TestMethod` (VSTest output)
   - `Error Message:` followed by test context
   - Stack traces containing `at TestNamespace.TestClass.TestMethod`

**Note**: Build logs are split across multiple log IDs. You may need to check several log IDs (e.g., 367, 390, 412) to find test execution output.

### Step 3: Gather Evidence

| Data Source | Tool | Purpose |
|-------------|------|---------|
| Test logs | `ado-pipelines_get_build_log` | Error messages, stack traces |
| Test source | `grep/glob` in `Test/Bvt/` | Understand assertions |
| Runtime telemetry | Kusto MCP (APIMTest) | Service-side errors |
| Recent changes | `git log` | Potential culprits |
| Transient patterns | `references/transient-errors.md` | Quick classification |

---

## Output Format

```markdown
# Test Failure Investigation Report

**Pipeline**: [URL]
**Build ID**: [buildId]  
**Status**: [Failed/PartiallySucceeded]
**Investigated**: [timestamp]
**Investigator Approach**: Hypothesis-Driven Root Cause Analysis

---

## Retry Filtering Summary

**Total test executions**: X
**Distinct tests**: Y
**Passed on retry (skipped)**: Z
**Consistently failing (investigating)**: W

### Skipped - Passed on Retry (Not Investigated)
| Test Name | Retry Attempts | Passed On |
|-----------|----------------|-----------|
| [TestName] | N | Retry M |

### Consistently Failing (Investigated Below)
| Test Name | Retry Attempts | Status |
|-----------|----------------|--------|
| [TestName] | N | All Failed |

---

## Executive Summary

- **Total failed tests**: X
- **Distinct failures**: Y  
- **Classification**: [Regression / Flaky / Environment / etc.]
- **Blast Radius**: [Low / Medium / High]
- **Recommended Action**: [Retry / Fix Required / Block Deployment]

---

## Failure: [TestClassName.TestMethodName]

### 1. Failure Understanding

**What the test asserts**: [Expected behavior]
**What actually happened**: [Actual behavior]
**Classification**: [Logic Bug / Flaky / Environment / Timing / Dependency / Data / Regression]

### 2. Context & Scope

**Recent Changes**:
| Commit | Author | Date | Message |
|--------|--------|------|---------|
| abc123 | @user | 2026-01-15 | [message] |

**Isolation**: [Isolated / Part of pattern]
**Blast Radius**: [Assessment]

### 3. Hypotheses

#### Hypothesis 1: [Description]
- **Likelihood**: High
- **Validation**: [How to prove/disprove]
- **Status**: ✅ Confirmed / ❌ Ruled Out / 🔍 Investigating

#### Hypothesis 2: [Description]
- **Likelihood**: Medium
- **Validation**: [How to prove/disprove]  
- **Status**: ❌ Ruled Out - [reason]

### 4. Root Cause

**Cause**: [Clear statement]
**Confidence**: [High/Medium/Low]
**Evidence**:
- [Evidence 1]
- [Evidence 2]

### 5. Fix Strategy

**Recommended Fix**: [Description]
**Change Type**: [Test / Code / Config]

| Action | Test Owner | Recent Commit Owner | Priority |
|--------|------------|---------------------|----------|
| [Action description] | [From `[Owner("...")]` in test file] | [From recent commit history if applicable] | [High/Medium/Low] |

**Implementation Steps**:
1. [Step 1]
2. [Step 2]

### 6. Verification & Prevention

**Verification**:
- [ ] Local test run
- [ ] CI validation

**Prevention**:
- [ ] [Recommendation 1]
- [ ] [Recommendation 2]

---

## Next Steps

1. [Immediate action]
2. [Follow-up action]
3. [Long-term improvement]
```

---

## Test Source Locations

| Test Type | Location |
|-----------|----------|
| Gateway/Proxy BVT | `Test/Bvt/Gateway/Proxy.Tests.Bvt/` |
| ResourceProvider Integration | `Test/Bvt/ResourceProvider/ResourceProvider.IntegrationTests/` |
| Management E2E | `Management/Test/Management.E2E.Tests/` |
| Data E2E | `Management/Test/Data.E2E.Tests/` |

## Finding Test Owners

Test files use the `[Owner("alias")]` MSTest attribute to declare ownership:

```csharp
[TestClass]
public class MyTests
{
    [Owner("nimak")]
    [TestMethod]
    public void MyTest_ShouldPass()
    {
        // ...
    }
}
```

**To find the owner of a failing test**:
```bash
grep -B5 "TestMethodName" <test-file-path> | grep -i "Owner"
```

**Priority**: Test-level `[Owner]` attribute takes precedence over area-based assignment from the Owner Matrix.

## Report Export

Investigation reports can be exported to markdown files for documentation or sharing:

```
Export the investigation report to <filename>.md
```

The report includes:
- Retry filtering summary
- Failure details with root cause analysis  
- Test owner and recent commit owner attribution
- Fix strategy with verification plan

**Naming convention**: Use buildId for filename (e.g., `149441611.md`)

## References

- **Investigation methodology**: See `references/investigation-methodology.md`
- **ADO URL patterns**: See `references/ado-patterns.md`
- **Kusto queries**: See `references/kusto-queries.md`
- **Transient errors**: See `references/transient-errors.md`
- **Owner assignment**: See `references/owner-assignment.md`

## MCP Tools Used

| Tool | Purpose |
|------|---------|
| `ado-pipelines_get_build_status` | Get build details and status |
| `ado-pipelines_get_build_log` | Get build/test logs |
| `ado-testplan_show_test_results_from_build_id` | Get test results |
| Kusto MCP (APIMTest) | Query telemetry for diagnostics |
| grep/glob | Find test source code |
| git | Analyze recent changes |
