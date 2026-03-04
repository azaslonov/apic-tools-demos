# Known Error Patterns

Common error patterns in RP integration tests with classification and recommended actions.

---

## ⛔ STOP - Manual Action Required Patterns

These patterns require manual intervention. Do NOT proceed with automated investigation or bug filing.

### Test Framework Timeout (3 hours)

```
timed out after 10800000ms
Test execution timed out
```

**Cause**: Test exceeded the 3-hour test framework timeout limit  
**Action**: ⛔ **STOP** - Prompt for manual action  
**Why**: This indicates the test itself is stuck or taking too long, not a product bug. Requires manual investigation of:
- Whether the test is waiting on an external dependency
- Whether an orchestration is stuck
- Whether the test environment is healthy
- Whether the test needs optimization

**Response template**:
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
```

---

## Transient Patterns (SKIP - Do NOT File Bug)

These patterns are known transient issues that will likely pass on retry.

### Rolling Upgrade in Progress

```
There is ongoing RollingUpgrade Start on
```

**Cause**: Test ran during infrastructure rolling upgrade  
**Action**: SKIP - transient  
**Note in summary**: "Skipped - rolling upgrade in progress"

### File Access Conflict

```
The process cannot access the file 'C:\Users\cloudtest\AppData\Local\Temp\...' because it is being used by another process
```

**Cause**: Concurrent file access during test execution  
**Action**: SKIP - transient  
**Note in summary**: "Skipped - file lock contention"

### Queue/Service Bus Errors

```
System.OperationCanceledException: The operation cannot be performed because the entity has been closed or aborted
```

**Cause**: Service Bus queue cleanup timing issue  
**Action**: SKIP - transient  
**Note in summary**: "Skipped - Service Bus transient error"

### Throttling (429)

```
429 Too Many Requests
Rate limit exceeded
TooManyRequests
```

**Cause**: Test hit rate limits  
**Action**: SKIP - throttling  
**Note in summary**: "Skipped - throttling (429)"

### Temporary Service Unavailable (503)

```
503 Service Unavailable
The service is temporarily unavailable
ServiceUnavailable
```

**Cause**: Backend service restart or deployment  
**Action**: SKIP - transient  
**Note in summary**: "Skipped - service temporarily unavailable"

### Timeout (Isolated)

```
The operation has timed out
TaskCanceledException
OperationCanceledException
```

**Cause**: Could be transient slowness  
**Action**: 
- If isolated (single test): SKIP - likely transient
- If repeated (multiple tests): INVESTIGATE - may indicate real issue

### Quota/Capacity Issues

```
QuotaExceeded
InsufficientCapacity
SkuNotAvailable
```

**Cause**: Test environment capacity limits  
**Action**: SKIP - infrastructure constraint  
**Note in summary**: "Skipped - quota/capacity limitation"

---

## Likely Transient Patterns (Verify Before Skipping)

These patterns suggest transient issues but should be verified.

### DNS Resolution Failure

```
No such host is known
NameResolutionFailure
```

**Possible causes**: 
- Transient DNS issue
- Service not deployed yet
**Action**: Check if multiple tests affected. If isolated, SKIP.

### Connection Refused

```
Connection refused
ConnectFailure
```

**Possible causes**:
- Service still starting up
- Service crashed
**Action**: Check Kusto for service health. If service is healthy now, SKIP.

### Certificate Errors

```
The remote certificate is invalid
SSL/TLS error
```

**Possible causes**:
- Certificate rotation in progress
- Clock skew
**Action**: Check if recent cert changes. Usually transient.

---

## Persistent Patterns (INVESTIGATE - File Bug)

These patterns usually indicate real issues that need fixing.

### NullReferenceException

```
System.NullReferenceException: Object reference not set to an instance of an object
```

**Cause**: Code defect - missing null check  
**Action**: INVESTIGATE - file bug  
**What to include**:
- Full stack trace
- Which object is null
- Code path analysis

### ArgumentException / ArgumentNullException

```
System.ArgumentException: Value cannot be null
System.ArgumentNullException: Parameter name: xyz
```

**Cause**: Invalid input not properly validated  
**Action**: INVESTIGATE - file bug  
**What to include**:
- What parameter is invalid
- What value was passed
- Where validation should occur

### InvalidOperationException

```
System.InvalidOperationException: Operation is not valid
```

**Cause**: Code called in invalid state  
**Action**: INVESTIGATE - file bug  
**What to include**:
- State machine analysis
- What operation was attempted
- What state was expected vs actual

### Assert Failures

```
Assert.AreEqual failed
Assert.IsTrue failed
Assert.IsNotNull failed
Expected: X, Actual: Y
```

**Cause**: Test expectation not met  
**Action**: INVESTIGATE - determine if test bug or code bug  
**What to include**:
- Expected vs actual values
- Whether expectation is correct
- Recent changes to tested code

### Authentication/Authorization Failures (401/403)

```
401 Unauthorized
403 Forbidden
AuthenticationFailed
```

**Cause**: Usually configuration or permission issue  
**Action**: INVESTIGATE - check if test-specific or broader  
**What to include**:
- What identity was used
- What permission was needed
- Recent changes to auth config

### Schema/Validation Errors

```
ValidationError
SchemaValidationFailed
The request is invalid
```

**Cause**: API contract mismatch  
**Action**: INVESTIGATE - file bug  
**What to include**:
- What schema violation occurred
- Expected vs actual payload
- Recent API changes

### Orchestration Stuck/Failed

```
Orchestration is stuck
OrchestrationFailed
TaskHub error
```

**Cause**: Orchestration logic issue  
**Action**: INVESTIGATE - file bug  
**What to include**:
- Orchestration name and instance ID
- Where it got stuck
- Kusto query showing orchestration state

### Database/EF Errors

```
SqlException
EntityFramework error
Deadlock
```

**Cause**: Database access issue  
**Action**: INVESTIGATE - file bug  
**What to include**:
- SQL error code
- Query that failed
- Deadlock graph if available

---

## Classification Decision Tree

```
Is error in transient list?
├── Yes → SKIP (note reason in summary)
└── No → Continue
         │
         Is error in "likely transient" list?
         ├── Yes → Check if isolated or widespread
         │         ├── Isolated → SKIP
         │         └── Widespread → INVESTIGATE
         └── No → Continue
                  │
                  Is error in persistent list?
                  ├── Yes → INVESTIGATE (file bug)
                  └── No → Analyze manually
                           ├── Consistent across retries? → INVESTIGATE
                           └── Passes sometimes? → Likely flaky, SKIP
