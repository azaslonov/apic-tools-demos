# Gateway Code Review Guidelines

Quick reference for reviewing Gateway code (`Proxy/` and `Test/Bvt/Gateway/`).

---

## Architecture Overview

The Gateway handles API request processing through a pipeline architecture with policies. Key architectural layers:

| Layer | Components | Purpose |
|-------|------------|---------|
| **Transport** | DotNetty/SpanNetty, HTTP Clients | Network I/O, connection pooling |
| **Pipeline** | PipelineExecutor, PipelineHandler | Request processing stages |
| **Policies** | PolicyBase, IPipelineHandler | Request/response transformations |
| **Expressions** | ExpressionRegistry, Security Analyzers | Policy expression evaluation |
| **Throttling** | RateLimit, ConcurrencyLimit, Quota | Traffic control |
| **Telemetry** | ApplicationInsights, Metrics | Observability |

---

## Review Hotspots

| Path | Critical Areas |
|------|----------------|
| `Gateway.Policies.Expressions/` | Security analyzers, type allow-lists, code injection |
| `Gateway.Policies/` | XmlSerializer pooling, handler thread-safety, expression hosts |
| `Gateway.Pipeline/` | Context state, stage transitions, error handling |
| `Gateway.Pipeline.IO/` | Stream wrappers, buffer management, latency tracking |
| `Gateway.Http.Client.DotNetty/` | Event loops, channel pools, backpressure |
| `Gateway.Policies.RateLimit/` | Distributed counters, Redis ops, increment conditions |
| `Gateway.Policies.ConcurrencyLimit/` | SemaphoreSlim patterns, stale semaphore cleanup |
| `Gateway.Redis/` | Connection health, timeout handling, GCRA |

---

## 🔴 Critical Issues

### 1. Expression Security
Never allow arbitrary type access in expression allow-lists:
```csharp
// ❌ CRITICAL: Security violation
allowedTypes.Add(typeof(System.Reflection.Assembly));

// ✅ Use explicit allow-list with security review
```

### 2. XmlSerializer Memory Leak
XmlSerializer with XmlRootAttribute creates uncollectable assemblies:
```csharp
// ❌ Memory leak - new assembly each call
new XmlSerializer(type, new XmlRootAttribute(elementName));

// ✅ Use pooled serializers (see PolicyBase.cs)
SerializerCache.GetOrAdd((type, elementName), k => 
    new ConcurrentQueueObjectPool<XmlSerializer>(...));
```

### 3. Thread-Safety Race Conditions
```csharp
// ❌ Race condition - check-then-act
if (!dict.ContainsKey(key)) dict[key] = Create();

// ✅ Atomic
dict.GetOrAdd(key, k => Create());

// ❌ ConcurrentDictionary modification during iteration
foreach (var item in concurrentDict)
    if (ShouldRemove(item)) concurrentDict.TryRemove(item.Key, out _);

// ✅ Snapshot first
foreach (var item in concurrentDict.ToArray())
    if (ShouldRemove(item)) concurrentDict.TryRemove(item.Key, out _);
```

### 4. AddOrUpdate Factory Side Effects
```csharp
// ❌ Factory may run multiple times - side effects are dangerous
dict.AddOrUpdate(key, 
    k => { SendEmail(); return Create(); },  // May send multiple emails!
    (k, v) => Update(v));

// ✅ Side effects outside the factory
var value = dict.AddOrUpdate(key, k => Create(), (k, v) => Update(v));
SendEmail();  // Only once
```

---

## DotNetty/SpanNetty Transport Patterns

### Event Loop Fundamentals
```csharp
// ❌ Blocking operation on event loop thread
await Task.Delay(1000);  // Don't block the event loop

// ✅ Use event loop timer or dispatch off event loop
var (executor, pool, _, _) = this.entries[index];
if (executor.InEventLoop)
{
    return pool.AcquireAsync(context, cancellation);
}
else
{
    executor.Execute(this.ProcessAsync, workItem);
}
```

