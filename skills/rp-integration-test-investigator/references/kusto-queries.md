# Kusto Queries for RP Integration Test Investigation

Query templates for the APIMTest database at `https://apim.kusto.windows.net`.

---

## Critical: Always Use All() Function

> ⚠️ **CRITICAL**: Always use `All('{TableName}')` when referencing Kusto tables. This provides cross-region views with normalized fields.

```kql
// ✅ CORRECT - Use All() function
All('Orchestration')
| where PreciseTimeStamp > ago(2h)

// ❌ WRONG - Direct table reference
Orchestration
| where PreciseTimeStamp > ago(2h)
```

---

## Tables by SKU Type

> ⚠️ **IMPORTANT**: Use the correct tables based on which SKU the test is targeting.

### Shared Tables (Both SKUs)

| Table | All() Reference | Purpose |
|-------|-----------------|---------|
| `Orchestration` | `All('Orchestration')` | Orchestration execution and errors |
| `ResourceProvider` | `All('ResourceProvider')` | Resource Provider operations |
| `HttpIncomingRequests` | `All('HttpIncomingRequests')` | HTTP request telemetry |
| `ManagementKpi` | `All('ManagementKpi')` | Management API KPIs and metrics |
| `Mapi` | `All('Mapi')` | Management API application logs |
| `CfgSvcRequestTrace` | `All('CfgSvcRequestTrace')` | Configuration service traces |
| `GatewayControlPlaneRequests` | `All('GatewayControlPlaneRequests')` | Gateway control plane operations |

### SKUv2 Investigation Tables (Modern Platform)

| Table | All() Reference | Purpose |
|-------|-----------------|---------|
| `ProxyRequest` | `All('ProxyRequest')` | Gateway proxy request logs |

### SKUv1 Investigation Tables (Classic Platform)

| Table | All() Reference | Purpose |
|-------|-----------------|---------|
| `ApiSvcHost` | `All('ApiSvcHost')` | API Service host process logs |
| `MicrosoftWindowsDscEvents` | `All('MicrosoftWindowsDscEvents')` | DSC (Desired State Configuration) events |
| `DscLogs` | `All('DscLogs')` | DSC execution logs |
| `ProxyInfra` | `All('ProxyInfra')` | Proxy infrastructure logs |
| `MapiInfra` | `All('MapiInfra')` | Management API infrastructure logs |
| `Integration` | `All('Integration')` | Integration component logs |
| `ApplicationEvents` | `All('ApplicationEvents')` | General application events |

---

## Database Configuration

| Setting | Value |
|---------|-------|
| **Cluster** | `https://apim.kusto.windows.net` |
| **Database** | `APIMTest` |
| **Agent** | `apim-kusto-agent` |

> **Note**: RP integration tests run against test environments (Current, Dogfood), so use APIMTest database.

---

## SKUv2 Queries (Modern Platform)

Use these queries for SKUv2, Consumption, PremiumV2, Workspace Gateway, and AI Platform tests.

### Orchestration Errors

```kql
All('Orchestration')
| where PreciseTimeStamp > ago(2h)
| where serviceName == "{serviceName}"
| where Level < 3  // Error and Warning
| project PreciseTimeStamp, operationName, exception, Level, RoleInstance
| order by PreciseTimeStamp desc
| take 50
```

### Orchestration by Operation Name

```kql
All('Orchestration')
| where PreciseTimeStamp > ago(2h)
| where operationName contains "{operationName}"
| where Level < 4
| summarize count() by operationName, Level, bin(PreciseTimeStamp, 5m)
| order by PreciseTimeStamp desc
```

### SLA for Operations in the Last 1 day

```kql
let _endTime = datetime(2026-01-15T21:00:00Z);
let _startTime = datetime(2026-01-14T21:00:00Z);
let clusterName = 'api-mwh-current-01';
All('OrchestrationKpi')
| where PreciseTimeStamp between (_startTime .. _endTime)
| where Tenant in (clusterName)
| where orchestrationName == "ActivateApiService"
| where resourceType == "service"
| where sku in ("Developer", "Basic", "Standard", "Premium")
| summarize Total = countif(operationStatus in ("Success", "Failed")),
            SuccessfulActivations = countif(operationStatus == "Success" ),
            FailedActivations = countif(operationStatus == "Failed") by Region, bin(PreciseTimeStamp, 1h), codeVersion
| extend SLA = round((todouble(SuccessfulActivations * 100) / Total), 5)
| project PreciseTimeStamp, Region, SLA, codeVersion
```


### Get capacity for SKU V1 compute pools in a region

```kql
let _region = "westus2";
All('RCMResourcePoolsTable')
| where TIMESTAMP > ago(7d)
| summarize arg_max(TIMESTAMP, *) by Region, ResourcePoolId // Latest data
| where Region == _region
| where ResourceTypeDescription in ("Dav4", "Dsv3", "Dv3", "VmssCore") // Filter out SKU V1 compute pools only
| where ReadOnly == false
| where ResourcePoolRegion == "East US" // Check capacity in primary region only
| project TIMESTAMP, Region, ResourcePoolId, ResourceType, ResourceTypeDescription, ResourcePoolRegion, ResourceAllocatedCount, MaxResourceAvailableCount, ReadOnly, ReadOnlyManualOverride, ReadOnlyReason
| summarize sum(ResourceAllocatedCount), sum(MaxResourceAvailableCount) by ResourceTypeDescription
```

