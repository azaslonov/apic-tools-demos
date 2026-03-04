# Kusto Queries for APIM SKUv1 Investigation

This reference contains commonly used Kusto queries for investigating APIM SKUv1 incidents.

## Context Budget Note

**Always limit query results** to stay within the 100K token budget:
- Use `| take 50` for exploratory queries
- Use `| top 100 by PreciseTimeStamp desc` for time-ordered results
- Use `| summarize` to aggregate instead of returning raw rows
- Prefer 1h time windows; use 6h only when necessary

## Cluster and Database

- **Cluster**: `apim.kusto.windows.net`
- **Database**: `APIMProd`

## Service Information Queries

### Get Service Configuration
```kusto
GetTenantVersions
| where serviceName =~ "{service-name}"
| project serviceName, State, sku, skuUnitCount, vpn, isVmss, version, sdpStage, Region
```

### Get VM/Instance Map
```kusto
GetApiServiceVmMap("{service-name}")
| project skuType, skuUnitCount, vmMap, HealthStatus, Region
```

### Get Tenant and RoleInstance Identifiers
```kusto
All('ApiSvcHost')
| where DeploymentName == "{service-name}.azure-api.net"
| where PreciseTimeStamp > ago(1d)
| summarize by Tenant, RoleInstance
```

## Event and Error Queries

### Role Events Around Incident Time
```kusto
All('ApiSvcHost')
| where DeploymentName startswith "{service-name}"
| where PreciseTimeStamp between(datetime({start-time})..1h)
| where eventType contains "Role" or eventType startswith "Host"
| project PreciseTimeStamp, RoleInstance, eventType, Level, message, exception
| order by PreciseTimeStamp desc
| take 100
```

### All Exceptions from Service (Multi-source)
```kusto
let period = 1h;
let start = ago(period);
let tenant = "{service-name}";
let maxLevel = 3;
(All('ApiSvcHost') | extend t = "ApiSvcHost")
| union (All('ProxyInfra') | extend t = "ProxyInfra")
| union (All('ProxyKpiRaw') | extend t = "ProxyKpiRaw")
| union (All('Mapi') | extend t = "Mapi")
| union (All('MapiInfra') | extend t = "MapiInfra")
| union (All('ManagementKpi') | extend t = "ManagementKpi")
| union (All('Integration') | extend t = "Integration")
| union (All('Portal') | extend t = "Portal")
| union (All('MessagingWorker') | extend t = "MessagingWorker")
| union (All('Orchestration') | extend t = "Orchestration")
| where DeploymentName startswith tenant and TIMESTAMP between(start..period) and Level <= maxLevel
| where eventType !contains "redis"
| project PreciseTimeStamp, t, eventType, Level, message, exception, RoleInstance
| order by PreciseTimeStamp desc
| take 100
```

### Health Monitor Events
```kusto
All('Orchestration')
| where PreciseTimeStamp > ago(6h)
| where eventType == "HealthMonitorServiceInBadState" and serviceName == "{service-name}"
| summarize count(), min(PreciseTimeStamp), max(PreciseTimeStamp), max(duration) by Level, eventType, message, exception
```

### Correlated Events Across Tables
```kusto
find withsource = SourceTable in (All('ApiSvcHost'), All('ProxyInfra'), All('Portal'), All('Orchestration'), All('ManagementKpi'), All('MapiInfra'), All('Mapi'))
| where PreciseTimeStamp >= ago(6h)
| extend tenant = "{service-name}"
| extend Ago = format_timespan(now() - PreciseTimeStamp, 'hh:mm:ss')
| where Level <= 3
| where DeploymentName contains tenant or serviceName == tenant
| project SourceTable, PreciseTimeStamp, Ago, Level, eventType, message, exception, Region, RoleInstance
| order by PreciseTimeStamp desc
| take 100
```

## VMSS and Infrastructure Queries

### VMSS Events (AzureCM Cluster)
```kusto
cluster('azurecm').database('AzureCM').TMMgmtSlaMeasurementEventEtwTable
| where TenantName == "{tenant-id}"
| where PreciseTimeStamp >= ago(2d)
| project PreciseTimeStamp, RoleInstanceID, RoleInstanceName, Context, EntityState, Detail0, NodeID, Level
| order by PreciseTimeStamp desc
| take 100
```

### VMSS Events for Specific Instance
```kusto
let _tenantName = "{tenant-id}";
let _roleInstanceName1 = "{instance-1}";
let _roleInstanceName2 = "{instance-2}";
cluster('azurecm').database('AzureCM').TMMgmtSlaMeasurementEventEtwTable
| where PreciseTimeStamp > ago(7d)
| where TenantName == _tenantName
| where RoleInstanceName contains _roleInstanceName1 or RoleInstanceName contains _roleInstanceName2
| project PreciseTimeStamp, Context, EntityState, RoleInstanceName
| order by PreciseTimeStamp desc
| take 100
```

## Upgrade and Deployment Queries

### Global Upgrade Progress
```kusto
All('Orchestration')
| where PreciseTimeStamp > ago(1d)
| where instanceId contains "System_GlobalUpgrade_{instance-id}"
| where eventType in (
    "GlobalUpgradeOrchestrationUpgradingApiService",
    "GlobalUpgradeOrchestrationUpgradedApiService",
    "GlobalUpgradeOrchestrationFailedToUpgradeApiService",
    "UpgradeOrchestrationSucceeded",
    "GlobalUpgradeOrchestrationCompletedErrorSummary"
)
| summarize count() by eventType
```

### Upgrade Errors
```kusto
All('Orchestration')
| where PreciseTimeStamp > ago(12h)
| where instanceId contains "System_GlobalUpgrade_{instance-id}"
| where eventType == "GlobalUpgradeOrchestrationCompletedErrorSummary"
```

### Version Distribution
```kusto
GetTenantVersionDistribution()
```

## Availability and Performance Queries

### Logs Not Coming (Identify Missing Instances)
```kusto
All('ApiSvcHost')
| where DeploymentName == "{service-name}.azure-api.net"
| where PreciseTimeStamp between(datetime({date})..1d)
| summarize by Tenant, RoleInstance
```

### Service Operations Timeline
```kusto
All('Orchestration')
| where serviceName =~ "{service-name}"
| where PreciseTimeStamp > ago(7d)
| where eventType has_any ("Activate", "Update", "Scale", "Upgrade", "Terminate")
| project PreciseTimeStamp, eventType, message, duration, exception
| order by PreciseTimeStamp desc
| take 50
```

## Quick Diagnostic Queries

### Is Service Healthy?
```kusto
GetApiServiceVmMap("{service-name}")
| project HealthStatus, vmMap, skuUnitCount
```

### Recent Errors (Last Hour)
```kusto
All('ApiSvcHost')
| where DeploymentName contains "{service-name}"
| where PreciseTimeStamp > ago(1h)
| where Level <= 2
| summarize count() by eventType, bin(PreciseTimeStamp, 5m)
| render timechart
```

### Check if Service is VNET-enabled
```kusto
GetTenantVersions
| where serviceName =~ "{service-name}"
| project serviceName, vpn
| where vpn != "None"
```