**Key Principles:**
- Event loop executes callbacks **serially** - blocking causes cascading delays
- Check `executor.InEventLoop` before synchronous operations
- Prefer `Channel<T>` for producer-consumer patterns over event loop marshalling

### Channel.Read() and Backpressure
```csharp
// ❌ Calling Read() prematurely causes excess syscalls
while (await reader.WaitToReadAsync(cancellationToken))
{
    ProcessItem(reader.ReadAsync());
    this.channel.Read();  // May cause unnecessary syscalls
}

// ✅ Only request more data when local queue is empty
await foreach (var httpContent in reader.ReadAllAsync(cancellationToken))
{
    await destination.WriteAsync(httpContent.Content.UnreadMemory);
    httpContent.Release();
    
    if (!reader.TryPeek(out _))
    {
        // Only ask for more from transport when nothing local
        this.channel.Read();
    }
}
```

### ManualResetEventSlim Optimization
```csharp
// ❌ Spin count of 1 causes excessive kernel transitions
new ManualResetEventSlim(false, 1);

// ✅ Use default spin count (35 in .NET Core) for optimal balance
new ManualResetEventSlim(false);  // Uses SpinCount = 35
```

### Content Release Pattern
```csharp
// ✅ Always release IHttpContent after processing
try
{
    await destination.WriteAsync(httpContent.Content.UnreadMemory, cancellationToken);
}
finally
{
    httpContent.Release();  // Prevent memory leaks
}
```

---

## Connection Pool Patterns

### Round-Robin Pool Selection
```csharp
// ✅ Atomic increment for thread-safe pool selection
var index = (uint)Interlocked.Increment(ref this.current) % this.capacity;
var (executor, pool, queue, _) = this.entries[index];
```

### Event Loop Stall Prevention
Under load, acquire-before-release stalls occur because event loop executes callbacks serially:

```csharp
// ❌ Can stall under load - acquire waits for release on same thread
public ValueTask<IChannel> AcquireAsync(IPipelineContext context, CancellationToken cancellation)
{
    // If pool is exhausted and release hasn't run yet, we're stuck
    return pool.AcquireAsync(context, cancellation);
}

// ✅ Dispatch to event loop to allow concurrent acquire/release
var promise = new TaskCompletionSource<IChannel>(TaskCreationOptions.RunContinuationsAsynchronously);
queue.Enqueue((pool, context, cancellation, promise));
executor.Execute(this.Acquire0, queue);
return new ValueTask<IChannel>(promise.Task);
```

### Thread Safety Trade-offs
**Reviewer Guidance**: Prefer simpler non-thread-safe code on event loop unless benchmarks prove multi-threading provides significant benefit:

```csharp
// Ask during review: "Is this thread-safe code needed? What's the benchmark difference?"
// Thread-safe code is harder to maintain and debug
```

---

## Buffer Management

### Production Response Size Distribution
When reviewing buffer-related changes, consider production data:

| Percentile | Size | Implications |
|------------|------|--------------|
| 50th | 512B | Most responses fit in small buffers |
| 90th | 5KiB | Larger buffers reduce ReadAsync calls |
| 99th | 128KiB | Significant for high-traffic scenarios |
| 99.9th | 1MiB | Large responses impact memory |

### Buffer Manager Selection
```csharp
// FixedBufferManager: Preallocated, predictable, affects capacity metrics
public class FixedBufferManager : IBufferManager
{
    // Capacity chosen based on SKU memory constraints:
    // Premium = A4 VM, Standard = A2, Dev/Basic = A1
    readonly ConcurrentQueue<byte[]> buffers;
}

// ArrayPoolBufferManager: On-demand, GC-friendly, variable memory
public class ArrayPoolBufferManager : IBufferManager
{
    readonly ArrayPool<byte> arrayPool = ArrayPool<byte>.Shared;
}
```

**Review Alert**: Changes to buffer sizes affect customer-visible "Capacity metric" - larger buffers = higher baseline memory.

---

## Streaming and Latency Patterns