---

## HTTP Request Queries

### All HTTP Errors for Service

```kql
All('HttpIncomingRequests')
| where TIMESTAMP > ago(2h)
| where serviceName == "{serviceName}"
| where responseCode >= 400
| project TIMESTAMP, operationName, responseCode, exception, correlationId
| order by TIMESTAMP desc
| take 50
```

### Requests by Operation

```kql
All('HttpIncomingRequests')
| where TIMESTAMP > ago(2h)
| where operationName contains "{operationName}"
| summarize 
    total = count(),
    errors = countif(responseCode >= 400),
    avgDuration = avg(durationMs)
    by operationName, bin(TIMESTAMP, 5m)
| order by TIMESTAMP desc
```

### Timeout Analysis

```kql
All('HttpIncomingRequests')
| where TIMESTAMP > ago(2h)
| where serviceName == "{serviceName}"
| where durationMs > 30000  // > 30 seconds
| project TIMESTAMP, operationName, durationMs, responseCode
| order by durationMs desc
| take 50
```

---

## Resource Provider Specific Queries (SKUv2)

### ResourceProvider Table - Operation Errors

```kql
All('ResourceProvider')
| where PreciseTimeStamp > ago(2h)
| where serviceName == "{serviceName}"
| where Level < 3
| project PreciseTimeStamp, operationName, message, exception, Level
| order by PreciseTimeStamp desc
| take 50
```

### ResourceProvider - Failed Operations Summary

```kql
All('ResourceProvider')
| where PreciseTimeStamp > ago(2h)
| where Level < 3
| summarize errorCount = count() by operationName, bin(PreciseTimeStamp, 5m)
| order by errorCount desc
```

---

## Consumption SKU and SKUv2 Queries

### Consumption Service Activation - Full Diagnostics

This query shows Consumption service activation failures with website provisioning details:

```kql
let startTime = ago(2h);
let endTime = now();
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp between (startTime..endTime)
| where serviceName == svcName
| where eventType in ("ActivateConsumptionServiceOrchestrationFailed", "ActivateConsumptionServiceOrchestrationSucceeded")
| project PreciseTimeStamp, Tenant, instanceId, subscriptionId, serviceName, eventType, Level, Region, exception
| order by PreciseTimeStamp desc 
| join kind=leftouter (
    All('Orchestration') 
    | where eventType in ("DeployWebsiteOrchestrationFailedToCreateWebsiteInRegion", "DeployWebsiteOrchestrationCreatingWebsite")
    | where PreciseTimeStamp between (startTime..endTime)
    | extend parentInstanceId = substring(instanceId, 0, indexof(instanceId, "_DeployWebsite"))
    | extend ejson = iif(eventType == "DeployWebsiteOrchestrationCreatingWebsite", parse_json(message), parse_json(exception))
    | project PreciseTimeStamp, Tenant, subscriptionId, parentInstanceId, serviceName, 
              websiteName=ejson["WebsiteName"], 
              websiteSubscriptionId=tostring(ejson["ResourceSubscriptionId"]), 
              region=ejson["Region"], 
              exception=ejson["Exception"]["Message"], 
              eventType
) on $left.instanceId == $right.parentInstanceId
| project PreciseTimeStamp, Region, Tenant, TenantSubscription = subscriptionId, instanceId, serviceName, eventType, 
          websiteCreationFailed = iff(eventType1 == "DeployWebsiteOrchestrationCreatingWebsite", "WebsiteCreationFailed", ""),  
          Level, websiteName, websiteSubscriptionId, exception
| where Level < 4 
| summarize max(PreciseTimeStamp), take_any(eventType), max(websiteCreationFailed), 
            take_anyif(websiteName, websiteName !=""), 
            take_anyif(websiteSubscriptionId, websiteSubscriptionId!=""), 
            take_anyif(exception, exception != "") 
  by Region, Tenant, TenantSubscription, instanceId, serviceName
| order by max_PreciseTimeStamp desc
```

### Consumption Service Activation by Tenant

Query activation status across a specific tenant:

