# Test Failure Owner Assignment

Owner matrix for routing test failures to the appropriate team member. Source: `Automation/AutomaticTestFailureAnalyzer/analyze_failure.py`

## Test-Level Ownership via Attributes

Individual tests may declare ownership via the `[Owner("alias")]` MSTest attribute:

```csharp
[Owner("nimak")]
[TestMethod]
public void HttpResolverBasicTest_StreamOfRequests_WithLargeSchema()
{
    // Test owned by nimak
}
```

**How to find test owner**:
```powershell
# Search for Owner attribute near test method
grep -B10 "TestMethodName" Test/Bvt/**/*.cs | grep -i "Owner"
```

**Priority**: Test-level `[Owner]` attribute takes precedence over area-based assignment from the Owner Matrix below.

## Owner Matrix

| Owner | Areas of Responsibility |
|-------|------------------------|
| **Ajinkya** | Buildout to new Azure regions, capacity, resource pools |
| **Alan** | Networking, private endpoint |
| **Andy** | Resource provider release, BRAIN, Azure Resource Graph/Network, notification service |
| **Brian** | Release channels |
| **Gabriel** | Tenant release |
| **Gleb** | Managed identity, CloudService to VMSS migration, VMSS |
| **Kenny** | Buildout to new Azure regions |
| **Nina** | Certificates |
| **Samir** | Default owner (only if no other match) |

## Do Not Assign

The following owners should not be assigned test failures:
- Kedar
- Shilpa

## Assignment Logic

### By Error Keywords

```python
def assign_owner(error_text):
    error_lower = error_text.lower()
    
    # Region/Capacity
    if any(kw in error_lower for kw in ['region', 'buildout', 'capacity', 'resource pool']):
        return 'Ajinkya' if 'capacity' in error_lower else 'Kenny'
    
    # Networking
    if any(kw in error_lower for kw in ['network', 'private endpoint', 'vnet', 'subnet']):
        return 'Alan'
    
    # Resource Provider
    if any(kw in error_lower for kw in ['brain', 'resource graph', 'notification']):
        return 'Andy'
    
    # Release
    if 'release channel' in error_lower:
        return 'Brian'
    
    # Tenant
    if 'tenant' in error_lower:
        return 'Gabriel'
    
    # Identity/VMSS
    if any(kw in error_lower for kw in ['managed identity', 'vmss', 'cloud service']):
        return 'Gleb'
    
    # Certificates
    if any(kw in error_lower for kw in ['certificate', 'ssl', 'tls']):
        return 'Nina'
    
    # Default
    return 'Samir'
```

### By Test Type

| Test Category | Primary Owner | Backup |
|--------------|---------------|--------|
| Gateway/Proxy BVT | Team on-call | - |
| RP Integration | Andy | Samir |
| Networking tests | Alan | Samir |
| Identity tests | Gleb | Samir |
| Certificate tests | Nina | Samir |
| Region buildout | Kenny/Ajinkya | Samir |

## Environment-Specific Ownership

| Environment | Pipeline Type | Additional Context |
|-------------|--------------|-------------------|
| Current | Deploy/Functional/Integration | Pre-production validation |
| Dogfood | Deploy/ReleaseBlocking | Internal dogfooding |
| Canary | .NET SDK tests | SDK version validation |
| Hotfix | Hotfix pipelines | Urgent fixes |

## Escalation Path

1. Identify owner from matrix
2. If owner unavailable, escalate to Samir
3. For critical/blocking issues, notify team channel
4. For security-related failures, involve security team

## Test Pipeline Contacts

| Pipeline | Definition ID | Primary Contact |
|----------|--------------|-----------------|
| Main CI | 292578 | On-call |
| RP Release | - | Andy |
| Gateway BVT | - | Team lead |