### CopyToAsync vs ReadAsync
```csharp
// ✅ CopyToAsync when content is already buffered (avoids async state machine overhead)
public override async Task CopyToAsync(Stream destination, int bufferSize, CancellationToken cancellationToken)
{
    await foreach (var httpContent in reader.ReadAllAsync(cancellationToken))
    {
        await destination.WriteAsync(httpContent.Content.UnreadMemory, cancellationToken);
        // DotNetty already provides parallelism - no need for explicit parallel read/write
    }
}

// ⚠️ ReadAsync adds async machinery even when content is in memory
// Use only when you need fine-grained control or buffering for policy processing
```

### Latency Tracking Placement
```csharp
// ❌ Latency tracked at wrapper level includes destination stream delays
public class TimeTrackingStreamWrapper : Stream
{
    public override async Task CopyToAsync(Stream destination, ...)
    {
        var start = Stopwatch.GetTimestamp();
        await destination.WriteAsync(...);  // Includes destination latency!
        onIoCompleted(Stopwatch.GetTimestamp() - start);
    }
}

// ✅ Track latency at transport layer (HttpResponseContentStream)
// Capture timing when data arrives from backend, not when written to client
```

### Connection Lifecycle
```csharp
// ✅ Close connection if response not fully consumed
protected override void Dispose(bool disposing)
{
    if (!this.doneWriting)
    {
        this.doneWriting = true;
        this.logger.Verbose("PrematureResponseContentDisposalDetected", "Channel will be closed");
        this.CloseSilently();  // Prevent connection reuse with partial data
    }
}
```

---

## 🟡 Important Issues

### CancellationToken Propagation
Always propagate through async chains:
```csharp
// ❌ Token not propagated
await httpClient.SendAsync(request);

// ✅ Token propagated
await httpClient.SendAsync(request, cancellationToken);
```

### Object Pool Bounds
Unbounded pools can exhaust memory under load:
```csharp
// ❌ Unbounded growth
new ConcurrentQueue<ExpensiveObject>();

// ✅ Bounded pool
new BoundedObjectPool<ExpensiveObject>(maxSize: 100);
```

### Event Handler Cleanup
```csharp
// ❌ Leak - handlers accumulate
configSource.Changed += OnChanged;

// ✅ Cleanup in Dispose
public void Dispose() { configSource.Changed -= OnChanged; }
```

### Symmetric Increment/Decrement
```csharp
// ❌ Missing decrement on error path
Interlocked.Increment(ref _count);
try { DoWork(); }
catch { throw; }  // Forgot decrement!
finally { Interlocked.Decrement(ref _count); }

// ✅ Decrement in finally covers all paths
```

---

## 🟢 Suggestions (Style & Naming)

### Naming Conventions
- **Use `PascalCase`** for public members, types, namespaces
- **Use `camelCase`** for parameters, local variables
- **Prefix private fields** with `_` (e.g., `_connectionPool`)
- **Use `I` prefix** for interfaces (e.g., `IRequestHandler`)
- **Use `Async` suffix** for async methods
- **Use `TryGet` pattern** for methods that may fail: `bool TryGetValue(out T value)`
- **Avoid abbreviations** except well-known ones (Id, Url, Http, Xml, Json)
- **Use descriptive names** - favor clarity over brevity

### Code Style
- **One statement per line** - avoid chaining multiple operations
- **Braces on new lines** (Allman style) per project convention
- **Use `var`** when type is obvious from RHS: `var list = new List<string>()`
- **Use explicit types** when type isn't obvious: `IService service = GetService()`
- **Keep methods short** - aim for < 30 lines, extract helpers for complex logic
- **Order members**: fields, constructors, properties, public methods, private methods
- **Group related code** - keep related fields/methods together

### Formatting
- **Consistent spacing** around operators and after commas
- **Blank line** between method definitions
- **No trailing whitespace**
- **Remove unused `using` statements**
- **Sort `using` statements** - System first, then alphabetical

### Comments & Documentation
- **XML docs on public APIs** - `<summary>`, `<param>`, `<returns>`
- **Avoid obvious comments** - code should be self-documenting
- **Comment "why" not "what"** - explain intent, not mechanics
- **TODO format**: `// TODO: [owner] description` with tracking item if long-term