```kql
let startTime = ago(1d);
let endTime = now();
let tenant = "{tenant}";  // e.g., "api-euapbn1-prod-01"
All('Orchestration')
| where Tenant == tenant
| where PreciseTimeStamp between (startTime..endTime)
| where eventType in ("ActivateConsumptionServiceOrchestrationFailed", "ActivateConsumptionServiceOrchestrationSucceeded")
| project PreciseTimeStamp, Tenant, instanceId, subscriptionId, serviceName, eventType, Level, Region, exception
| order by PreciseTimeStamp desc 
| join kind=leftouter (
    All('Orchestration') 
    | where Tenant == tenant
    | where eventType in ("DeployWebsiteOrchestrationFailedToCreateWebsiteInRegion", "DeployWebsiteOrchestrationCreatingWebsite")
    | where PreciseTimeStamp between (startTime..endTime)
    | extend parentInstanceId = substring(instanceId, 0, indexof(instanceId, "_DeployWebsite"))
    | extend ejson = iif(eventType == "DeployWebsiteOrchestrationCreatingWebsite", parse_json(message), parse_json(exception))
    | project PreciseTimeStamp, Tenant, subscriptionId, parentInstanceId, serviceName, 
              websiteName=ejson["WebsiteName"], 
              websiteSubscriptionId=tostring(ejson["ResourceSubscriptionId"]), 
              region=ejson["Region"], 
              exception=ejson["Exception"]["Message"], 
              eventType
) on $left.instanceId == $right.parentInstanceId
| project PreciseTimeStamp, Region, Tenant, TenantSubscription = subscriptionId, instanceId, serviceName, eventType, 
          websiteCreationFailed = iff(eventType1 == "DeployWebsiteOrchestrationCreatingWebsite", "WebsiteCreationFailed", ""),  
          Level, websiteName, websiteSubscriptionId, exception
| where Level < 4 
| summarize max(PreciseTimeStamp), take_any(eventType), max(websiteCreationFailed), 
            take_anyif(websiteName, websiteName !=""), 
            take_anyif(websiteSubscriptionId, websiteSubscriptionId!=""), 
            take_anyif(exception, exception != "") 
  by Region, Tenant, TenantSubscription, instanceId, serviceName
| order by max_PreciseTimeStamp desc
```

### Website Provisioning Failures

Query website provisioning failures specifically:

```kql
let startTime = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > startTime
| where serviceName == svcName
| where eventType in ("DeployWebsiteOrchestrationFailedToCreateWebsiteInRegion", "DeployWebsiteOrchestrationCreatingWebsite")
| extend ejson = iif(eventType == "DeployWebsiteOrchestrationCreatingWebsite", parse_json(message), parse_json(exception))
| project PreciseTimeStamp, serviceName, eventType,
          websiteName = ejson["WebsiteName"],
          websiteSubscriptionId = tostring(ejson["ResourceSubscriptionId"]),
          region = ejson["Region"],
          exception = ejson["Exception"]["Message"]
| order by PreciseTimeStamp desc
| take 50
```

### Consumption Activation Summary by Region

```kql
let startTime = ago(1d);
All('Orchestration')
| where PreciseTimeStamp > startTime
| where eventType in ("ActivateConsumptionServiceOrchestrationFailed", "ActivateConsumptionServiceOrchestrationSucceeded")
| summarize 
    Total = count(),
    Succeeded = countif(eventType == "ActivateConsumptionServiceOrchestrationSucceeded"),
    Failed = countif(eventType == "ActivateConsumptionServiceOrchestrationFailed")
  by Region, bin(PreciseTimeStamp, 1h)
| extend SuccessRate = round(100.0 * Succeeded / Total, 2)
| order by PreciseTimeStamp desc, Region
```

### Antares (App Service) Website Provisioning Details

When website provisioning fails, query the AntaresAdminGeoEvents table to get detailed App Service provisioning information:

```kql
let startTime = ago(1d);
let endTime = now();
let websiteSubscriptionId = "{websiteSubscriptionId}";  // From DeployWebsiteOrchestration logs
let websiteName = "{websiteName}";  // From DeployWebsiteOrchestration logs
let correlationId = "{correlationId}";  // From orchestration instance correlation
All('AntaresAdminGeoEvents')
| where PreciseTimeStamp between (startTime..endTime)
| where SubscriptionId == websiteSubscriptionId
| where CorrelationRequestId == correlationId
| project TIMESTAMP, Level, ActivityId, Details, Exception, Operation, LatencyInMilliseconds, Address, Verb, StatusCode, SubscriptionId, SiteName
| order by TIMESTAMP desc
```

### Antares Events by Website Name

```kql
let startTime = ago(2h);
let websiteName = "{websiteName}";
All('AntaresAdminGeoEvents')
| where PreciseTimeStamp > startTime
| where SiteName == websiteName
| project TIMESTAMP, Level, ActivityId, Details, Exception, Operation, LatencyInMilliseconds, StatusCode
| order by TIMESTAMP desc
| take 100
```

### Antares Failures for Subscription

```kql
let startTime = ago(2h);
let websiteSubscriptionId = "{websiteSubscriptionId}";
All('AntaresAdminGeoEvents')
| where PreciseTimeStamp > startTime
| where SubscriptionId == websiteSubscriptionId
| where Level < 3 or StatusCode >= 400
| project TIMESTAMP, Level, Operation, StatusCode, Exception, Details, SiteName
| order by TIMESTAMP desc
| take 50
```

---

## Antares (App Service) Queries - Different Cluster

> ⚠️ **IMPORTANT**: Antares tables are located in a **DIFFERENT Kusto cluster**, not in APIMTest.

### Antares Kusto Clusters

| Region | Cluster URL | Supported Regions |
|--------|-------------|-------------------|
| West US | `https://wawswus.kusto.windows.net:443` | West US, West US 2, West US 3, BAY, MWH |

> **Note**: Choose the cluster based on the region where the Consumption service is being provisioned. Additional Antares clusters exist for other regions.

### Antares Controller Events - Website Provisioning

Query the AntaresAdminControllerEvents table for detailed controller-level provisioning information:

```kql
// Cluster: https://wawswus.kusto.windows.net (for West US regions)
let startTime = ago(1d);
let endTime = now();
let websiteSubscriptionId = "{websiteSubscriptionId}";
let websiteName = "{websiteName}";
let correlationId = "{correlationId}";
All('AntaresAdminControllerEvents')
| where PreciseTimeStamp between (startTime..endTime)
| where SubscriptionId == websiteSubscriptionId
| where CorrelationRequestId == correlationId
| project TIMESTAMP, Level, ActivityId, Details, Operation, LatencyInMilliseconds, Address, Verb, StatusCode, SubscriptionId, SiteName
| order by TIMESTAMP desc
```

### Antares Geo Events - Website Provisioning

```kql
// Cluster: https://wawswus.kusto.windows.net (for West US regions)
let startTime = ago(1d);
let endTime = now();
let websiteSubscriptionId = "{websiteSubscriptionId}";
let websiteName = "{websiteName}";
let correlationId = "{correlationId}";
All('AntaresAdminGeoEvents')
| where PreciseTimeStamp between (startTime..endTime)
| where SubscriptionId == websiteSubscriptionId
| where CorrelationRequestId == correlationId
| project TIMESTAMP, Level, ActivityId, Details, Exception, Operation, LatencyInMilliseconds, Address, Verb, StatusCode, SubscriptionId, SiteName
| order by TIMESTAMP desc
```

### Antares Controller Events by Website Name

```kql
// Cluster: https://wawswus.kusto.windows.net (for West US regions)
let startTime = ago(2h);
let websiteName = "{websiteName}";
All('AntaresAdminControllerEvents')
| where PreciseTimeStamp > startTime
| where SiteName == websiteName
| project TIMESTAMP, Level, ActivityId, Details, Operation, LatencyInMilliseconds, StatusCode, Verb, Address
| order by TIMESTAMP desc
| take 100
```

### Antares Controller Failures

```kql
// Cluster: https://wawswus.kusto.windows.net (for West US regions)
let startTime = ago(2h);
let websiteSubscriptionId = "{websiteSubscriptionId}";
All('AntaresAdminControllerEvents')
| where PreciseTimeStamp > startTime
| where SubscriptionId == websiteSubscriptionId
| where Level < 3 or StatusCode >= 400
| project TIMESTAMP, Level, Operation, StatusCode, Details, SiteName, Address, Verb
| order by TIMESTAMP desc
| take 50
```

### Antares Geo Events by Website Name

```kql
// Cluster: https://wawswus.kusto.windows.net (for West US regions)
let startTime = ago(2h);
let websiteName = "{websiteName}";
All('AntaresAdminGeoEvents')
| where PreciseTimeStamp > startTime
| where SiteName == websiteName
| project TIMESTAMP, Level, ActivityId, Details, Exception, Operation, LatencyInMilliseconds, StatusCode
| order by TIMESTAMP desc
| take 100
```

### Antares Geo Failures for Subscription

```kql
// Cluster: https://wawswus.kusto.windows.net (for West US regions)
let startTime = ago(2h);
let websiteSubscriptionId = "{websiteSubscriptionId}";
All('AntaresAdminGeoEvents')
| where PreciseTimeStamp > startTime
| where SubscriptionId == websiteSubscriptionId
| where Level < 3 or StatusCode >= 400
| project TIMESTAMP, Level, Operation, StatusCode, Exception, Details, SiteName
| order by TIMESTAMP desc
| take 50
```

---

## SKUv2 Specific Queries

### ManagementKpi - API Performance Metrics

```kql
All('ManagementKpi')
| where PreciseTimeStamp > ago(2h)
| where serviceName == "{serviceName}"
| project PreciseTimeStamp, operationName, statusCode, durationMs, success
| order by PreciseTimeStamp desc
| take 100
```

### ManagementKpi - Failed API Calls

```kql
All('ManagementKpi')
| where PreciseTimeStamp > ago(2h)
| where serviceName == "{serviceName}"
| where success == false or statusCode >= 400
| project PreciseTimeStamp, operationName, statusCode, durationMs, errorMessage
| order by PreciseTimeStamp desc
| take 50
```

### Mapi - Management API Errors

```kql
All('Mapi')
| where PreciseTimeStamp > ago(2h)
| where DeploymentName startswith "{serviceName}"
| where Level < 3
| project PreciseTimeStamp, message, exception, Level, RoleInstance
| order by PreciseTimeStamp desc
| take 50
```

### Mapi - Request Processing Errors

```kql
All('Mapi')
| where PreciseTimeStamp > ago(2h)
| where DeploymentName startswith "{serviceName}"
| where message contains "Exception" or message contains "Error"
| project PreciseTimeStamp, message, exception
| order by PreciseTimeStamp desc
| take 100
```

### ProxyRequest - Gateway Request Errors

```kql
All('ProxyRequest')
| where TIMESTAMP > ago(2h)
| where serviceName == "{serviceName}"
| where statusCode >= 400
| project TIMESTAMP, url, statusCode, exception, correlationId
| order by TIMESTAMP desc
| take 50
```

### ProxyRequest - Request by API

```kql
All('ProxyRequest')
| where TIMESTAMP > ago(2h)
| where serviceName == "{serviceName}"
| summarize 
    total = count(),
    errors = countif(statusCode >= 400),
    avgDuration = avg(durationMs)
    by apiId, bin(TIMESTAMP, 5m)
| order by errors desc
```

