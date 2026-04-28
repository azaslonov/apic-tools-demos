# Common Alert Patterns and Root Causes

This reference contains common alert patterns encountered in APIM SKUv1 incidents and their typical root causes.

## Alert Type: HealthMonitorServiceInBadState

### Pattern
- Alert Title: `[Prod] API RP Alert: HealthMonitorServiceInBadState occurred for Tenant`
- Component: Gateway, Portal, or Proxy

### Common Causes (Ranked)

| Rank | Cause | Frequency | Key Indicators |
|------|-------|-----------|----------------|
| 1 | VNET settings blocking OS upgrade | High | VNET-enabled service, recent OS upgrade |
| 2 | VM in bad state after reboot | Medium | Role state cycling in AzureCM |
| 3 | Network/VM infrastructure issue | Medium | External Azure issue |
| 4 | Storage throttling | Low | Storage exceptions in logs |
| 5 | Certificate issue | Low | SSL errors |

### Mitigation Steps
1. Try reboot via Jarvis Action
2. If reboot fails, try reimage
3. If reimage fails, try rebuild
4. If rebuild fails, engage Cloud Service team with logs

---

## Alert Type: API RP Health Monitoring Alert

### Pattern
- Alert Title: `[{region}] API RP Health Monitoring Alert: {component} for {SKU} Tenant {service-name}`
- Components: gateway, portal, proxy

### Sub-patterns

#### Gateway not reachable
- **Indicators**: Gateway availability = 0%, health probe failures
- **Common causes**: DNS issue, VM down, network configuration, certificate expiry

#### Portal not reachable
- **Indicators**: Developer portal unavailable
- **Severity note**: If "Has published version" = false in ASI, downgrade to Sev3
- **Common causes**: Portal process crash, configuration issue

#### Proxy not reachable
- **Indicators**: API calls failing, backend unreachable
- **Common causes**: Similar to gateway issues

---

## Alert Type: Service Deployment/Upgrade Alerts

### HealthMonitorTenantVersionMismatchWithRP
- **Cause**: Service version differs from RP expected version
- **Usually**: Self-resolves after upgrade completes
- **Action**: Monitor, wait for upgrade completion

### HealthMonitorSkuMismatch
- **Cause**: Actual SKU differs from expected
- **Trigger**: Often after emergency scale operations
- **Action**: Customer needs to initiate proper scale from Azure Portal

### CloudServiceAv2PackageMismatchDetected
- **Cause**: Package mismatch during deployment
- **Action**: May need redeployment

---

## Alert Type: VM/VMSS Alerts

### Unhealthy Role Instance
- **Indicators**: Single instance showing unhealthy in health monitoring
- **Common causes**: OS issue, process crash, resource exhaustion

### DSC Extension Failure
- **Cause**: Desired State Configuration extension failed
- **Action**: Check DSC logs, escalate to Azure Automation team if needed

### VMSS Deployment Failed
- **Cause**: VMSS create/update operation failed
- **Common causes**: Capacity issues, configuration errors, Azure platform issues

---

## Self-Mitigating Patterns

These alerts often resolve automatically:

| Alert | Typical Resolution Time | When to Escalate |
|-------|------------------------|------------------|
| Single instance down during upgrade | 30-60 min | After 2+ hours |
| Health monitor flap | 5-15 min | If persistent >30 min |
| Post-reboot recovery | 5-10 min | If not recovered in 15 min |
| DNS propagation | 5-15 min | If still failing after 30 min |

---

## Escalation Triggers

Escalate immediately if:
- Multiple services affected in same region
- All instances of a service down
- Sev0/Sev1 customer impact
- No improvement after reboot/reimage/rebuild cycle
- Suspected Azure platform issue

---

## Correlation Patterns

### Check for Broader Issues

When investigating, check if this is part of a larger pattern:

1. **Same region**: Multiple services in same region affected?
2. **Same version**: Services on specific version affected?
3. **Same SDP stage**: Services in specific deployment stage affected?
4. **Azure outage**: Check Azure status page and partner notifications

### Kusto Query for Pattern Detection
```kusto
All('Orchestration')
| where PreciseTimeStamp > ago(1h)
| where eventType == "HealthMonitorServiceInBadState"
| summarize count() by Region, bin(PreciseTimeStamp, 5m)
| order by count_ desc
```
