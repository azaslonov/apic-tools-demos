# Common Error Patterns and Investigation Guidance

Context for understanding errors commonly seen in SMAPI/Control Plane telemetry.

Use this to understand what categories of errors exist and what typically causes them.
This is **guidance**, not classification—always investigate the actual root cause.

---

## Authentication / AAD Errors

**What to look for:** `AADSTS*`, `MsalServiceException`, `NotAuthenticatedException`

**Common patterns:**
- `AADSTS700027` + `certificate expired` → Expired service certificate
- `AADSTS7000222` + `expired` → Expired client secret
- `AADSTS700016` + `not found` → AAD app registration issue
- `MsalServiceException` + `connection forcibly closed` → Network/AAD service issue

**Investigation guidance:**
- **If affecting specific tenant:** Likely customer-side credential issue (not actionable)
- **If affecting all tenants in a region:** Check if our certificates/secrets expired, or AAD regional outage
- **If intermittent across regions:** Usually transient AAD issues (check Azure status)

**Typical root causes:**
1. Our service credentials expired → Check Key Vault, rotation schedule
2. Customer credentials expired → Not actionable (customer error)
3. AAD service degradation → Check Azure status page

---

## Database / SQL Errors

**What to look for:** `SqlException`, `DbUpdateException`, `EntityException`, `RetryLimitExceededException`

**Common patterns:**
- `request limit has been reached` → DTU/eDTU exhaustion
- `Execution Timeout Expired` → Long-running query or DB overload
- `connection was forcibly closed` → Network issue or DB failover
- `size quota` → Database storage full
- `Cannot insert duplicate key` → Race condition or retry bug

**Investigation guidance:**
- **If one region:** Check that region's SQL metrics (CPU, DTU, storage)
- **If all regions:** Look for problematic query pattern, recent code change
- **If correlated with traffic spike:** Capacity issue
- **If duplicate key errors:** Look for missing idempotency or bad retry logic

**Typical root causes:**
1. Database under capacity → Need scale-up or query optimization
2. Bad query pattern → Find the query, check execution plan
3. Connection pool exhaustion → Check connection management code
4. Race condition in code → Look at the specific entity/operation

**Key diagnostic queries:** See `investigation-patterns.md` for DB CPU and latency queries.

---

## Redis Errors

**What to look for:** `TaskCanceledException` + `Redis`, `StackExchange.Redis`

**Common patterns:**
- `EstablishRedisConnectionAsync` timeout → Redis connection issues
- `No connection is available` → Connection pool exhausted

**Investigation guidance:**
- **If one region:** Check that region's Redis metrics
- **If all regions:** Possible Redis client bug or configuration issue
- **If after deployment:** Check for changes to Redis usage patterns

**Typical root causes:**
1. Redis server overload → Check server metrics, consider scaling
2. Network issues → Usually transient
3. Connection leak → Look for disposal issues in code

---

## Storage Errors

**What to look for:** `RequestFailedException` + storage, `WebException` + `TableRestClient`

**Common patterns:**
- `Operations per second account limit` → Storage throttling
- `Tenant storage account not found` → Missing/deleted storage account

**Investigation guidance:**
- **If throttling:** Check which operations are hitting limits
- **If not found:** Check if storage account exists, tenant provisioning state

**Typical root causes:**
1. Hot partition → Need partition key redesign
2. Burst traffic → Consider retry/backoff improvements
3. Provisioning bug → Storage not created properly

---

## Entity / Data Errors

**What to look for:** `InvalidOperationException`, `ArgumentException`, duplicate key errors

**Common patterns:**
- `must be touched with higher revision` → Optimistic concurrency conflict
- `Sequence contains more than one` → Data integrity issue
- `Cannot insert duplicate key` → Race condition

**Investigation guidance:**
- **If revision mismatch:** Check for concurrent modification scenarios
- **If duplicate key:** Look for retry logic without idempotency
- **If sequence errors:** Data corruption or bad query assumptions

**Typical root causes:**
1. Race condition → Need locking or idempotency
2. Data corruption → Investigate how bad data got in
3. Missing null checks → Defensive coding issue

---

## OpenAPI / Swagger Errors

**What to look for:** Errors in `OpenApiImporter`, `WsdlExporter`, `OpenApiV3Deserializer`

**Common patterns:**
- `YamlScalarNode` cast errors → Malformed customer API spec
- `ArgumentNullException` in OpenAPI code → Bad input handling
- `IndexOutOfRangeException` → Edge case in parsing

**Investigation guidance:**
- **Usually customer-caused:** Bad API definition uploaded
- **But if widespread:** Could be a bug in our parsing code

**Typical root causes:**
1. Customer uploaded invalid spec → Not actionable (return good error message)
2. Edge case in parser → Need code fix to handle case or return better error

---

## Controller / DI Errors

**What to look for:** `DependencyResolutionException`, `AutoMapperMappingException`

**Common patterns:**
- `Cannot resolve parameter` → Missing DI registration
- `Missing map` → AutoMapper configuration issue

**Investigation guidance:**
- **If after deployment:** Check recent code changes to DI or AutoMapper config
- **If specific controller:** Look at that controller's dependencies

**Typical root causes:**
1. Missing registration → Add to DI container
2. Circular dependency → Refactor code
3. AutoMapper config missing → Add mapping

---

## Framework / General Errors

**What to look for:** `NullReferenceException`, `TaskCanceledException`, `JsonReaderException`

**Common patterns:**
- `NullReferenceException` in specific method → Code bug
- `TaskCanceledException` → Request timeout or client disconnect
- `JsonReaderException` → Malformed JSON input

**Investigation guidance:**
- **NullRef:** Find the line of code, understand what was null
- **TaskCanceled:** Check if client-side timeout or server overload
- **JSON errors:** Usually customer input issue

**Typical root causes:**
1. Missing null check → Add defensive code
2. Client timeouts → May need performance work or timeout tuning
3. Bad input → Validate input better, return clear error

---

## Determining Actionability

**Actionable (file a bug):**
- NullReferenceException in our code
- Race conditions causing data issues
- Missing error handling
- Capacity issues we control
- Configuration/credential expiration we manage

**Not actionable (skip):**
- Customer input errors (400-level)
- External service transient failures
- Customer credential issues
- Issues that self-resolved quickly

---

## When You See an Unfamiliar Error

1. **Get the full stack trace** from Kusto
2. **Find the code** in this repository
3. **Understand the context** - what operation was being performed?
4. **Check recent changes** - was this code modified recently?
5. **Determine actionability** - is this something we can fix?