### ProxyRequest - Timeout and Slow Requests

```kql
All('ProxyRequest')
| where TIMESTAMP > ago(2h)
| where serviceName == "{serviceName}"
| where durationMs > 10000  // > 10 seconds
| project TIMESTAMP, url, apiId, durationMs, statusCode
| order by durationMs desc
| take 50
```

### SKUv2 Comprehensive Error Query

Join Orchestration with Mapi and ProxyRequest for full picture:

```kql
let svcName = "{serviceName}";
let timeRange = ago(2h);
let orchErrors = All('Orchestration')
| where PreciseTimeStamp > timeRange
| where serviceName == svcName
| where Level < 3
| project Timestamp = PreciseTimeStamp, Source = "Orchestration", Operation = operationName, Message = message, Exception = exception;
let mapiErrors = All('Mapi')
| where PreciseTimeStamp > timeRange
| where DeploymentName startswith svcName
| where Level < 3
| project Timestamp = PreciseTimeStamp, Source = "Mapi", Operation = "", Message = message, Exception = exception;
let proxyErrors = All('ProxyRequest')
| where TIMESTAMP > timeRange
| where serviceName == svcName
| where statusCode >= 500
| project Timestamp = TIMESTAMP, Source = "ProxyRequest", Operation = url, Message = tostring(statusCode), Exception = exception;
union orchErrors, mapiErrors, proxyErrors
| order by Timestamp desc
| take 100
```

---

## RP Controller Errors

```kql
All('HttpIncomingRequests')
| where TIMESTAMP > ago(2h)
| where operationName startswith "ApiService" or operationName startswith "Gateway"
| where responseCode >= 500
| project TIMESTAMP, operationName, responseCode, exception
| summarize count() by operationName, responseCode
| order by count_ desc
```

### Create/Update Operations

```kql
All('Orchestration')
| where PreciseTimeStamp > ago(2h)
| where operationName in ("CreateApiService", "UpdateApiService", "DeleteApiService")
| where Level < 4
| project PreciseTimeStamp, operationName, serviceName, Level, exception
| order by PreciseTimeStamp desc
| take 100
```

### Scale Operations

```kql
All('Orchestration')
| where PreciseTimeStamp > ago(2h)
| where operationName contains "Scale" or operationName contains "Resize"
| where Level < 4
| project PreciseTimeStamp, operationName, serviceName, message, exception
| take 100
```

---

## Backup/Restore Queries

> ⚠️ **Backup Test Operations**: The Backup test performs 3 main operations:
> 1. **Create Database** - Uses COPY AS SQL command with 30-minute timeout
> 2. **Export Contents** - Exports to storage account  
> 3. **Export BacPac** - Exports DB to storage as BacPac file with 1-hour timeout

### Backup Orchestration - Database Creation Issues

Find database creation failures during backup operations by correlating `UpdatingApiServiceContainer` events with failed backup orchestrations:

```kql
let period = 1d;
let svcName = "{serviceName}";  // e.g., 'Int-Premium-abc123'
All('Orchestration')
| where eventType == "UpdatingApiServiceContainer"
| where PreciseTimeStamp > ago(period)
| where serviceName == svcName
| project PreciseTimeStamp, instanceId, eventType, duration, message, serviceName
| order by PreciseTimeStamp desc
| join kind=inner (
    All('Orchestration') 
    | where eventType == "BackupApiServiceOrchestrationFailed" and PreciseTimeStamp > ago(period)
    | where serviceName == svcName
    | project PreciseTimeStamp, instanceId, eventType, message, exception, serviceName
) on instanceId
| extend messageJson = parse_json(message)
| extend region = tostring(messageJson["MasterLocation"])
| project PreciseTimeStamp, region, instanceId, serviceName
| summarize count() by bin(PreciseTimeStamp, 1h), region, serviceName
```

### Backup Orchestration - Export Failures (SQL Import/Export)

Check for export failures by correlating failed backup orchestrations with SQL Import/Export polling status:

```kql
let _startTime = ago(1d);
let _endTime = now();
let clusterName = '{tenant}';  // e.g., 'api-am2-prod-01'
let svcName = "{serviceName}";  // e.g., 'Int-Premium-abc123'
All('OrchestrationKpi')
| where PreciseTimeStamp between (_startTime .. _endTime)
| where Tenant == clusterName
| where resourceName == svcName
| project PreciseTimeStamp, Region, operationStatus, instanceId, resourceName, codeVersion, subscriptionId, exceptionMessage = substring(exception, 0, 600)
| join kind=inner (
    All('Orchestration')
    | where PreciseTimeStamp between (_startTime .. _endTime)
    | where Tenant == clusterName
    | where serviceName == svcName
    | where eventType in ("WaitForSqlImportExportOperationRunning")
    | extend mjson = parse_json(message)
    | extend pollingLocation = tostring(mjson["PollingLocation"])
    | extend requestId = tostring(mjson["AsyncOperation"]["properties"]["requestId"])
    | extend queuedTime = todatetime(mjson["AsyncOperation"]["properties"]["queuedTime"])
    | extend serverName = tostring(mjson["AsyncOperation"]["properties"]["serverName"])
    | extend databaseName = tostring(mjson["AsyncOperation"]["properties"]["databaseName"])
    | extend requestStatus = tostring(mjson["AsyncOperation"]["properties"]["status"])
) on instanceId
| project PreciseTimeStamp, subscriptionId, serviceName, requestId, queuedTime, serverName, databaseName, codeVersion, Tenant, exceptionMessage, requestStatus, pollingLocation
| summarize count(), min(PreciseTimeStamp), max(PreciseTimeStamp) by requestId, queuedTime, Tenant, subscriptionId, serviceName, serverName, databaseName, codeVersion, exceptionMessage
```

