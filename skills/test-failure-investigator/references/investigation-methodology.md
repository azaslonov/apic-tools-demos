# Investigation Methodology

A Principal Software Engineer's guide to structured, hypothesis-driven test failure investigation.

## Philosophy

> "Don't just read logs. Form hypotheses, gather evidence, and converge on root cause."

The difference between junior and senior debugging:
- **Junior**: Read error message → Google → Try random fixes
- **Senior**: Understand context → Form hypotheses → Validate systematically → Fix correctly

## The Eight Phases (Including Retry Filtering)

### Phase 0: Retry Filtering (MANDATORY FIRST STEP)

**Time Budget**: 2-3 minutes

**Goal**: Filter out tests that passed on retry to focus investigation time on real blockers.

Before investigating ANY test failure:

1. **Retrieve all test results** from the pipeline run
2. **Group by test name** - a test may appear multiple times if retried
3. **Identify tests that passed on retry**:
   - If ANY execution of a test passed → **SKIP** this test
   - If ALL executions failed → **INVESTIGATE** this test
4. **Document the filtering summary** in the report

#### Why This Matters
- Tests that pass on retry are **flaky but not blocking** - they didn't cause the build to fail
- Investigating flaky tests that eventually passed wastes time
- Focus on tests that **consistently fail** and **actually block the build**

#### Retry Filtering Decision Matrix

| Scenario | Attempts | Any Passed? | Action |
|----------|----------|-------------|--------|
| Test passed first time | 1 | Yes | Not a failure |
| Test failed, passed on retry 1 | 2 | Yes | **SKIP** |
| Test failed, passed on retry 2 | 3 | Yes | **SKIP** |
| Test failed all 2 retries | 3 | No | **INVESTIGATE** |
| Test failed, no retries configured | 1 | No | **INVESTIGATE** |

#### Output for Phase 0

```markdown
## Retry Filtering Summary

**Total test executions**: 47
**Distinct tests**: 32
**Passed on retry (skipped)**: 8
**Consistently failing (investigating)**: 5

### Skipped - Passed on Retry
| Test | Attempts | Passed On |
|------|----------|-----------|
| TestA | 3 | Attempt 2 |
| TestB | 2 | Attempt 2 |

### Investigating - Failed All Attempts
| Test | Attempts | Status |
|------|----------|--------|
| TestC | 3 | All Failed |
| TestD | 2 | All Failed |
```

**Proceed to Phase 1 ONLY for tests in the "Investigating" list.**

### Phase 1: Failure Understanding

**Time Budget**: 5-10 minutes

Before diving into logs, answer these questions:

#### 1.1 Restate the Failure
Don't just copy the error message. Explain what went wrong in plain English.

❌ Bad: "AssertionError: expected 200 but got 404"
✅ Good: "The API returned 404 Not Found when the test expected a successful resource creation"

#### 1.2 Assertion vs Reality

| Question | Answer Template |
|----------|-----------------|
| What is the test trying to verify? | "This test verifies that [functionality] works correctly" |
| What was the expected outcome? | "Expected: [specific expected state]" |
| What actually happened? | "Actual: [specific actual state]" |
| What is the delta? | "The difference is: [gap analysis]" |

#### 1.3 Failure Classification

| Type | Key Indicators | Investigation Focus |
|------|----------------|---------------------|
| **Logic Bug** | Consistent failure, deterministic wrong output | Source code of SUT |
| **Product Bug** | Test validates product behavior, behavior regressed | Recent product code changes |
| **Flaky Test** | Intermittent, different results on retry | Race conditions, ordering |
| **Environment** | Works locally, fails in CI | Config, permissions, network |
| **Timing** | Timeouts, async failures | Backend latency, no retry |
| **Dependency** | External service errors in logs | Backend availability |
| **Data Setup** | Missing data, constraint violations | Test fixture, idempotency |
| **Regression** | Was passing, now failing | Recent commits |

> **Product Bug vs Test Bug**: When Kusto telemetry shows the actual product behavior doesn't match expectations (e.g., 2 cache refreshes when expecting 1), this is a **product bug**, not a test infrastructure issue. Verify by running the exact test query against Kusto - if the data shows wrong behavior, the product is at fault.

### Phase 2: Context & Scope Analysis

**Time Budget**: 5-10 minutes

#### 2.1 Change Analysis