---

## Key Patterns

### 1. Performance: Avoid Hot Path Allocations
```csharp
// ❌ Allocates on every call
var elapsed = new Stopwatch(); elapsed.Start();

// ✅ No allocation
long start = Stopwatch.GetTimestamp();
long elapsedTicks = Stopwatch.GetTimestamp() - start;
```

Use `ArrayPool<T>.Shared` for temporary buffers. Use `Encoder.Convert` instead of `GetByteCount` when encoding anyway.

### 2. TaskCompletionSource in High-Throughput
```csharp
// ✅ Prevents completing thread from blocking on continuations
var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
```

### 3. TryGet Pattern for Fallible Operations
```csharp
// ❌ Caller must check null
public Event GetBufferedEvent() => _buffer.IsEmpty ? null : _buffer.Dequeue();

// ✅ Clear success/failure indication
public bool TryGetBufferedEvent(out Event evt)
{
    if (_buffer.IsEmpty) { evt = default; return false; }
    evt = _buffer.Dequeue();
    return true;
}
```

### 4. Fatal Exception Handling
```csharp
// ❌ Catches fatal exceptions
catch (Exception ex) { Log(ex); }

// ✅ Allows fatal exceptions to propagate
catch (Exception ex) when (!ex.IsFatal()) { Log(ex); }
```

### 5. Capture Metadata Before Risky Operations
```csharp
// ❌ Metadata lost if stream read fails
var content = await response.Content.ReadAsStringAsync();
Log(response.StatusCode, response.Content.Headers.ContentLength);

// ✅ Capture first
var statusCode = response.StatusCode;
var contentLength = response.Content.Headers.ContentLength;
var content = await response.Content.ReadAsStringAsync();
```

### 6. SpanNetty Channel Read Timing
```csharp
// ❌ Calling Read() when local queue still has items
while (true)
{
    ProcessItem(queue.Dequeue());
    channel.Read();  // Excess syscalls
}

// ✅ Only call Read() when queue empty
while (true)
{
    ProcessItem(queue.Dequeue());
    if (queue.Count == 0) channel.Read();
}
```

### 7. Loop Control Flow
```csharp
// ❌ Return bypasses cleanup
while (hasMore)
{
    if (terminal) return;  // Cleanup skipped!
    Process();
}
FlushBuffer();

// ✅ Break allows cleanup to run
while (hasMore)
{
    if (terminal) break;
    Process();
}
FlushBuffer();
```

### 8. Configurable Defaults
```csharp
// ❌ Hard-coded
private const int BatchSize = 1;

// ✅ Configurable with default
public int BatchSize { get; init; } = 1;
```

### 9. Base Class Trade-offs
Prefer self-contained handlers for readability unless substantial shared logic exists. Base classes add indirection and coupling.

### 10. Buffer Size Guidance
Production response size distribution: 50th=512B, 90th=5KiB, 99th=128KiB, 99.9th=1MiB. Balance buffer size against memory usage and customer capacity metrics.

### 11. HTTP/2 Stream Handling
```csharp
// HTTP/2 header frame comes separately from content - stream needs to be 
// poked to start content flow. Use ILastHttpContent to detect completion.
if (content is ILastHttpContent)
{
    writer.Complete();
    this.doneWriting = true;
}
```

### 12. Async Exception Patterns with Promise
```csharp
// ✅ Use async void only for event loop dispatch with proper error handling
async void Acquire0(object state)
{
    var (pool, context, cancellation, promise) = workItem;
    try
    {
        var result = await pool.AcquireAsync(context, cancellation);
        promise.TrySetResult(result);
    }
    catch (OperationCanceledException ex) when (ex.CancellationToken == cancellation)
    {
        promise.TrySetCanceled(ex.CancellationToken);
    }
    catch (Exception ex) when (!ex.IsFatal())
    {
        promise.TrySetException(ex);
    }
}
```