```

---

## Quick Reference Table

| Pattern | Classification | Action |
|---------|---------------|--------|
| RollingUpgrade | Transient | SKIP |
| File lock | Transient | SKIP |
| Queue closed | Transient | SKIP |
| 429 Throttling | Transient | SKIP |
| 503 Unavailable | Transient | SKIP |
| Timeout (isolated) | Likely Transient | SKIP |
| Timeout (repeated) | Investigate | Check infra |
| DNS failure (isolated) | Likely Transient | SKIP |
| NullReferenceException | Persistent | FILE BUG |
| ArgumentException | Persistent | FILE BUG |
| Assert failure | Persistent | FILE BUG |
| Auth failure (401/403) | Persistent | FILE BUG |
| Schema validation | Persistent | FILE BUG |
| Orchestration stuck | Persistent | FILE BUG |
| SQL/EF error | Persistent | FILE BUG |

---

## Detection Code Pattern

```python
transient_patterns = [
    "There is ongoing RollingUpgrade",
    "The process cannot access the file",
    "entity has been closed or aborted",
    "429",
    "Too Many Requests",
    "503",
    "Service Unavailable",
    "QuotaExceeded",
    "InsufficientCapacity"
]

persistent_patterns = [
    "NullReferenceException",
    "ArgumentException",
    "ArgumentNullException",
    "Assert.AreEqual failed",
    "Assert.IsTrue failed",
    "401 Unauthorized",
    "403 Forbidden",
    "ValidationError",
    "OrchestrationFailed"
]

def classify_error(error_text):
    for pattern in transient_patterns:
        if pattern.lower() in error_text.lower():
            return "TRANSIENT", pattern
    
    for pattern in persistent_patterns:
        if pattern.lower() in error_text.lower():
            return "PERSISTENT", pattern
    
    return "UNKNOWN", None
```