```bash
# Recent changes to test
git log --oneline --since="7 days ago" -- <test-file>

# Recent changes to code under test
git log --oneline --since="7 days ago" -- <source-file>

# Recent changes to shared infrastructure
git log --oneline --since="7 days ago" -- Test/Bvt/Infra/

# Who changed what?
git log --format="%h %an %s" --since="7 days ago" -- <path>
```

#### 2.2 Isolation Analysis

| Pattern | Meaning | Action |
|---------|---------|--------|
| Only this test fails | Isolated issue | Focus on this test |
| Multiple tests in same class fail | Shared setup issue | Check `[TestInitialize]` |
| All tests for component fail | Component regression | Check component changes |
| Random tests across suites fail | Infrastructure issue | Check CI environment |
| Tests fail only in specific env | Environment issue | Compare env configs |

#### 2.3 Blast Radius Assessment

Questions to answer:
1. **Deployment Impact**: Does this block the release pipeline?
2. **Functionality Risk**: What user scenarios break if this is real?
3. **Data Risk**: Could this cause data corruption in production?
4. **Security Risk**: Is there a security implication?

Severity Matrix:
| Blast Radius | Criteria | Response |
|--------------|----------|----------|
| **Critical** | Blocks deployment, security risk | Immediate fix required |
| **High** | Core functionality at risk | Fix before next release |
| **Medium** | Non-critical path affected | Fix within sprint |
| **Low** | Edge case, workaround exists | Backlog |

### Phase 3: Hypothesis Generation

**Time Budget**: 5-10 minutes

#### 3.1 Hypothesis Template

```markdown
### Hypothesis [N]: [Short Title]

**Likelihood**: High / Medium / Low

**Description**: 
[1-2 sentence explanation of what might have caused the failure]

**Assumptions**:
- [What must be true for this to be correct]

**Evidence For**:
- [What we've observed that supports this]

**Evidence Against**:
- [What we've observed that contradicts this]

**Validation Steps**:
1. [Concrete step to prove/disprove]
2. [Expected outcome if hypothesis is correct]
```

#### 3.2 Hypothesis Ranking

Rank by likelihood using these signals:

| Signal | Weight | Example |
|--------|--------|---------|
| Recent change in failure area | Highest | Commit yesterday to failing component |
| Known transient pattern | High | Matches rolling upgrade error |
| Similar historical failures | Medium | Same test flaked last month |
| Environmental difference | Medium | Only fails in CI, not locally |
| Speculation without evidence | Low | "Maybe there's a race condition" |

#### 3.3 Common Hypothesis Categories

**For Consistent Failures:**
1. Recent code change introduced bug
2. Test assertions are incorrect
3. Configuration changed

**For Intermittent Failures:**
1. Race condition in test setup
2. Timing-dependent external call
3. Shared state between tests
4. Resource contention in CI

**For Environment Failures:**
1. Missing environment variable
2. Permission denied
3. Service unavailable in that region
4. Different software versions

### Phase 4: Investigation Plan

**Time Budget**: Define before executing

#### 4.1 Prioritize by Feedback Speed

| Priority | Time | Investigation Type |
|----------|------|-------------------|
| P0 | Seconds | Check transient patterns, recent commits |
| P1 | Minutes | Kusto queries, log analysis, grep source |
| P2 | 10+ min | Full source code review, reproduction |
| P3 | Hours | Local debugging, reduced test case |

#### 4.2 Investigation Plan Template

```markdown
## Investigation Plan

| Step | Action | Validates Hypothesis | Expected If True | Time |
|------|--------|---------------------|------------------|------|
| 1 | Check transient error patterns | H3 | Match found | 30s |
| 2 | Query Kusto for exceptions | H1, H2 | Errors visible | 2m |
| 3 | Review test source | H2 | Bad assertion | 5m |
| 4 | Check commits since last green | H1 | Relevant change | 3m |
| 5 | Reproduce locally | H1, H2 | Same failure | 15m |
```

#### 4.3 Evidence Collection Checklist

- [ ] Error message and stack trace
- [ ] Test source code (assertions)
- [ ] Code under test (relevant methods)
- [ ] Kusto telemetry (runtime errors)
- [ ] Recent git commits (potential culprits)
- [ ] Historical test results (pattern detection)
- [ ] Environment configuration (diff if available)

### Phase 5: Root Cause Identification

**Time Budget**: As needed, but be honest about confidence

#### 5.1 Convergence Process

