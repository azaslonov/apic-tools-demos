# Transient Error Patterns

Known transient errors that typically resolve on retry. Source: `Automation/AutomaticTestFailureAnalyzer/analyze_failure.py`

## Definitive Transient Patterns

These patterns are known transient issues that will likely pass on retry:

### Rolling Upgrade in Progress
```
There is ongoing RollingUpgrade Start on
```
**Cause**: Test ran during infrastructure rolling upgrade
**Action**: Retry the test

### File Access Conflict
```
The process cannot access the file 'C:\Users\cloudtest\AppData\Local\Temp\IssuersInstanceCache\ALLUSAGES-AME-PUBLIC.json' because it is being used by another process.
```
**Cause**: Concurrent file access during test execution
**Action**: Retry the test

### Queue Deletion Error
```
Exception: System.OperationCanceledException : The operation cannot be performed because the entity has been closed or aborted.
```
**Cause**: Service Bus queue cleanup timing issue
**Action**: Retry the test

## Likely Transient Patterns

These patterns suggest transient issues but should be verified:

### Timeout Errors
```
The operation has timed out
TaskCanceledException
```
**Possible causes**: 
- Infrastructure slowness
- High load during test
- Network issues

### Throttling
```
429 Too Many Requests
Rate limit exceeded
```
**Cause**: Test hit rate limits
**Action**: Wait and retry

### Temporary Service Unavailable
```
503 Service Unavailable
The service is temporarily unavailable
```
**Cause**: Backend service restart or deployment
**Action**: Retry after a few minutes

## Detection Logic

```python
transient_errors = {
    "There is ongoing RollingUpgrade Start on": "ongoing RollingUpgrade",
    "The process cannot access the file...ALLUSAGES-AME-PUBLIC.json": "File access conflict"
}

def is_transient(error_text):
    for pattern in transient_errors:
        if pattern in error_text:
            return True, transient_errors[pattern]
    
    # Check for queue deletion error at start
    if error_text.startswith("Exception: System.OperationCanceledException"):
        return True, "Queue deletion error"
    
    return False, None
```

## Non-Transient Indicators

These patterns usually indicate real issues:

- `NullReferenceException` in test code
- `Assert.` failures with specific value mismatches
- `InvalidOperationException` with consistent stack trace
- Missing configuration errors
- Authentication/authorization failures (401, 403)
- Schema validation errors

## Recommendation Matrix

| Pattern | Classification | Action |
|---------|---------------|--------|
| RollingUpgrade | Transient | Retry |
| File lock | Transient | Retry |
| Queue closed | Transient | Retry |
| Timeout (isolated) | Likely Transient | Retry once |
| Timeout (repeated) | Investigate | Check infrastructure |
| Assert failure | Persistent | Fix code |
| NullReference | Persistent | Fix code |
| Auth failure | Persistent | Check config |