### Backup Orchestration - General Failures

Query all backup orchestration failures for a specific service:

```kql
let startTime = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > startTime
| where serviceName == svcName
| where eventType in ("BackupApiServiceOrchestrationFailed", "BackupApiServiceOrchestrationSucceeded", "BackupApiServiceOrchestrationStarted")
| project PreciseTimeStamp, instanceId, eventType, message, exception, Level
| order by PreciseTimeStamp desc
| take 100
```

### Backup Orchestration - By Region Summary

Summarize backup failures by region to identify regional issues:

```kql
let period = 1d;
All('OrchestrationKpi')
| where resourceType == "service"
| where PreciseTimeStamp > period
| where orchestrationName == "BackupApiService" and operationStatus  != "Starting"
| where isempty(_sku) or sku in (_sku)
| where operationOwner in (opOwner) or isempty(opOwner)
| summarize Total = count(),
            SuccessfulActivations = countif(operationStatus == "Success") by sku, Region, bin(PreciseTimeStamp, 1h)
| extend SLA = round((todouble(SuccessfulActivations * 100) / Total), 5)
| project PreciseTimeStamp,  SLA, Region
```

### Restore Orchestration - General Failures

Query restore orchestration failures:

```kql
let startTime = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > startTime
| where serviceName == svcName
| where eventType contains "RestoreApiService"
| project PreciseTimeStamp, instanceId, eventType, message, exception, Level
| order by PreciseTimeStamp desc
| take 100
```

---

## Configuration Service Queries

### CfgSvc Errors

```kql
All('CfgSvcRequestTrace')
| where TIMESTAMP > ago(2h)
| where serviceName == "{serviceName}"
| where Level < 3
| project TIMESTAMP, eventType, operationName, exception
| order by TIMESTAMP desc
| take 50
```

### Configuration Sync Issues

```kql
All('CfgSvcRequestTrace')
| where TIMESTAMP > ago(2h)
| where eventType in ("SyncStarted", "SyncCompleted", "SyncFailed")
| where serviceName == "{serviceName}"
| project TIMESTAMP, eventType, operationName, message
| order by TIMESTAMP desc
| take 100
```

---

## Gateway Control Plane Queries

### Control Plane Failures

```kql
All('GatewayControlPlaneRequests')
| where TIMESTAMP > ago(2h)
| where serviceName == "{serviceName}"
| where success == false
| project TIMESTAMP, operation, errorMessage, statusCode
| take 50
```

### Gateway Deployment Status

```kql
All('GatewayControlPlaneRequests')
| where TIMESTAMP > ago(2h)
| where operation contains "Deploy" or operation contains "Provision"
| where serviceName == "{serviceName}"
| project TIMESTAMP, operation, success, errorMessage
| order by TIMESTAMP desc
| take 50
```

---

## Test-Specific Queries

### Find Service by Test Run Time

If you know the approximate test run time:

```kql
let testTime = datetime({timestamp});
All('Orchestration')
| where PreciseTimeStamp between (testTime - 10m .. testTime + 30m)
| where serviceName startswith "apim-" or serviceName startswith "test-"
| where Level < 3
| project PreciseTimeStamp, serviceName, operationName, exception
| order by PreciseTimeStamp desc
| take 100
```

### Correlation by Activity ID

If you have a correlation/activity ID from logs:

```kql
let activityId = "{activityId}";
union 
    (All('Orchestration') | where RelatedActivityId == activityId),
    (All('HttpIncomingRequests') | where correlationId == activityId)
| order by PreciseTimeStamp desc
| project PreciseTimeStamp, operationName, Level, exception
| take 100
```

---

## Aggregation Queries

### Error Summary by Operation

```kql
All('Orchestration')
| where PreciseTimeStamp > ago(2h)
| where Level < 3
| summarize 
    errorCount = count(),
    distinctServices = dcount(serviceName)
    by operationName
| order by errorCount desc
| take 20
```

### Error Trends Over Time

```kql
All('Orchestration')
| where PreciseTimeStamp > ago(6h)
| where Level < 3
| summarize errorCount = count() by bin(PreciseTimeStamp, 10m)
| order by PreciseTimeStamp asc
| render timechart
```

---

## SKUv1 Queries (Classic Platform - Bootstrapper Tables)

> ⚠️ **SKUv1 ONLY**: The following queries use Bootstrapper tables (ApiSvcHost, DscLogs, MicrosoftWindowsDscEvents, ProxyInfra, MapiInfra, Integration, ApplicationEvents) which are only relevant for SKUv1 test investigation. Do NOT use these tables for SKUv2/Consumption/PremiumV2 tests.

