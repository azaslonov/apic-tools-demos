# Investigation Patterns

Diagnostic queries and patterns for investigating SLA issues.

---

## Important Note

> ⚠️ **These queries are STARTING POINTS.** The agent should adapt, combine, and explore freely.

---

## Deep Investigation Queries

### 1. Top Errors (by count) - Start Here

Query `MapiNormalized` for top errors in the affected region/time:

```kql
MapiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Region == '{region}'
| where DeploymentType == '{SKUv1|SKUv2|Consumption}'
| where Level == 2
| where isnotempty(exception)
| summarize 
    Count = count(),
    Services = dcount(DeploymentName)
    by ErrorType = extract("^[^:]+", 0, exception)
| top 10 by Count
```

### 2. Full Stack Traces (for each top error)

After identifying top errors, get full details:

```kql
MapiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Region == '{region}'
| where DeploymentType == '{SKUv1|SKUv2|Consumption}'
| where Level == 2
| where exception has "{errorType}"
| project PreciseTimeStamp, exception, message, uri, httpMethod, activityId
| take 5
```

### 3. Trace Full Request by ActivityId (IMPORTANT)

Once you have an activityId from an error, trace the ENTIRE request flow:

```kql
MapiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where activityId == "{activityId}"
| order by PreciseTimeStamp asc
| project PreciseTimeStamp, eventType, message, exception, Level
```

This shows every log entry for that single request - trace where it started, what it called, and where it failed.

### 4. Find Related Logs Around Error Time

Get context around when the error occurred:

```kql
MapiNormalized
| where PreciseTimeStamp >= datetime({errorTime}) - 1m and PreciseTimeStamp <= datetime({errorTime}) + 1m
| where Region == '{region}'
| where DeploymentType == '{type}'
| where RoleInstance == '{roleInstance}'  // same instance as the error
| order by PreciseTimeStamp asc
| project PreciseTimeStamp, eventType, message, exception, Level, activityId
| take 100
```

### 5. Trace RP to SMAPI Call Flow

For RP errors that involve SMAPI calls, trace the full flow:

```kql
// First, find the RP request
All('HttpIncomingRequests')
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where correlationId == "{correlationId}"
| project PreciseTimeStamp, operationName, httpStatusCode, durationInMilliseconds, targetUri

// Then check SMAPI side with same correlationId
MapiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where activityId == "{correlationId}" or message has "{correlationId}"
| order by PreciseTimeStamp asc
```

### 6. Find What Changed - Recent Errors Spike

Compare error rates to identify when issues started:

```kql
MapiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Region == '{region}'
| where Level == 2
| summarize ErrorCount = count() by bin(PreciseTimeStamp, 5m), ErrorType = extract("^[^:]+", 0, exception)
| order by PreciseTimeStamp asc
```

---

## Resource-Specific Queries

### 7. RoleInstance Count (SKUv2/Consumption)

Check if instance count dropped (multitenant architecture - fewer instances = reduced capacity):

```kql
ManagementKpiNormalized
| union MapiInfraNormalized
| union MapiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Region == '{region}'
| where DeploymentType == "{SKUv2|Consumption}"
| summarize InstanceCount = dcount(RoleInstance) by bin(PreciseTimeStamp, 5m), Tenant
```

**Interpretation:**
- Normal: Stable instance count
- Issue: Sudden drop in instance count correlating with SLA dip

### 8. Database CPU Utilization

Check if database CPU spike caused slowdown:

```kql
All('Orchestration')
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Region == '{region}'
| where eventType == 'HealthMonitorSmapiScaleUnitDatabaseUsage'
| extend parsed = parse_json(message)
| mv-expand usageData = parsed['UsageData']
| project probeTime = todatetime(usageData['EndTime']), cpu = toreal(usageData["AverageCpuPercentage"]), serviceName, Region
| where probeTime >= datetime({startTime}) and probeTime <= datetime({endTime})
| summarize cpu = max(cpu) by probeTime, scaleunit = serviceName, Region
| summarize Average = avg(cpu) by bin(probeTime, 5m), scaleunit, Region
```

**Interpretation:**
- Normal: CPU < 70%
- Warning: CPU 70-85%
- Critical: CPU > 85% - likely causing query timeouts

### 9. SQL Query Latency

Check if database latency increased:

```kql
MapiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Region == '{region}'
| where DeploymentType == '{SKUv1|SKUv2|Consumption}'
| where eventType == "TraceStepStop"
| parse-where message with "name:sql-query, elapsed:" elapsed
| extend elapsed = totimespan(elapsed) / time(1ms)
| summarize
    minElapsed = min(elapsed),
    avgElapsed = avg(elapsed),
    maxElapsed = max(elapsed)
    by bin(PreciseTimeStamp, 5m), Region, Tenant
```

**Interpretation:**
- Normal: avg < 100ms, max < 1000ms
- Warning: avg 100-500ms
- Critical: avg > 500ms or max > 5000ms

### 10. Dependency-Specific Errors

Filter errors by known dependency patterns:

```kql
MapiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Region == '{region}'
| where Level == 2
| where exception has_any ("SqlException", "SqlClient", "database", "connection")
| summarize count() by bin(PreciseTimeStamp, 5m)
```

Replace the `has_any` filter for different dependencies:
- **Redis:** `"Redis", "RedisConnection", "StackExchange"`
- **Storage:** `"StorageException", "Azure.Storage", "BlobClient"`
- **AAD:** `"Msal", "AADSTS", "authentication", "identity"`

---

## Other Potential Causes

Don't limit investigation to the queries above. Consider:

| Category | Potential Causes |
|----------|-----------------|
| **Deployment** | Rolling upgrade in progress, recent deployment, rollback |
| **Network** | DNS failures, connectivity issues, NSG changes |
| **Authentication** | Certificate expiration, AAD outage, secret rotation |
| **Dependencies** | Redis cluster issues, storage throttling, SQL failover |
| **Capacity** | Traffic spike, instance failures, scale-in events |
| **Code** | Regression from recent release, bug introduced |
| **Platform** | Azure regional issues, compute problems |

---

## Code Areas by Component

When investigating code, focus on these areas:

| Component | Code Location | Key Classes |
|-----------|---------------|-------------|
| SMAPI SKUv1 | `Management/` | Controllers, Services, Data layer |
| SMAPI SKUv2 | `Management/` | Same, but multitenant hosting |
| Consumption | `Management/` | Same, Consumption-specific paths |
| RP | `ResourceProvider/` | Controllers, Orchestrations |
| RP→SMAPI | `ResourceProvider/` | `IRegionalResourceProviderClient` |

Use `explore` agent to find specific code when errors point to particular classes/methods.

---

## Correlating Multiple Signals

| Signal 1 | Signal 2 | Likely Cause |
|----------|----------|--------------|
| High DB CPU | High SQL latency | Database throttling |
| Instance count drop | Increased error rate | Capacity reduction |
| AAD errors spike | Auth failures | AAD/certificate issue |
| Storage errors | Timeout errors | Storage throttling |
| All regions affected | Same time | Deployment or platform issue |
| Single region affected | - | Regional infrastructure issue |
