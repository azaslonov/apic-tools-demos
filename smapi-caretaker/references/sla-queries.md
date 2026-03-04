# SLA Queries for SMAPI Caretaker

This reference contains all SLA queries used by the SMAPI Caretaker skill.

## Time Range Parameters

All queries use these parameters:
- `{startTime}` - Start of time range (ISO 8601 format, e.g., `2026-01-20T21:00:00Z`)
- `{endTime}` - End of time range (ISO 8601 format, e.g., `2026-01-21T21:00:00Z`)

**Default:** Past 24 hours from current time.

---

## SMAPI Queries

All SMAPI queries use the `ManagementKpiNormalized` **function** (not a table).

> ⚠️ **Important:** Do NOT wrap with `All("...")` - it's a function, call it directly.

### SMAPI SKUv1 SLA

```kql
ManagementKpiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where DeploymentType == "SKUv1"
| where eventType == "MapiKpi"
| where uri has "subscriptions"
| summarize
    Success = countif(response < 500 and duration < 90000),
    TotalRequests = count()
    by Region, bin(PreciseTimeStamp, 5m)
| extend SLA = todouble(Success * 100) / TotalRequests
| summarize
    SLA = min(SLA)
    by Region, bin(PreciseTimeStamp, 3600000ms)
| order by Region asc
```

### SMAPI SKUv2 SLA

```kql
ManagementKpiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where DeploymentType == "SKUv2"
| where eventType == "MapiKpi"
| where uri has "subscriptions"
| summarize
    Success = countif(response < 500 and duration < 90000),
    TotalRequests = count()
    by Region, bin(PreciseTimeStamp, 5m)
| extend SLA = todouble(Success * 100) / TotalRequests
| summarize
    SLA = min(SLA)
    by Region, bin(PreciseTimeStamp, 3600000ms)
| order by Region asc
```

### SMAPI Consumption SLA

```kql
ManagementKpiNormalized
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where DeploymentType == "Consumption"
| where eventType == "MapiKpi"
| where uri has "subscriptions"
| summarize
    Success = countif(response < 500 and duration < 90000),
    TotalRequests = count()
    by Region, bin(PreciseTimeStamp, 5m)
| extend SLA = todouble(Success * 100) / TotalRequests
| summarize
    SLA = min(SLA)
    by Region, bin(PreciseTimeStamp, 3600000ms)
| order by Region asc
```

---

## RP HTTP SLA Queries

These queries use the `HttpIncomingRequests` **table**.

> ⚠️ **Important:** Use `All('HttpIncomingRequests')` for cross-cluster queries.

### What These Measure

**RP SLA = HTTP response success**, NOT operational success.

Example: If RP fails to activate a service, the HTTP call to get the service container should still succeed (return 200 with failure status in body). The activation failure is operational, not HTTP SLA.

### RP SLA (includes SMAPI calls)

All RP HTTP requests, including those that call SMAPI.

```kql
All('HttpIncomingRequests')
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Tenant !has "global"
| where operationName !startswith "admin/" and operationName != "HttpRequestCompleted"
| where httpStatusCode != -1
| where targetUri has "subscriptions"
| where isnotempty(serviceName)
| summarize
    Success = countif(httpStatusCode < 500 and durationInMilliseconds < 90000),
    TotalRequests = count()
    by Region, bin(PreciseTimeStamp, 5m)
| extend SLA = todouble(Success * 100) / TotalRequests
| summarize
    SLA = min(SLA)
    by Region, bin(PreciseTimeStamp, 3600000ms)
| order by Region asc
```

### RP Only SLA (excludes SMAPI calls)

RP HTTP requests that don't involve SMAPI.

```kql
All('HttpIncomingRequests')
| where PreciseTimeStamp >= datetime({startTime}) and PreciseTimeStamp <= datetime({endTime})
| where Tenant !has "global"
| where operationName !startswith "admin/" 
| where operationName !in ("HttpRequestCompleted", "Call Management API") 
| where httpStatusCode != -1
| where targetUri has "subscriptions"
| where isnotempty(serviceName)
| summarize
    Success = countif(httpStatusCode < 500 and durationInMilliseconds < 90000),
    TotalRequests = count()
    by Region, bin(PreciseTimeStamp, 5m)
| extend SLA = todouble(Success * 100) / TotalRequests
| summarize
    SLA = min(SLA)
    by Region, bin(PreciseTimeStamp, 3600000ms)
| order by Region asc
```

---

## SLA Definition

For all queries:
- **Success:** `response/httpStatusCode < 500` AND `duration/durationInMilliseconds < 90000ms`
- **SLA:** `(Success / TotalRequests) * 100`
- **Aggregation:** Minimum SLA per region per hour

---

## Query Execution Notes

1. Use `apim-kusto-agent` via the task tool to execute queries
2. Database: `APIMProd` (production data)
3. Results are per-region, per-hour - look for the worst values
4. Compare across components to prioritize investigation
