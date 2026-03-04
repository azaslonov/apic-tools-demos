---
name: skill-apim-skuv1-investigator
description: |
  Investigate ICM incidents for Azure API Management SKU v1 (Dedicated/Classic) services using a structured,
  hypothesis-driven approach. Use when you need to:
  - Analyze ICM incidents related to APIM SKUv1 services (Developer, Basic, Standard, Premium tiers)
  - Investigate health monitoring alerts (Gateway, Portal, Proxy, SMAPI issues)
  - Troubleshoot service availability, VM/VMSS issues, and deployment failures
  - Query Kusto telemetry (APIMProd) for runtime diagnostics
  - Perform root cause analysis for service outages
  - Determine mitigation actions (reboot, reimage, rebuild, rollback)
  - Escalate to appropriate teams (Platform, Gateway, Portal)
  
  **SKU Identification**: SKUv1 includes Developer, Basic, Standard, Premium tiers running on VMSS.
  SKUv2 includes BasicV2, StandardV2, PremiumV2 running on App Service - use separate TSGs for those.
  
  Triggers: "ICM incident", "investigate APIM", "SKUv1 issue", "dedicated service", "health monitoring alert",
  "gateway not reachable", "service in bad state", "VMSS issue", "RP health alert", incident IDs
max_context_tokens: 100000
---

# APIM SKUv1 ICM Investigator

A structured approach to investigating ICM incidents for Azure API Management SKUv1 (Dedicated/Classic) services.

## Context Budget Guidelines

**Max Context**: 100,000 tokens

To stay within budget:
- **Kusto queries**: Limit results with `| take 50` or `| top 100 by ...`
- **Log fetching**: Request specific time windows (≤1h for detailed, ≤6h for overview)
- **ICM data**: Use AI summary instead of full incident context when possible
- **Avoid**: Fetching full stack traces for all instances; sample 1-2 representative ones

## How to Use

### Investigate an ICM incident
```
Investigate ICM incident 503176286 for APIM service ApiM-Prd-Us-Sales-B2C-Public
```

### Analyze health monitoring alert
```
Why is the health monitor showing "HealthMonitorServiceInBadState" for service contoso-api?
```

### Gateway availability investigation
```
Gateway is not reachable for service mycompany-api. Help me investigate.
```

---

## Phase 0: Incident Classification (MANDATORY FIRST STEP)

### Determine SKU Type

Before investigating, verify this is a SKUv1 service:

1. **Check ASI**:
   - SKUv1: `https://asi.azure.ms/services/APIM/pages/Service?serviceName={service-name}`
   - SKUv2: `https://asi.azure.ms/services/APIM/pages/Servicev2?serviceName={service-name}`

2. **Run Kusto query**:
```kusto
GetTenantVersions
| where serviceName =~ "{service-name}"
| project serviceName, sku, State, vpn, isVmss, version, sdpStage
```

**SKUv1 indicators**: sku is Developer, Basic, Standard, or Premium (without V2 suffix)
**SKUv2 indicators**: sku contains "V2" → Use [SKUv2 TSG](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/skuv2/)

### Classify Alert Type