### 13. ExceptionDispatchInfo for Deferred Errors
```csharp
// ✅ Capture exception context for later throwing
ExceptionDispatchInfo error;
void OnError(Exception ex)
{
    if (!this.doneWriting && this.error == null)
    {
        this.error = ExceptionDispatchInfo.Capture(ex);
    }
}

public override Task<int> ReadAsync(...)
{
    this.error?.Throw();  // Rethrows with original stack trace
    // ...
}
```

### 14. Semaphore Cleanup for Dynamic Keys
```csharp
// ✅ Clean up stale semaphores to prevent memory leaks
if ((force || (now - pair.Value.LastAccess) > MaxAge)
    && pair.Value.Semaphore.CurrentCount == 0
    && Interlocked.CompareExchange(ref record.WaitCount, int.MinValue, 0) == 0)
{
    this.semaphores.TryRemove(pair.Key, out record);
}
```

---

## Files to Review Together

| Changed File | Also Review |
|--------------|-------------|
| `Gateway.Policies.*/` | `Gateway.Policies.Tests/` |
| `Gateway.Pipeline/` | Error handlers, stage nodes |
| `Gateway.Policies.Expressions/` | Security analyzers, AllowedTypesAnalyzer |
| `Gateway.Configuration/` | Schema, validation |
| `Gateway.Http.Client.DotNetty/` | Connection pools, event loops, stream handling |
| `Gateway.Pipeline.IO/Buffers/` | Buffer managers, memory impact |
| `Gateway.Policies.RateLimit/` | Counter services, P2P synchronization |
| `Gateway.Policies.ConcurrencyLimit/` | Semaphore lifecycle, neighbor discovery |
| `Gateway.AspNetCore/Http/` | Response streamers, latency tracking |
| `appsettings.json` (any SKU) | Buffer sizes, memory configuration |

---

## Configuration Sensitivity

Changes to these settings impact customer-visible metrics:

| Setting | Impact | Review Alert |
|---------|--------|--------------|
| Buffer size | Affects "Capacity metric" baseline | Larger = higher baseline memory |
| Buffer count | Affects preallocated memory | Must align with SKU VM memory |
| Event loop spin count | Affects CPU/latency trade-off | Default 35 is well-tuned |
| Connection pool size | Affects concurrent backend connections | Per-SKU limits apply |

**SKU Memory Constraints:**
- Premium: A4 VM
- Standard: A2 VM  
- Dev/Basic: A1 VM

---

## C# / .NET Best Practices

### Async/Await
- **Always propagate `CancellationToken`** through async call chains
- **Never block on async**: Avoid `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` - use `await`
- **Use `ConfigureAwait(false)`** in library code to avoid deadlocks
- **Suffix async methods with `Async`** (except ASP.NET controllers)
- **No `async void`** except for event handlers
- **Use `ValueTask<T>`** for hot paths that often complete synchronously (avoids Task allocation)
- **Never await `ValueTask` twice** - store result in variable if needed multiple times

### Memory & Allocations
- **Use `ArrayPool<T>.Shared`** for temporary buffers on hot paths
- **Prefer `Span<T>` / `ReadOnlySpan<T>`** for slicing without allocation
- **Use `StringBuilder`** for string concatenation in loops
- **Avoid LINQ on hot paths** - allocates iterators and delegates
- **Use `stackalloc`** for small fixed-size buffers (< 1KB)

### Collections
- **Initialize capacity** when size is known: `new List<T>(capacity)`
- **Use `TryGetValue`** not `ContainsKey` + indexer (avoids double lookup)
- **Prefer `IReadOnlyList<T>`** / `IReadOnlyDictionary<TK,TV>` in public APIs
- **Return empty collections** not null: `Array.Empty<T>()`, `Enumerable.Empty<T>()`