1. Execute investigation plan in priority order
2. After each step, update hypothesis statuses:
   - ✅ **Confirmed**: Evidence strongly supports
   - ❌ **Ruled Out**: Evidence contradicts
   - 🔍 **Investigating**: Need more data
   - ⏸️ **Parked**: Low priority, check if others fail

3. Stop when one hypothesis reaches high confidence

#### 5.2 Root Cause Statement Template

```markdown
## Root Cause

**Statement**: [Clear, specific description of what caused the failure]

**Confidence**: High / Medium / Low

**Type**: [Logic Bug / Flaky Test / Environment / Timing / Dependency / Data / Regression]

**Evidence**:
1. [Specific evidence point 1]
2. [Specific evidence point 2]
3. [Specific evidence point 3]

**Ruled Out Alternatives**:
- H1 ([description]): Ruled out because [specific reason]
- H3 ([description]): Ruled out because [specific reason]
```

#### 5.3 Confidence Calibration

| Confidence | Criteria |
|------------|----------|
| **High** | Direct evidence (stack trace points to line, commit diff explains failure) |
| **Medium** | Circumstantial evidence (timing correlates, pattern matches) |
| **Low** | Hypothesis fits but no direct proof |

### Phase 6: Fix Strategy

**Time Budget**: 10-15 minutes

#### 6.1 Fix Type Decision

| Situation | Fix Type | Example |
|-----------|----------|---------|
| Test assertion is wrong | Test Fix | Update expected value |
| Test is flaky by design | Test Fix | Add retry, improve isolation |
| Production code has bug | Code Fix | Fix the actual defect |
| Test reveals missing case | Both | Fix code AND add test |
| Config is wrong | Config Fix | Update environment settings |

#### 6.2 Fix Principles

1. **Minimal**: Change as little as possible
2. **Correct**: Actually fix the root cause, not symptoms
3. **Safe**: Don't introduce new risks
4. **Maintainable**: Don't add tech debt
5. **Tested**: Verify the fix works

#### 6.3 Fix Strategy Template

```markdown
## Fix Strategy

**Recommended Fix**: [What to change]

**Change Type**: Test / Code / Configuration / Infrastructure

**Files to Modify**:
- `path/to/file1.cs`: [What to change]
- `path/to/file2.cs`: [What to change]

**Implementation Steps**:
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Risks**:
- [Risk 1]: Mitigated by [mitigation]

**Alternatives Considered**:
- [Alternative]: Rejected because [reason]
```

### Phase 7: Verification & Prevention

**Time Budget**: 10+ minutes

#### 7.1 Verification Checklist

```markdown
## Verification

- [ ] Fix compiles without errors
- [ ] Previously failing test now passes
- [ ] No new test failures introduced
- [ ] Code review approved
- [ ] CI pipeline passes
- [ ] Monitored N subsequent runs for stability
```

#### 7.2 Prevention Analysis

For each failure, ask:
1. **Earlier Detection**: How could we have caught this sooner?
2. **Better Signal**: How could the error message be clearer?
3. **More Resilient**: How could the test be less flaky?
4. **Better Coverage**: What related scenarios need testing?

#### 7.3 Prevention Recommendations Template

```markdown
## Prevention Recommendations

### Immediate (This PR)
- [ ] Improve error message in [location]
- [ ] Add missing assertion for [edge case]

### Short-term (Next Sprint)
- [ ] Add integration test for [scenario]
- [ ] Create alert for [early warning]

### Long-term (Backlog)
- [ ] Refactor [component] for better testability
- [ ] Improve test infrastructure for [capability]
```

---

## Quick Reference Card

### Investigation Sequence
0. **Filter** → Skip tests that passed on retry
1. **Understand** → Restate, classify, identify gap
2. **Scope** → Recent changes, isolation, blast radius
3. **Hypothesize** → Rank by likelihood, define validation
4. **Plan** → Fastest feedback first
5. **Investigate** → Gather evidence, update hypotheses
6. **Identify** → Converge on root cause
7. **Fix** → Minimal, correct, safe
8. **Verify** → Confirm fix, prevent recurrence

### Time Budget (30-60 minutes total)
- Retry Filtering: 2-3 min
- Understanding: 5-10 min
- Context: 5-10 min
- Hypotheses: 5-10 min
- Investigation: 10-20 min
- Fix + Verify: 10-15 min

### Red Flags (Escalate)
- Security-related failure
- Data corruption possible
- Multiple unrelated tests failing
- Infrastructure-wide issues
- No hypothesis fits evidence
