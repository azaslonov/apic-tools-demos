# Kusto Queries for Test Investigation

Query templates for the APIMTest database at `https://apim.kusto.windows.net`.

## Database Configuration

- **Cluster**: `https://apim.kusto.windows.net`
- **Database**: `APIMTest` (for Current, Dogfood, Private environments)
- **Database**: `APIMProd` (for Production - different permissions)

## Orchestration Queries

### Service Exceptions (Last 24h)
```kql
Orchestration
| where serviceName == "{serviceName}"
| where PreciseTimeStamp > ago(1d)
| where Level < 4
| order by PreciseTimeStamp desc
| project PreciseTimeStamp, exception, Level, operationName
| take 50
```

### Service Errors by Operation
```kql
Orchestration
| where serviceName == "{serviceName}"
| where PreciseTimeStamp > ago(2h)
| where Level < 3
| summarize count() by operationName, bin(PreciseTimeStamp, 5m)
| order by PreciseTimeStamp desc
```

## Proxy/Gateway Queries

### ProxyRequest Errors (EventId=205)
```kql
ProxyRequest
| where TIMESTAMP >= ago(2h)
| where serviceName == "{serviceName}"
| where EventId == 205
| where statusCode >= 400
| project TIMESTAMP, url, statusCode, exception, correlationId
| take 50
```

### Gateway Outgoing Request Failures
```kql
GatewayOutgoingRequests
| where TIMESTAMP >= ago(2h)
| where serviceName == "{serviceName}"
| where responseCode >= 400
| project TIMESTAMP, backendUrl, responseCode, exception
| take 50
```

## Gateway Outgoing Requests by DeploymentName

**Note**: `GatewayOutgoingRequests` may have empty `serviceName` field. Use `DeploymentName` filter instead:

```kql
let t = datetime({timestamp});
GatewayOutgoingRequests
| where PreciseTimeStamp between ( t-15m .. t+5m )
| where DeploymentName startswith '{serviceName}'
| project PreciseTimeStamp, source, RelatedActivityId, url, responseCode, RoleInstance
| take 100
```

## Correlating ProxyRequest with GatewayOutgoingRequests

To correlate inbound requests with outbound backend calls, join on `RelatedActivityId`:

```kql
let t = datetime({timestamp});
let proxyActivityIds = ProxyRequest
| where PreciseTimeStamp between ( t-5m .. t+5m )
| where DeploymentName startswith '{serviceName}'
| where EventId == 205
| project RelatedActivityId;
GatewayOutgoingRequests
| where PreciseTimeStamp between ( t-5m .. t+5m )
| where DeploymentName startswith '{serviceName}'
| where source == "send-request"
| where RelatedActivityId in (proxyActivityIds)
| summarize count() by RoleInstance
```

## Cache-Value Stampede Validation

For tests validating cache stampede protection (e.g., `CacheValue_StampedeSucceeds`):

```kql
// Count send-request operations per worker - should be 1 per RoleInstance for stampede protection
let t = datetime({timestamp});
All('ProxyRequest')
| where TIMESTAMP between (t-5m .. t+5m)
| where serviceName == "{serviceName}"
| where EventId == 205
| where apiId == "{apiId}"
| project RelatedActivityId, apiId
| join kind=inner (
    All("GatewayOutgoingRequests")
    | where TIMESTAMP between (t-5m .. t+5m)
    | where source == "send-request"
) on RelatedActivityId
| summarize TotalRefreshes = count() by apiId, RoleInstance
| order by apiId, RoleInstance
```

**Expected**: `TotalRefreshes = 1` per RoleInstance (stampede protection working)
**Failure**: `TotalRefreshes > 1` indicates stampede protection regression

## Configuration Service Queries

### CfgSvc Request Trace
```kql
CfgSvcRequestTrace
| where TIMESTAMP >= ago(2h)
| where serviceName == "{serviceName}"
| where eventType in ("RequestStarted", "RequestCompleted")
| project TIMESTAMP, eventType, operationName, exception
| order by TIMESTAMP desc
| take 100
```

### CfgSvc Errors
```kql
CfgSvcRequest
| where TIMESTAMP >= ago(2h)
| where serviceName == "{serviceName}"
| where Level < 3
| project TIMESTAMP, message, exception
| take 50
```

## Control Plane Queries

### Gateway Control Plane Operations
```kql
GatewayControlPlaneRequests
| where TIMESTAMP >= ago(2h)
| where serviceName == "{serviceName}"
| where success == false
| project TIMESTAMP, operation, errorMessage
| take 50
```

## Health Probe Queries

### Health Probe Status
```kql
HealthProbeStatusRequest
| where TIMESTAMP >= ago(1h)
| where serviceName == "{serviceName}"
| where EventId == 2
| summarize count() by isHealthy, bin(TIMESTAMP, 1m)
| order by TIMESTAMP desc
```

## Using All() Functions

The `All('TableName')` functions provide cross-region views with normalized fields. Prefer these for test investigation:

```kql
// All() function has serviceName properly populated
All('ProxyRequest')
| where TIMESTAMP >= ago(2h)
| where serviceName == "{serviceName}"
| where EventId == 205
| project TIMESTAMP, serviceName, apiId, RelatedActivityId
| take 50

All("GatewayOutgoingRequests")
| where TIMESTAMP >= ago(2h)
| where source == "send-request"
| project TIMESTAMP, RelatedActivityId, url, responseCode
| take 50
```

## Common Filters

### Time Ranges
- Last hour: `ago(1h)`
- Last 2 hours: `ago(2h)`
- Last day: `ago(1d)`
- Specific time: `datetime(2026-01-16T10:00:00Z)`

### Log Levels
- `Level < 2`: Error only
- `Level < 3`: Error + Warning
- `Level < 4`: Error + Warning + Info

### Service Name Extraction

From test output logs, look for lines containing:
- `servicename` in JSON
- `"ServiceName":` in test configuration

## Using with Kusto MCP

The Kusto MCP is configured for APIMTest:
```json
{
  "azure-kusto-mcp-apimtest": {
    "command": "uvx",
    "args": ["azure-kusto-mcp"],
    "env": {
      "KUSTO_SERVICE_URI": "https://apim.kusto.windows.net",
      "KUSTO_DATABASE": "APIMTest"
    }
  }
}
```

Invoke queries using the Kusto MCP tool with the query text.