### Disposal & Resources
- **Use `using` declaration** (C# 8+) or `using` statement for `IDisposable`
- **Use `await using`** for `IAsyncDisposable`
- **Dispose in reverse order** of acquisition
- **Implement `IDisposable`** if class holds unmanaged resources or `IDisposable` members

### Null Handling
- **Use `ArgumentNullException.ThrowIfNull()`** (.NET 6+) for guard clauses
- **Prefer pattern matching**: `if (x is null)` over `if (x == null)`
- **Use null-coalescing**: `x ?? default`, `x ??= Create()`
- **Enable nullable reference types** and address warnings

### Error Handling
- **Use exception filters**: `catch (Exception ex) when (!ex.IsFatal())`
- **Throw specific exceptions** not `Exception` base class
- **Include context** in exception messages: IDs, names, values
- **Use `nameof()`** for parameter names in `ArgumentException`

### Performance Tips
- **Seal classes** that won't be inherited (enables devirtualization)
- **Prefer `struct`** for small, immutable value types (< 16 bytes)
- **Avoid boxing**: Use generic constraints or `Span<T>` APIs
- **Use `StringComparison.Ordinal`** for non-linguistic string comparisons

---

## Dependency Injection Patterns

### Feature Flags in Pipeline Handlers

**Pattern: Resolve Feature Flags at Registration Time**

When a pipeline handler needs a feature flag (boolean setting), resolve the flag value at DI registration time rather than passing the entire `ISettingsProvider` into the handler. This:
- Improves testability (tests can pass simple `bool` instead of mocking `ISettingsProvider`)
- Follows single responsibility principle (handler doesn't need to know about settings infrastructure)
- Makes the handler's dependencies explicit

**❌ Bad Pattern:**
```csharp
// Handler takes ISettingsProvider dependency
public class CompressionHandler : IPipelineHandler
{
    private readonly ISettingsProvider settingsProvider;
    
    public CompressionHandler(bool inbound, CompressionMode mode, ISettingsProvider settingsProvider = null)
    {
        this.settingsProvider = settingsProvider;
    }
    
    public ValueTask ProcessAsync(IPipelineContext context, CancellationToken cancellation)
    {
        // Reading settings at runtime - harder to test, hidden dependency
        if (settingsProvider.TryGetBooleanSetting("FeatureKey", out var enabled) && enabled)
        { ... }
    }
}

// DI Registration
builder.Register(c => {
    var settingsProvider = c.Resolve<ISettingsProvider>();
    return new CompressionHandlerFactory((inbound, mode) => 
        new CompressionHandler(inbound, mode, settingsProvider));
});
```

**✅ Good Pattern:**
```csharp
// Handler takes bool directly
public class CompressionHandler : IPipelineHandler
{
    private readonly bool featureEnabled;
    
    public CompressionHandler(bool inbound, CompressionMode mode, bool featureEnabled = false)
    {
        this.featureEnabled = featureEnabled;
    }
    
    public ValueTask ProcessAsync(IPipelineContext context, CancellationToken cancellation)
    {
        // Simple boolean check - easy to test, explicit dependency
        if (this.featureEnabled)
        { ... }
    }
}

// DI Registration - resolve flag at registration time
builder.Register(c => {
    var settingsProvider = c.Resolve<ISettingsProvider>();
    bool featureEnabled = settingsProvider.TryGetBooleanSetting("FeatureKey", out var enabled) && enabled;
    return new CompressionHandlerFactory((inbound, mode) => 
        new CompressionHandler(inbound, mode, featureEnabled));
});
```

**Testing Benefits:**
```csharp
// ❌ Old test - requires mock or stub
var handler = new CompressionHandler(true, CompressionMode.Decompress, new StubSettingsProvider());

// ✅ New test - simple boolean
var handler = new CompressionHandler(true, CompressionMode.Decompress, brotliEnabled: true);
```

**Note:** For feature flags evaluated at DI registration time, the flag value is fixed for the lifetime of the application. This is appropriate for:
- Feature flags that don't change at runtime
- Settings read from configuration files
- Flags that require application restart to change

For dynamic feature flags that can change at runtime, consider other patterns like `IOptionsMonitor<T>`.

---

## Build & Test

```powershell
# Build Gateway
dotnet build Proxy/Gateway.sln /p:Configuration=Debug

# Run Gateway tests
dotnet test Proxy/test/Gateway.Tests/Gateway.Tests.csproj

# Run BVTs
dotnet test Test/Bvt/Gateway/Gateway.Bvt.csproj
```

---