### Orchestration + Bootstrapper Join Queries

Join Orchestration logs with Bootstrapper component tables for deeper SKUv1 diagnostics.

### Orchestration with ApiSvcHost Logs (SKUv1)

```kql
let timeRange = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > timeRange
| where serviceName == svcName
| where Level < 3
| project OrchTimestamp = PreciseTimeStamp, operationName, orchestrationException = exception, serviceName
| join kind=inner (
    All('ApiSvcHost')
    | where PreciseTimeStamp > timeRange
    | where DeploymentName startswith svcName
    | project ApiSvcTimestamp = PreciseTimeStamp, ApiSvcMessage = message, ApiSvcException = exception, DeploymentName, RoleInstance
) on $left.serviceName == $right.DeploymentName
| where abs(datetime_diff('second', OrchTimestamp, ApiSvcTimestamp)) < 60
| project OrchTimestamp, operationName, orchestrationException, ApiSvcTimestamp, ApiSvcMessage, ApiSvcException, RoleInstance
| order by OrchTimestamp desc
| take 100
```

### Orchestration with ProxyInfra Logs (SKUv1)

```kql
let timeRange = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > timeRange
| where serviceName == svcName
| where Level < 3
| project OrchTimestamp = PreciseTimeStamp, operationName, orchestrationException = exception, serviceName
| join kind=inner (
    All('ProxyInfra')
    | where PreciseTimeStamp > timeRange
    | where DeploymentName startswith svcName
    | where Level < 3
    | project ProxyTimestamp = PreciseTimeStamp, ProxyMessage = message, ProxyException = exception, DeploymentName, RoleInstance
) on $left.serviceName == $right.DeploymentName
| where abs(datetime_diff('second', OrchTimestamp, ProxyTimestamp)) < 60
| project OrchTimestamp, operationName, orchestrationException, ProxyTimestamp, ProxyMessage, ProxyException, RoleInstance
| order by OrchTimestamp desc
| take 100
```

### Orchestration with MapiInfra Logs (SKUv1)

```kql
let timeRange = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > timeRange
| where serviceName == svcName
| where Level < 3
| project OrchTimestamp = PreciseTimeStamp, operationName, orchestrationException = exception, serviceName
| join kind=inner (
    All('MapiInfra')
    | where PreciseTimeStamp > timeRange
    | where DeploymentName startswith svcName
    | where Level < 3
    | project MapiInfraTimestamp = PreciseTimeStamp, MapiInfraMessage = message, MapiInfraException = exception, DeploymentName, RoleInstance
) on $left.serviceName == $right.DeploymentName
| where abs(datetime_diff('second', OrchTimestamp, MapiInfraTimestamp)) < 60
| project OrchTimestamp, operationName, orchestrationException, MapiInfraTimestamp, MapiInfraMessage, MapiInfraException, RoleInstance
| order by OrchTimestamp desc
| take 100
```

### Orchestration with Integration Logs (SKUv1)

```kql
let timeRange = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > timeRange
| where serviceName == svcName
| where Level < 3
| project OrchTimestamp = PreciseTimeStamp, operationName, orchestrationException = exception, serviceName
| join kind=inner (
    All('Integration')
    | where PreciseTimeStamp > timeRange
    | where DeploymentName startswith svcName
    | where Level < 3
    | project IntegrationTimestamp = PreciseTimeStamp, IntegrationMessage = message, IntegrationException = exception, DeploymentName, RoleInstance
) on $left.serviceName == $right.DeploymentName
| where abs(datetime_diff('second', OrchTimestamp, IntegrationTimestamp)) < 60
| project OrchTimestamp, operationName, orchestrationException, IntegrationTimestamp, IntegrationMessage, IntegrationException, RoleInstance
| order by OrchTimestamp desc
| take 100
```

### Orchestration with ApplicationEvents (SKUv1)

```kql
let timeRange = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > timeRange
| where serviceName == svcName
| where Level < 3
| project OrchTimestamp = PreciseTimeStamp, operationName, orchestrationException = exception, serviceName
| join kind=inner (
    All('ApplicationEvents')
    | where PreciseTimeStamp > timeRange
    | where DeploymentName startswith svcName
    | where Level < 3
    | project AppEventTimestamp = PreciseTimeStamp, AppEventMessage = message, AppEventException = exception, DeploymentName, RoleInstance
) on $left.serviceName == $right.DeploymentName
| where abs(datetime_diff('second', OrchTimestamp, AppEventTimestamp)) < 60
| project OrchTimestamp, operationName, orchestrationException, AppEventTimestamp, AppEventMessage, AppEventException, RoleInstance
| order by OrchTimestamp desc
| take 100
```

### Orchestration with DSC Events (SKUv1)

```kql
let timeRange = ago(2h);
let svcName = "{serviceName}";
All('Orchestration')
| where PreciseTimeStamp > timeRange
| where serviceName == svcName
| where Level < 3
| project OrchTimestamp = PreciseTimeStamp, operationName, orchestrationException = exception, serviceName
| join kind=inner (
    All('MicrosoftWindowsDscEvents')
    | where PreciseTimeStamp > timeRange
    | where DeploymentName startswith svcName
    | project DscTimestamp = PreciseTimeStamp, DscMessage = Message, DeploymentName, RoleInstance
) on $left.serviceName == $right.DeploymentName
| where abs(datetime_diff('second', OrchTimestamp, DscTimestamp)) < 60
| project OrchTimestamp, operationName, orchestrationException, DscTimestamp, DscMessage, RoleInstance
| order by OrchTimestamp desc
| take 100
```

