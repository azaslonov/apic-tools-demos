# Mitigation Actions Reference

This reference contains detailed mitigation actions for APIM SKUv1 incidents.

## Immediate Actions

### 1. Reboot/Reimage/Rebuild

**Jarvis Action URL**: [Manage Hosted Service](https://jarvis-west.dc.ad.msft.net/5DF5BE37)

**Parameters**:
| Parameter | Description | Example |
|-----------|-------------|---------|
| HostedServiceOperation | Action type | Reboot, Reimage, Rebuild |
| ApiServiceName | Service name (without domain) | contoso-api |
| RegionName | Leave empty for all regions | (empty) or "East US 2" |
| RoleInstanceNames | Specific instances | gwhost_0, Proxy.Host.WebRole_IN_0 |
| RestartRoleInstancesInParallel | Parallel restart | false (safer) |
| RestartRegionsInParallel | Parallel region restart | false (safer) |

**Order of operations**:
1. **Reboot** - Restarts the VM, fastest but least impactful
2. **Reimage** - Recreates VM from image, may migrate to new host
3. **Rebuild** - Complete VM rebuild, most impactful but can fix deeper issues

**When to use each**:
| Action | Use When | Expected Time | Risk |
|--------|----------|---------------|------|
| Reboot | Process hang, minor glitch | 5-10 min | Low |
| Reimage | Reboot failed, OS corruption | 15-30 min | Medium |
| Rebuild | Reimage failed, need fresh VM | 30-60 min | Higher |

### 2. Scale Operations

**For service overload**: Customer must initiate scale from Azure Portal

**Emergency scale** (OBSOLETE for VMSS, use only if absolutely necessary):
- Direct Cloud Service scaling via Azure Portal
- Creates SKU mismatch (expected behavior)
- Not stable - RP may scale back
- Customer must finalize via proper scale operation

### 3. Configuration Refresh

**Force configuration sync**:
Use when service has stale configuration that's not auto-refreshing.

---

## Rollback Procedures

### Dedicated SKUv1 Tenant Rollback

**Use case**: Recent upgrade caused regression

**Process**:
1. Identify target version (last known good)
2. Use targeted upgrade to rollback
3. Monitor service health after rollback

**TSG**: [Dedicated SKUv1 Rollback](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/buildanddeploy/publictargetedupgrades)

### Developer Portal Rollback

**Use case**: Portal regression after update

**TSG**: [Rollback Developer Portal](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/portal/rollback-developer-portal-version)

### ARM Manifest Rollback

**Use case**: ARM-level changes causing issues

**TSG**: [ARM Manifest Rollback](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/resourceprovider/arm-manifest-rollback)

---

## Advanced Mitigations

### Role Patcher

**Use case**: Need binary upgrade on specific SKUv1 services without full release

**Documentation**: [Role Patcher](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/buildanddeploy/prodrolepatcherreleasepipeline)

### Geneva Action Automation

**Use case**: Automated response to specific conditions

**Setup**: [Azure Alerting](https://azurealerting.trafficmanager.net/)

Can trigger Geneva Actions based on alert conditions.

---

## Service-Specific Mitigations

### VNET-Deployed Services

When service is in VNET and having issues:

1. **Follow VNET TSG**: [VNET Connectivity Issues](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/networking/vnet-connectivity-or-deployment-issues)

2. **Common VNET issues**:
   - NSG blocking required ports
   - UDR misconfiguration
   - DNS resolution failures
   - Service endpoint issues

### Certificate Issues

1. **Check certificate status**: Use [SslLabs](https://www.ssllabs.com/ssltest)
2. **Custom domain certificates**: May need customer action
3. **Platform certificates**: May need platform team engagement

### Memory/CPU Exhaustion

1. **Identify consuming process**: Check Jarvis Service Health Dashboard
2. **If Proxy process**:
   - Single VM: Follow [Memory Pressure TSG](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/gateway/memory-pressure-on-power-apim-alerts)
   - Multiple VMs: Engage Gateway team
3. **If other process**: Engage Platform team

---

## Mitigation Verification

### Verify Reboot Success

```kusto
All('ApiSvcHost')
| where DeploymentName == "{service-name}.azure-api.net"
| where PreciseTimeStamp > ago(30m)
| where eventType contains "RoleStart"
| project PreciseTimeStamp, RoleInstance, eventType
| order by PreciseTimeStamp desc
```

### Verify Service Health

1. **Health endpoint**: `https://{service}.azure-api.net/internal-status-0123456789abcdef`
2. **ASI**: Check service health metrics
3. **Kusto**: Check for new errors post-mitigation

### Verify Rollback Success

```kusto
GetTenantVersions
| where serviceName =~ "{service-name}"
| project serviceName, version, State
```

Version should match target rollback version.

---

## Post-Mitigation Actions

1. **Monitor**: Watch service for 30-60 minutes
2. **Document**: Update ICM with actions taken and results
3. **Verify customer impact resolved**: Check customer-facing symptoms
4. **Create repair items**: If root cause requires code fix
5. **Consider PIR**: For significant incidents

---

## Do NOT Do

❌ Deploy to all regions simultaneously (follow SDP)
❌ Make breaking changes without VIP validation
❌ Skip the reboot → reimage → rebuild progression
❌ Scale services without customer consent (except emergencies)
❌ Assume Azure platform issues without evidence
❌ Close incident before verifying mitigation