| Alert Pattern | Category | Primary TSG |
|---------------|----------|-------------|
| HealthMonitorServiceInBadState | Service Health | See [Health Monitor TSG](#health-monitor-service-in-bad-state) |
| Gateway for {SKU} Tenant | Gateway Availability | See [Gateway Availability](#gateway-availability) |
| Portal for {SKU} Tenant | Developer Portal | See [Portal Issues](#developer-portal-issues) |
| Proxy for {SKU} Tenant | Proxy/Gateway | See [Gateway Availability](#gateway-availability) |
| DSC Extension Failure | VM Configuration | See [DSC Extension](#dsc-extension-failures) |
| VMSS Deployment Failed | Deployment | See [VMSS Issues](#vmss-issues) |

---

## Phase 1: Gather Service Context

### Step 1: Get Service Information

**Health status endpoint**:
```
https://{service-name}.azure-api.net/internal-status-0123456789abcdef
```

**Expected response** (healthy service):
```json
{
    "StatusCode": 200,
    "Message": "Service operational",
    "Instance": "gwhost_4",
    "SkuType": "Basic",
    "SkuCount": "1",
    "RuntimeVersion": "0.44.18652.0"
}
```

**Kusto - Service details**:
```kusto
GetTenantVersions
| where serviceName =~ "{service-name}"
| project State, sku, vpn, isVmss, version, sdpStage, skuUnitCount
```

**Key fields to check**:
- `State`: Should be `Active`. `Upgrading` may be within SLA for single-instance SKUs
- `vpn`: If not `None`, service is in VNET → follow VNET TSG
- `isVmss`: Deployment type (VMSS vs legacy Cloud Service)

### Step 2: Get VM/Instance Information

**VM Map query**:
```kusto
GetApiServiceVmMap("{service-name}")
| project skuType, skuUnitCount, vmMap, HealthStatus
```

**Get Tenant and RoleInstance identifiers**:
```kusto
All('ApiSvcHost')
| where DeploymentName == "{service-name}.azure-api.net"
| where PreciseTimeStamp > ago(1d)
| summarize by Tenant, RoleInstance
```

### Step 3: Check for Recent Events

**Role events around incident time**:
```kusto
All('ApiSvcHost')
| where DeploymentName startswith "{service-name}"
| where PreciseTimeStamp between(datetime({incident-time})..1h)
| where eventType contains "Role" or eventType startswith "Host"
| project PreciseTimeStamp, RoleInstance, eventType, Level, message, exception
| order by PreciseTimeStamp desc
| take 100
```

**All exceptions from service**:
```kusto
let period = 1h;
let start = ago(period);
let tenant = "{service-name}";
let maxLevel = 3;
(All('ApiSvcHost') | extend t = "ApiSvcHost")
| union (All('ProxyInfra') | extend t = "ProxyInfra")
| union (All('Mapi') | extend t = "Mapi")
| union (All('MapiInfra') | extend t = "MapiInfra")
| union (All('Portal') | extend t = "Portal")
| union (All('Orchestration') | extend t = "Orchestration")
| where DeploymentName startswith tenant and TIMESTAMP between(start..period) and Level <= maxLevel
| project PreciseTimeStamp, t, eventType, message, exception, RoleInstance
| order by PreciseTimeStamp desc
| take 100
```

---

## Phase 2: Hypothesis-Driven Investigation

### Common Root Causes (Ranked by Frequency)

| # | Hypothesis | Indicators | Validation |
|---|------------|------------|------------|
| 1 | Service upgrade in progress | State=Upgrading, recent deployment | Check service operations in ASI |
| 2 | VNET configuration issue | vpn != None, DNS failures | Run nslookup, check VNET TSG |
| 3 | VM/VMSS issue | Role state changes, unhealthy instances | Check VMSS history, AzureCM |
| 4 | Resource exhaustion (CPU/Memory) | High CPU, low available memory | Check Jarvis Service Health Dashboard |
| 5 | DNS not registered | nslookup fails | Run `nslookup {service}.azure-api.net` |
| 6 | Certificate issue | SSL errors, missing certificate | Check SslLabs |
| 7 | Storage throttling | Storage exceptions in logs | Check storage metrics |
| 8 | Recent release regression | Failures after upgrade | Check version, sdpStage |

### Investigation Decision Tree

```
1. Is service in VNET?
   YES → Follow VNET TSG
   NO → Continue

2. Is State = "Upgrading"?
   YES → Wait for upgrade (1 hour for Basic SKU)
   NO → Continue

3. Are VMs healthy?
   NO → Check VMSS history, try reboot/reimage
   YES → Continue

4. Is CPU/Memory exhausted?
   YES → Check which process, consider scale-out
   NO → Continue

5. Is DNS resolving?
   NO → Engage Platform team
   YES → Continue

6. Recent release/upgrade?
   YES → Consider rollback
   NO → Engage Gateway/Platform team
```

---

## Phase 3: Specific Alert Investigations

### Health Monitor Service in Bad State

**Common causes**:
- VNET settings blocking OS upgrade completion
- VM in bad state after reboot
- Network/VM infrastructure issues

**Step 1: Try reboot → reimage → rebuild**

Use Jarvis Action: [Reboot/Reimage Hosted Service](https://jarvis-west.dc.ad.msft.net/5DF5BE37)

**Step 2: Check Orchestration exceptions**
```kusto
All('Orchestration')
| where PreciseTimeStamp > ago(6h)
| where eventType == "HealthMonitorServiceInBadState" and serviceName == "{service-name}"
| summarize count(), min(PreciseTimeStamp), max(PreciseTimeStamp) by Level, eventType, message, exception
```

**Step 3: Check AzureCM for VM events**
```kusto
cluster('azurecm').database('AzureCM').TMMgmtSlaMeasurementEventEtwTable
| where TenantName == "{tenant-id}"
| where PreciseTimeStamp >= ago(2d)
| project PreciseTimeStamp, RoleInstanceID, RoleInstanceName, Context, EntityState, NodeID, Level
| order by PreciseTimeStamp desc
| take 100
```

### Gateway Availability

**Quick triage checklist**:
1. Gateway inside VNet? → Check ASI > Service Info > VNet Type
2. Single VM instance? → Check ASI > Requests per VM
3. Gateway overloaded? → Check ASI > SkuV1 CPU per Machine
4. Deployment failure? → Check ASI > Service Operations
5. Recent upgrade? → Check ASI > Service Operations
6. DNS not registered? → Run `nslookup {service-name}.azure-api.net`
7. Missing certificate? → Check [SslLabs](https://www.ssllabs.com/ssltest)

**NSLookup validation**:
```
nslookup {service-name}.azure-api.net
```
Expected: `{unique-id}.{region}.cloudapp.azure.com` with trafficmanager.net alias

### VMSS Issues

**Check VMSS events**:
```kusto
let _tenantName = "{tenant-id}";
let _roleInstanceName = "{instance-name}";
cluster('azurecm').database('AzureCM').TMMgmtSlaMeasurementEventEtwTable
| where PreciseTimeStamp > ago(7d)
| where TenantName == _tenantName
| where RoleInstanceName contains _roleInstanceName
| project PreciseTimeStamp, Context, EntityState, RoleInstanceName
| order by PreciseTimeStamp desc
| take 100
```

**Look for patterns**:
- `RoleStateStarted` → `RoleStateDestroyed` cycling = VM instability
- Extended time in non-Running states = deployment issues

### DSC Extension Failures

**Reference**: [DSC Extension Failures Wiki](https://supportability.visualstudio.com/AzureAutomation/_wiki/wikis/Azure-Automation.wiki/217974/Windows-DSC-Extension-Failures)

**ICM escalation template**: [Product Team Escalation](https://supportability.visualstudio.com/AzureAutomation/_wiki/wikis/Azure-Automation.wiki/23864/Product-Team-Escalation)

### Developer Portal Issues

**Severity note**: If alert is for Developer Portal and ASI shows "Has published version" = `false`, can downgrade to Sev3.

**Reference TSGs**:
- [Developer portal high failure rate](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/portal/skuv1-developer-portal-failure-per-service)
- [DeveloperPortal Failures](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/portal/portal-cant-start-with-non-transient-error-systemwebhttpexception-0x80004005)

---

## Phase 4: Mitigation Actions

### Immediate Actions (In Order)

| Action | When to Use | Tool |
|--------|-------------|------|
| **Reboot** | VM stuck, process hang | Jarvis Action |
| **Reimage** | Reboot didn't help, OS corruption suspected | Jarvis Action |
| **Rebuild** | Reimage didn't help, need fresh VM | Jarvis Action |
| **Scale out** | Resource exhaustion | Azure Portal (customer) |
| **Rollback** | Recent release caused regression | See Rollback TSGs |

### Jarvis Actions

**Reboot/Reimage/Rebuild**:
[Jarvis Action: Manage Hosted Service](https://jarvis-west.dc.ad.msft.net/5DF5BE37)

Parameters:
- `HostedServiceOperation`: Reboot | Reimage | Rebuild
- `ApiServiceName`: {service-name}
- `RoleInstanceNames`: {instance-name}

### Rollback Options

| Component | Rollback TSG |
|-----------|-------------|
| Dedicated SKUv1 | [Dedicated SKUv1 Rollback](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/buildanddeploy/publictargetedupgrades) |
| Developer Portal | [Rollback Developer Portal](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/portal/rollback-developer-portal-version) |
| ARM Manifest | [ARM Manifest Rollback](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/resourceprovider/arm-manifest-rollback) |

---

## Phase 5: Escalation

### Team Contacts

| Area | Team | Teams Channel |
|------|------|---------------|
| VM/VMSS/Infrastructure | Platform | [Platform Channel](https://teams.microsoft.com/l/channel/19%3Abb8c347362bf41ddb2ab77be2c936437%40thread.skype/Platform) |
| Gateway/Proxy | Gateway | [Gateway Engineering](https://teams.microsoft.com/l/channel/19%3Ae879e4306b554fbea5e28287db9dff3e%40thread.skype/Gateway%20Engineering) |
| Developer Portal | Portal | [Portal Channel](https://teams.microsoft.com/l/channel/19%3A848d42faeb96436994d004cc9334a7b1%40thread.skype/SLOOP) |
| Control Plane/RP | RP | [RP Channel](https://teams.microsoft.com/l/channel/19%3A848d42faeb96436994d004cc9334a7b1%40thread.skype/SLOOP) |

### Escalation Order

1. **During business hours**: Post in relevant Teams channel
2. **Any time**: Contact Incident Manager for context and mitigation know-how
3. **If IM unavailable**: Contact RA responsible member from the owning team

### External Escalations

**Cloud Services/VM issues** (after reboot/reimage/rebuild fail):
- Engage Guest Agent/CM team
- Provide orchestration logs and current role state
- Reference ongoing issues: Check for related ICM incidents

---

## Key Dashboards & Tools

| Tool | Purpose | Link |
|------|---------|------|
| **ASI** | Service health overview | [SKUv1](https://asi.azure.ms/services/APIM/pages/Service?serviceName={name}) |
| **Service Health Dashboard** | CPU, Memory, Capacity | [Jarvis Dashboard](https://portal.microsoftgeneva.com/dashboard/ApiManagementProd/Proxy/Service%2520Health%2520Monitoring%2520DashBoard) |
| **Kusto** | Telemetry queries | [APIMProd](https://dataexplorer.azure.com/clusters/apim/databases/APIMProd) |
| **Jarvis Actions** | Reboot/Reimage/Rebuild | [Manage Hosted Service](https://jarvis-west.dc.ad.msft.net/5DF5BE37) |
| **Lens Dashboard** | Release status | [Release Dashboard](https://lens.msftcloudes.com/#/dashboard/baebafd2-56a0-4cb4-8859-936acd17d36f) |

---

## Output Format

```markdown
# ICM Investigation Report

**Incident ID**: [ICM ID]
**Service Name**: [service-name]
**SKU**: [SKU type]
**Severity**: [Sev level]
**Investigated**: [timestamp]

---

## Service Context

| Property | Value |
|----------|-------|
| State | [Active/Upgrading/etc] |
| SKU | [Developer/Basic/Standard/Premium] |
| Units | [count] |
| VNET | [None/Internal/External] |
| Version | [version] |
| Region | [region] |

---

## Investigation Summary

### Symptoms
- [Symptom 1]
- [Symptom 2]

### Hypotheses Evaluated

| Hypothesis | Status | Evidence |
|------------|--------|----------|
| [Hypothesis 1] | ✅ Confirmed / ❌ Ruled Out | [Evidence] |

### Root Cause

**Identified Cause**: [Clear statement]
**Confidence**: High / Medium / Low

---

## Mitigation

**Actions Taken**:
1. [Action 1]
2. [Action 2]

**Result**: [Mitigated / Escalated / Pending]

---

## Next Steps

1. [Follow-up action]
2. [Monitoring recommendation]
```

---

## MCP Tools Used

| Tool | Purpose |
|------|---------|
| `mcp_icm_get_incident_details_by_id` | Get ICM incident details |
| `mcp_icm_get_ai_summary` | Get incident AI summary |
| `mcp_icm_get_incident_context` | Get full incident context |
| `mcp_icm_get_similar_incidents` | Find similar past incidents |
| `mcp_icm_get_mitigation_hints` | Get suggested mitigations |
| `mcp_azure-kusto-m_execute_query` | Run Kusto queries on APIMProd |
| `mcp_icm_get_impacted_services_regions_clouds` | Get affected scope |

---

## Quick Reference: Kusto Functions

| Function | Purpose |
|----------|---------|
| `GetTenantVersions` | Service configuration and state |
| `GetApiServiceVmMap("{name}")` | VM/instance mapping |
| `GetTenantVersionDistribution()` | Version distribution across fleet |
| `All('ApiSvcHost')` | Host-level events |
| `All('ProxyInfra')` | Proxy infrastructure events |
| `All('Orchestration')` | Control plane orchestration events |
| `All('Portal')` | Developer portal events |
| `All('Mapi')` | Management API events |

---

## References

- [APIM TSG Index](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/)
- [On-Call Handbook](https://aka.ms/oncallhandbook)
- [Azure CEN](https://aka.ms/azurecen)
- [APIM Outage Playbook](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/outage-playbook)
- [JIT Access Guide](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/_jit/)
