# Escalation Paths and Team Contacts

This reference contains escalation paths for APIM SKUv1 incidents.

## Team Ownership Matrix

| Area | Owning Team | Primary Contact |
|------|-------------|-----------------|
| VM/VMSS/Infrastructure | Platform | Platform Team |
| Gateway/Proxy | Gateway | Gateway Engineering |
| Developer Portal | Portal | Portal Team |
| Control Plane/RP | Resource Provider | RP Team |
| SMAPI/Configuration | SMAPI | SMAPI Team |
| Networking/VNET | Networking | Platform Team |
| Certificates | Security | Platform Team |

## Teams Channels

| Team | Channel | Link |
|------|---------|------|
| Platform | Platform | [Platform Channel](https://teams.microsoft.com/l/channel/19%3Abb8c347362bf41ddb2ab77be2c936437%40thread.skype/Platform?groupId=48dcdab4-70a0-46b2-a680-aa8e200a9126&tenantId=72f988bf-86f1-41af-91ab-2d7cd011db47) |
| Gateway | Gateway Engineering | [Gateway Channel](https://teams.microsoft.com/l/channel/19%3Ae879e4306b554fbea5e28287db9dff3e%40thread.skype/Gateway%20Engineering?groupId=48dcdab4-70a0-46b2-a680-aa8e200a9126&tenantId=72f988bf-86f1-41af-91ab-2d7cd011db47) |
| SLOOP | SLOOP | [SLOOP Channel](https://teams.microsoft.com/l/channel/19%3A848d42faeb96436994d004cc9334a7b1%40thread.skype/SLOOP?groupId=48dcdab4-70a0-46b2-a680-aa8e200a9126&tenantId=72f988bf-86f1-41af-91ab-2d7cd011db47) |

## Escalation Order

### For Non-Critical Issues (Sev3+)

1. Post in relevant Teams channel during business hours
2. Wait for response (15-30 min)
3. If no response, contact Incident Manager

### For Critical Issues (Sev2)

1. Join engineering bridge immediately
2. Notify IM (Incident Manager)
3. Contact RA responsible member from owning team
4. Post in Teams channel for awareness

### For Outages (Sev0/Sev1)

1. Join engineering bridge immediately
2. Engage EIM (Executive Incident Manager)
3. Contact on-call for all potentially affected teams
4. Follow [APIM Outage Playbook](https://eng.ms/docs/cloud-ai-platform/devdiv/serverless-paas-balam/serverless-paas-vikr/api-management/api-management-tsg/troubleshooting/outage-playbook)

## External Team Escalations

### Azure Cloud Services / Guest Agent / CM Team

**When to engage**:
- Reboot/reimage/rebuild cycle doesn't resolve VM issues
- Suspected Azure platform issue

**What to provide**:
- Orchestration logs showing the issue
- Current role state from AzureCM queries
- Timeline of events
- Evidence ruling out application issues

**Important**: Be prepared to explain and justify - they may initially classify as application issue.

### DSC Extension / Azure Automation Team

**When to engage**:
- DSC Extension failures
- Configuration management issues

**ICM Template**: [Product Team Escalation](https://supportability.visualstudio.com/AzureAutomation/_wiki/wikis/Azure-Automation.wiki/23864/Product-Team-Escalation)

### Azure Networking

**When to engage**:
- VNET connectivity issues not resolved by standard TSGs
- DNS resolution failures
- Load balancer issues

## On-Call Contacts

### Finding On-Call

Use ICM to find current on-call:
- Navigate to ICM > Teams > API Management
- Check current on-call schedule

### Handoff Protocol

Daily handoffs should cover:
- Active Sev2s (incoming shift takes ownership)
- Active CRIs requiring attention
- Pending mitigations or follow-ups

## Communication Templates

### Initial Engagement (Teams)

```
🔔 **Incident Engagement**
**ICM**: [incident-id]
**Service**: [service-name]
**Issue**: [brief description]
**Impact**: [customer impact]
**Current Status**: Investigating
**Ask**: [specific ask - triage help, ownership, etc.]
```

### Escalation to IM

```
**Escalation Required**
**ICM**: [incident-id]
**Severity**: [sev level]
**Duration**: [how long has this been going on]
**Actions Taken**: [list of mitigation attempts]
**Current Status**: [mitigation status]
**Blocker**: [what's blocking resolution]
**Ask**: [specific help needed]
```

### Engineering Bridge Update

```
**Status Update** - [timestamp]
**Current Investigation**: [what you're looking at]
**Findings**: [key findings]
**Next Steps**: [planned actions]
**ETA**: [estimated time to next update or mitigation]
```

## JIT Access Requirements

Most investigation actions require JIT access:

| Action | JIT Role Required |
|--------|-------------------|
| View Kusto data | Reader access |
| Jarvis Actions | ApiManagement-PlatformServiceOperator |
| VM access | ApiManagement-PlatformServiceAdministrator |
| Production access | SAW machine required |

**JIT Portal**: https://jitaccess.security.core.windows.net

### Common JIT Roles

- `ApiManagement-PlatformServiceAdministrator`: Full admin access
- `ApiManagement-PlatformServiceOperator`: Operational actions (reboot, reimage)
- Reader roles: View-only access to logs and metrics
