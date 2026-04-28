# Code Review Guidelines (Azure API Management)

This rubric is tailored for the **AAPT-APIManagement** repository.

## Priorities

### 🔴 CRITICAL (Block merge)
- **Security vulnerabilities**:
  - Secrets/credentials in code (SEC101 patterns: Management Keys, Subscription Keys, SAS tokens)
  - Injection vectors in policy expressions
  - AuthZ/AuthN gaps in certificate filters
  - SSRF, XXE, or deserialization issues
- **Correctness bugs**:
  - Race conditions in ConcurrentDictionary/cache usage
  - Missing CancellationToken propagation in async code
  - Incorrect transaction/retry semantics in EF decorators
  - Data corruption in entity attachment/detachment
- **Breaking API/contract changes** without versioning
- **Data loss/destructive behavior** without safeguards

### 🟡 IMPORTANT (Requires discussion)
- **Missing tests** for new/changed behavior (50% diff coverage target)
- **Performance footguns**:
  - N+1 queries in EF repositories
  - Unbounded cache growth (XmlSerializer pools, authorization rules)
  - Missing pagination in API endpoints
- **Thread-safety issues**:
  - Shared state without proper synchronization
  - Missing `ConfigureAwait(false)` in library code
- **Architecture drift** from established patterns:
  - Autofac module registration in `/Management/Management.IoC/`
  - Repository pattern with EF DbContext
  - Policy handler interface implementation
- **Poor error handling/observability**:
  - Missing exception mapping to `ApiExceptionHandler`
  - Missing telemetry/logging

### 🟢 SUGGESTION (Non-blocking)
- Readability/naming/structure improvements
- Simplifying control flow, reducing nesting
- Minor best-practice improvements
- Documentation/XML comment improvements

## APIM-Specific Checks

### Policy Engine (`Proxy/Gateway.Policies/`)

**Critical checks (see `gateway-patterns.md` for full details):**
- [ ] XmlSerializer pool has size limits to prevent memory leaks
- [ ] Expression parsing validates input securely (type allow-list enforced)
- [ ] PolicyBase implementations properly dispose resources
- [ ] Validators handle all edge cases consistently
- [ ] `ConcurrentDictionary.GetOrAdd` used instead of check-then-act patterns

### Gateway Pipeline (`Proxy/Gateway.Pipeline/`)
- [ ] Use `ValueTask` for hot-path pipeline handlers
- [ ] Properly propagate `CancellationToken` through pipeline stages
- [ ] Error handlers set correct HTTP status codes
- [ ] Pipeline stage transitions are deterministic

### Gateway Security (`Proxy/Gateway.Policies.Expressions/`)
- [ ] `AllowedTypesAnalyzer` covers all used types
- [ ] `CodeInjectionAnalyzer` validates method count
- [ ] `KeywordAnalyzer` blocks unsafe keywords
- [ ] Expression timeout enforcement active

### Gateway Threading (`Proxy/Gateway.Policies.*`)
- [ ] `ConcurrentDictionary` with atomic operations (no check-then-act)
- [ ] `SemaphoreSlim` with proper async wait patterns
- [ ] Object pools with bounded size
- [ ] Timer cleanup for stale semaphores

### Gateway Redis (`Proxy/Gateway.Redis/`)
- [ ] Connection health checks before operations
- [ ] Operation success/failure tracking for metrics
- [ ] Proper timeout handling

### API Controllers (`Management/Management.Api/`)
- [ ] All async methods propagate CancellationToken
- [ ] Auth filter composition is correct (Certificate/Token/Scheme)
- [ ] API versioning maintains backward compatibility
- [ ] Exception handling maps to consistent error responses

### Data Access (`Management/Management.Data.Ef/`)
- [ ] Transaction decorators compose correctly
- [ ] Retry logic has proper backoff (not fixed 10 retries)
- [ ] Entity cloning handles all properties
- [ ] IDisposable implemented correctly in decorator chains
- [ ] Bulk operations consider performance

### Resource Provider (`ResourceProvider/`)
- [ ] ARM lifecycle operations are idempotent
- [ ] Service Fabric hosting patterns followed
- [ ] TaskHub orchestration handles failures gracefully

### Certificate Authentication
- [ ] Correct filter variant used (Mandatory/Optional × Legacy/SNI)
- [ ] Certificate validation follows security best practices
- [ ] Proper error messages for auth failures

## What to Check

| Category | APIM Focus |
|----------|------------|
| **Scope** | Does change match intent? Hidden behavior changes? |
| **Security** | No secrets (SEC101); validate inputs; least privilege |
| **Correctness** | Thread-safety; async/await patterns; retry semantics |
| **Reliability** | Error handling; idempotency; timeouts; cancellation |
| **Testing** | Unit/E2E coverage; CIT/BVT tests; edge cases |
| **Performance** | EF query efficiency; cache bounds; pagination |
| **Maintainability** | Follows Autofac DI patterns; proper layering |

## Comment Format

```
**[Severity] Category: Title**

Issue description.

**Why this matters:**
Impact/risk specific to APIM.

**Suggested fix:**
Concrete code or pattern to follow.
```

## Build & Test Commands

```bash
# Full build
MSBuild.exe /v:m /m /nr:false /p:Configuration=Release ci-build.proj

# Run tests  
MSBuild.exe /v:m /m /nr:false /p:Configuration=Release ci-tests.proj

# Gateway only
MSBuild.exe Proxy\ci-build-gateway.proj

# Management solution
MSBuild.exe Management\Management.sln
```

## Quality Gates

| Gate | Requirement |
|------|-------------|
| Code Coverage | 50% diff coverage |
| CodeQL | Pass static analysis |
| SDL Compliance | FxCop `Sdl7.0_minimum.ruleset` |
| Approvers | Min 1 on main/prodrelease/hotfix |
| Secret Scanning | 1ES SEC101 patterns |

## Key Patterns to Follow

- **DI Registration**: Use Autofac modules in `/Management/Management.IoC/`
- **Data Access**: Repository pattern with `EfRepository<T>`
- **Configuration**: `IConfiguration` with transform files
- **Logging**: Structured logging with telemetry correlation
- **Policies**: Implement `IPolicyHandler` interface

### Gateway-Specific Patterns

- **Policy Implementation**: Extend `PolicyBase<TConfiguration>` or `SimplePolicyBase<TConfiguration>`
- **Pipeline Handlers**: Implement `IPipelineHandler` with `ValueTask ProcessAsync()`
- **Object Pooling**: Use `ConcurrentQueueObjectPool<T>` for expensive objects (XmlSerializer)
- **Thread-Safety**: Use `ConcurrentDictionary.GetOrAdd()`, `SemaphoreSlim.WaitAsync()` with cancellation
- **Expression Hosts**: Implement `IExpressionHost` for expression security initialization
- **Testing**: Use `ProxyTestSetBase` for policy tests, MSTest with `[Owner]` attribute

## Gateway-Specific Reviews

For changes touching `Proxy/` or `Test/Bvt/Gateway/`, refer to `gateway-patterns.md` for:
- Memory safety patterns (XmlSerializer pooling)
- Concurrency patterns (ConcurrentDictionary, SemaphoreSlim)
- Expression security validation
- Pipeline handler implementation
- Test requirements and patterns