### DscLogs - DSC Execution Details (SKUv1)

```kql
All('DscLogs')
| where PreciseTimeStamp > ago(2h)
| where DeploymentName startswith "{serviceName}"
| where Level < 3
| project PreciseTimeStamp, JobId, Message, Exception, DeploymentName, RoleInstance
| order by PreciseTimeStamp desc
| take 100
```

### SKUv1 Comprehensive Multi-Table Join

Join Orchestration errors with ALL Bootstrapper tables for complete SKUv1 diagnostics:

```kql
let timeRange = ago(2h);
let svcName = "{serviceName}";
let orchErrors = All('Orchestration')
| where PreciseTimeStamp > timeRange
| where serviceName == svcName
| where Level < 3
| project OrchTimestamp = PreciseTimeStamp, operationName, orchestrationException = exception, serviceName;
// Union all SKUv1 bootstrapper logs for the same service
let bootstrapperLogs = union
    (All('ApiSvcHost') | where PreciseTimeStamp > timeRange | where DeploymentName startswith svcName | where Level < 3 | project Timestamp = PreciseTimeStamp, Source = "ApiSvcHost", Message = message, Exception = exception, DeploymentName, RoleInstance),
    (All('ProxyInfra') | where PreciseTimeStamp > timeRange | where DeploymentName startswith svcName | where Level < 3 | project Timestamp = PreciseTimeStamp, Source = "ProxyInfra", Message = message, Exception = exception, DeploymentName, RoleInstance),
    (All('MapiInfra') | where PreciseTimeStamp > timeRange | where DeploymentName startswith svcName | where Level < 3 | project Timestamp = PreciseTimeStamp, Source = "MapiInfra", Message = message, Exception = exception, DeploymentName, RoleInstance),
    (All('Integration') | where PreciseTimeStamp > timeRange | where DeploymentName startswith svcName | where Level < 3 | project Timestamp = PreciseTimeStamp, Source = "Integration", Message = message, Exception = exception, DeploymentName, RoleInstance),
    (All('ApplicationEvents') | where PreciseTimeStamp > timeRange | where DeploymentName startswith svcName | where Level < 3 | project Timestamp = PreciseTimeStamp, Source = "ApplicationEvents", Message = message, Exception = exception, DeploymentName, RoleInstance),
    (All('MicrosoftWindowsDscEvents') | where PreciseTimeStamp > timeRange | where DeploymentName startswith svcName | project Timestamp = PreciseTimeStamp, Source = "DscEvents", Message = Message, Exception = "", DeploymentName, RoleInstance),
    (All('DscLogs') | where PreciseTimeStamp > timeRange | where DeploymentName startswith svcName | where Level < 3 | project Timestamp = PreciseTimeStamp, Source = "DscLogs", Message = Message, Exception = Exception, DeploymentName, RoleInstance);
orchErrors
| join kind=inner bootstrapperLogs on $left.serviceName == $right.DeploymentName
| where abs(datetime_diff('second', OrchTimestamp, Timestamp)) < 60
| project OrchTimestamp, operationName, orchestrationException, BootstrapperTimestamp = Timestamp, Source, Message, Exception, RoleInstance
| order by OrchTimestamp desc, BootstrapperTimestamp desc
| take 200
```

---

## SKUv1 Bootstrapper Tables Reference

> ⚠️ **SKUv1 ONLY**: These tables are only populated for SKUv1 (classic) services.

| Table | All() Reference | Purpose |
|-------|-----------------|---------|
| `ApiSvcHost` | `All('ApiSvcHost')` | API Service host process logs |
| `ProxyInfra` | `All('ProxyInfra')` | Proxy/Gateway infrastructure logs |
| `MapiInfra` | `All('MapiInfra')` | Management API infrastructure logs |
| `MicrosoftWindowsDscEvents` | `All('MicrosoftWindowsDscEvents')` | DSC (Desired State Configuration) events |
| `DscLogs` | `All('DscLogs')` | DSC execution logs |
| `Integration` | `All('Integration')` | Integration component logs |
| `ApplicationEvents` | `All('ApplicationEvents')` | General application events |

---

## Using with apim-kusto-agent

Invoke queries through the `apim-kusto-agent`:

```
Use the apim-kusto-agent to run this query:
{paste query here}
```

The agent is configured for APIMTest database by default.

---

## Common Filters

### Time Ranges
- Last hour: `ago(1h)`
- Last 2 hours: `ago(2h)`
- Last day: `ago(1d)`
- Specific time: `datetime(2026-01-30T10:00:00Z)`

### Log Levels
- `Level < 2`: Error only
- `Level < 3`: Error + Warning
- `Level < 4`: Error + Warning + Info

### Service Name Patterns
- Test services often start with: `apim-`, `test-`, `int-`
- Look for patterns in build logs to find exact service name
