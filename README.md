# cf-workerz

A Zig library for building Cloudflare Workers with WebAssembly. Write high-performance serverless functions in Zig with full access to Cloudflare's platform APIs.

## Features

- **Cloudflare APIs**: KV, R2, D1, Cache, Queues, Service Bindings, Workers AI
- **Built-in Router**: Path parameters, wildcards, route groups, response helpers
- **JSPI Async**: Zero-overhead JavaScript Promise Integration (no Asyncify)
- **Tiny Binaries**: WASM output typically 10-15KB
- **Type Safe**: Full Zig type safety with compile-time route checking
- **Modern Zig**: Supports Zig 0.14+ (tested with 0.15 and 0.16)

## Requirements

- **Zig**: 0.14.0 or later
- **Runtime**: Cloudflare Workers (or Chrome 137+, Firefox 139+ for local testing)
- **Node.js**: 18+ (for wrangler CLI)

## Installation

### Via zig fetch

```bash
zig fetch --save https://github.com/ealecho/cf-workerz/archive/refs/tags/v0.1.0.tar.gz
```

### Manual (build.zig.zon)

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .cf_workerz = .{
        .url = "https://github.com/ealecho/cf-workerz/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...",  // zig fetch will provide this
    },
},
```

### Configure build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // WASM target for Cloudflare Workers
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Get cf-workerz dependency
    const workers_dep = b.dependency("cf_workerz", .{
        .target = wasm_target,
        .optimize = optimize,
    });

    // Create your worker
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });

    // Add the cf-workerz import
    root_module.addImport("cf-workerz", workers_dep.module("cf-workerz"));

    const exe = b.addExecutable(.{
        .name = "worker",
        .root_module = root_module,
    });

    exe.entry = .disabled;
    exe.rdynamic = true;

    b.installArtifact(exe);
}
```

## Quick Start

### 1. Create your worker (src/main.zig)

```zig
const std = @import("std");
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;

// Define routes
const routes: []const Route = &.{
    Route.get("/", handleRoot),
    Route.get("/hello/:name", handleHello),
    Route.get("/api/health", handleHealth),
};

fn handleRoot(ctx: *FetchContext) void {
    ctx.json("{\"message\":\"Hello from cf-workerz!\"}", 200);
}

fn handleHello(ctx: *FetchContext) void {
    const name = ctx.params.get("name") orelse "World";
    
    var buf: [256]u8 = undefined;
    const response = std.fmt.bufPrint(&buf, 
        "{{\"hello\":\"{s}\"}}", .{name}) catch {
        ctx.throw(500, "Buffer overflow");
        return;
    };
    
    ctx.json(response, 200);
}

fn handleHealth(ctx: *FetchContext) void {
    ctx.json("{\"status\":\"healthy\"}", 200);
}

// Entry point called by TypeScript runtime
export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
```

### 2. Create TypeScript runtime (src/index.ts)

The TypeScript runtime handles JSPI and bridges JavaScript and WASM:

```typescript
import wasmModule from '../zig-out/bin/worker.wasm';

const enum ReservedHeapPtr {
  NULL = 1, UNDEFINED = 2, TRUE = 3, FALSE = 4, INFINITY = 5, NAN = 6,
}

interface WASMExports {
  memory: WebAssembly.Memory;
  alloc: (size: number) => number;
  allocSentinel: (size: number) => number;
  handleFetch: (ctxPtr: number) => void;
}

interface WorkerContext {
  path: string;
  req: Request;
  env: Env;
  ctx: ExecutionContext;
  resolved: boolean;
  resolve?: (response: Response) => void;
}

const textDecoder = new TextDecoder();
const textEncoder = new TextEncoder();

class Heap extends Map<number, unknown> {
  private counter = 7;
  
  constructor() {
    super();
    this.set(1, null);
    this.set(2, undefined);
    this.set(3, true);
    this.set(4, false);
    this.set(5, Infinity);
    this.set(6, NaN);
  }

  put(value: unknown): number {
    if (value === null) return 1;
    if (value === undefined) return 2;
    if (value === true) return 3;
    if (value === false) return 4;
    const key = this.counter++;
    if (this.counter >= 100_000) this.counter = 7;
    this.set(key, value);
    return key;
  }
}

class WASMRuntime {
  private heap = new Heap();
  private instance: WebAssembly.Instance | null = null;
  private wasmMemory: Uint8Array | null = null;
  private handleFetchPromising: ((ctxPtr: number) => Promise<any>) | null = null;

  private buildEnvFunctions() {
    const self = this;
    return {
      jsFree(ptr: number) { if (ptr > 6) self.heap.delete(ptr); },
      jsHeapGetNum(ptr: number) { return self.heap.get(ptr) as number; },
      jsStringSet(ptr: number, len: number) { 
        return self.heap.put(self.getString(ptr, len)); 
      },
      jsStringGet(stringPtr: number) { 
        return self.putString(self.heap.get(stringPtr) as string); 
      },
      jsStringThrow(stringPtr: number): never { 
        throw new Error(self.heap.get(stringPtr) as string); 
      },
      jsArrayPush(arrayPtr: number, itemPtr: number) {
        (self.heap.get(arrayPtr) as unknown[]).push(self.heap.get(itemPtr));
      },
      jsArrayPushNum(arrayPtr: number, num: number) {
        (self.heap.get(arrayPtr) as unknown[]).push(num);
      },
      jsArrayGet(arrayPtr: number, pos: number) {
        return self.heap.put((self.heap.get(arrayPtr) as unknown[])[pos]);
      },
      jsArrayGetNum(arrayPtr: number, pos: number) {
        return (self.heap.get(arrayPtr) as number[])[pos];
      },
      jsObjectHas(objPtr: number, keyPtr: number) {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        const key = self.heap.get(keyPtr) as string;
        return self.heap.put(obj[key] !== undefined);
      },
      jsObjectSet(objPtr: number, keyPtr: number, valuePtr: number) {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        obj[self.heap.get(keyPtr) as string] = self.heap.get(valuePtr);
      },
      jsObjectSetNum(objPtr: number, keyPtr: number, value: number) {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        obj[self.heap.get(keyPtr) as string] = value;
      },
      jsObjectGet(objPtr: number, keyPtr: number) {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        const key = self.heap.get(keyPtr) as string;
        const value = obj[key];
        return self.heap.put(typeof value === 'function' ? value.bind(obj) : value);
      },
      jsObjectGetNum(objPtr: number, keyPtr: number) {
        const obj = self.heap.get(objPtr) as Record<string, unknown>;
        const val = Number(obj[self.heap.get(keyPtr) as string]);
        return isNaN(val) ? 0 : val;
      },
      jsStringify(objPtr: number) { 
        return self.heap.put(JSON.stringify(self.heap.get(objPtr))); 
      },
      jsParse(strPtr: number) { 
        return self.heap.put(JSON.parse(self.heap.get(strPtr) as string)); 
      },
      jsFnCall(funcPtr: number, argsPtr: number) {
        const func = self.heap.get(funcPtr) as (...args: unknown[]) => unknown;
        const args = self.heap.get(argsPtr);
        const res = args === undefined || args === null ? func() 
          : Array.isArray(args) ? func(...args) : func(args);
        return self.heap.put(res);
      },
      jsAsyncFnCall: null, // Replaced with Suspending
      jsResolve(ctxPtr: number, resPtr: number) {
        const ctx = self.heap.get(ctxPtr) as WorkerContext;
        ctx.resolve?.(self.heap.get(resPtr) as Response);
      },
      jsLog(stringPtr: number) { console.log(self.heap.get(stringPtr)); },
      jsSize(ptr: number) {
        const data = self.heap.get(ptr);
        if (data === null || data === undefined) return 0;
        if (typeof data === 'object' && 'byteLength' in data) 
          return (data as ArrayBufferLike).byteLength;
        if (typeof data === 'string' || Array.isArray(data)) return data.length;
        return 0;
      },
      jsToBytes(ptr: number) {
        const data = self.heap.get(ptr);
        let bytes: Uint8Array;
        if (data instanceof ArrayBuffer) bytes = new Uint8Array(data);
        else if (data instanceof Uint8Array) bytes = data;
        else if (typeof data === 'string') bytes = textEncoder.encode(data);
        else throw new Error('jsToBytes: unsupported data type');
        return self.putBytes(bytes);
      },
      jsToBuffer(ptr: number, len: number) {
        return self.heap.put(self.getBytes(ptr, len).buffer);
      },
      jsGetClass(classPos: number) { return self.heap.put(CLASSES[classPos]); },
      jsCreateClass(classPos: number, argsPtr: number) {
        const ClassCtor = CLASSES[classPos];
        const args = self.heap.get(argsPtr);
        const instance = args === undefined || args === null ? new ClassCtor()
          : Array.isArray(args) ? new ClassCtor(...args) : new ClassCtor(args);
        return self.heap.put(instance);
      },
      jsEqual(aPtr: number, bPtr: number) {
        return self.heap.put(self.heap.get(aPtr) === self.heap.get(bPtr));
      },
      jsDeepEqual(aPtr: number, bPtr: number) {
        try {
          return self.heap.put(
            JSON.stringify(self.heap.get(aPtr)) === JSON.stringify(self.heap.get(bPtr))
          );
        } catch { return self.heap.put(false); }
      },
      jsInstanceOf(classPos: number, objPtr: number) {
        return self.heap.put(self.heap.get(objPtr) instanceof CLASSES[classPos]);
      },
      jsWaitUntil(ctxPtr: number) {
        const ctx = self.heap.get(ctxPtr) as WorkerContext;
        const resolver: { resolve: (value?: unknown) => void } = { resolve: () => {} };
        ctx.ctx.waitUntil(new Promise((resolve) => { resolver.resolve = resolve; }));
        return self.heap.put(resolver.resolve);
      },
      jsWaitUntilResolve(resolverPtr: number, valuePtr: number) {
        (self.heap.get(resolverPtr) as (value?: unknown) => void)(self.heap.get(valuePtr));
      },
      jsPassThroughOnException(ctxPtr: number) {
        (self.heap.get(ctxPtr) as WorkerContext).ctx.passThroughOnException();
      },
      jsCacheGet(keyPtr: number) {
        const key = self.heap.get(keyPtr) as string | undefined;
        return self.heap.put(key !== undefined ? caches.open(key) : caches.default);
      },
      jsFetch: null, // Replaced with Suspending
      jsRandomUUID() { return self.putString(crypto.randomUUID()); },
      jsGetRandomValues(bufPtr: number) {
        crypto.getRandomValues(self.heap.get(bufPtr) as Uint8Array);
      },
    };
  }

  private createAsyncImports() {
    const self = this;
    
    const jsAsyncFnCallImpl = async (funcPtr: number, argsPtr: number) => {
      const func = self.heap.get(funcPtr) as (...args: unknown[]) => Promise<unknown>;
      const args = self.heap.get(argsPtr);
      const result = args === undefined || args === null ? await func()
        : Array.isArray(args) ? await func(...args) : await func(args);
      return self.heap.put(result);
    };

    const jsFetchImpl = async (urlPtr: number, initPtr: number) => {
      const url = self.heap.get(urlPtr) as string | Request;
      const init = self.heap.get(initPtr) as RequestInit | undefined;
      try {
        return self.heap.put(await fetch(url, init));
      } catch (err) {
        console.error('Fetch failed:', err);
        return self.heap.put(new Response(null, { status: 502 }));
      }
    };

    return {
      jsAsyncFnCall: new WebAssembly.Suspending(jsAsyncFnCallImpl),
      jsFetch: new WebAssembly.Suspending(jsFetchImpl),
    };
  }

  private init() {
    if (this.instance) return;
    
    const envFunctions = this.buildEnvFunctions();
    Object.assign(envFunctions, this.createAsyncImports());

    this.instance = new WebAssembly.Instance(wasmModule, {
      env: {
        memoryBase: 0,
        tableBase: 0,
        memory: new WebAssembly.Memory({ initial: 512 }),
        ...envFunctions,
      },
    });

    const exports = this.instance.exports as unknown as WASMExports;
    if (exports.handleFetch) {
      this.handleFetchPromising = WebAssembly.promising(exports.handleFetch);
    }
  }

  private get exports() { return this.instance!.exports as unknown as WASMExports; }
  private alloc(size: number) { return this.exports.alloc(size); }
  private allocSentinel(size: number) { return this.exports.allocSentinel(size); }

  private getMemory() {
    const memory = this.exports.memory;
    if (!this.wasmMemory || this.wasmMemory.buffer !== memory.buffer) {
      this.wasmMemory = new Uint8Array(memory.buffer);
    }
    return this.wasmMemory;
  }

  private getBytes(ptr: number, len: number) {
    const copy = new Uint8Array(len);
    copy.set(this.getMemory().subarray(ptr, ptr + len));
    return copy;
  }

  private putBytes(buf: Uint8Array, ptr?: number) {
    const len = buf.byteLength;
    if (ptr === undefined) ptr = this.alloc(len);
    this.getMemory().subarray(ptr, ptr + len).set(buf);
    return ptr;
  }

  private getString(ptr: number, len: number) {
    return textDecoder.decode(this.getBytes(ptr, len));
  }

  private putString(str: string) {
    const buf = textEncoder.encode(str);
    const ptr = this.allocSentinel(buf.byteLength);
    this.getMemory().subarray(ptr, ptr + buf.byteLength).set(buf);
    return ptr;
  }

  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    this.init();
    
    const url = new URL(request.url);
    const context: WorkerContext = {
      path: url.pathname,
      req: request,
      env: env,
      ctx: ctx,
      resolved: false,
    };

    return new Promise<Response>(async (resolve) => {
      context.resolve = (response: Response) => {
        context.resolved = true;
        resolve(response);
      };

      if (!this.handleFetchPromising) {
        resolve(new Response('handleFetch not exported', { status: 500 }));
        return;
      }

      const ctxId = this.heap.put(context);
      
      try {
        await this.handleFetchPromising(ctxId);
      } catch (err) {
        console.error('WASM error:', err);
        if (!context.resolved) {
          resolve(new Response(`WASM error: ${err}`, { status: 500 }));
        }
        return;
      }

      if (!context.resolved) {
        resolve(new Response('No response from handler', { status: 500 }));
      }
    });
  }
}

const CLASSES = [
  Array, Object, Date, Map, Set, WeakMap, WeakSet,
  Int8Array, Uint8Array, Uint8ClampedArray, Int16Array, Uint16Array,
  Int32Array, Uint32Array, BigInt64Array, BigUint64Array,
  ArrayBuffer, SharedArrayBuffer, DataView,
  Request, Response, Headers, FormData, File, Blob,
  URL, URLPattern, URLSearchParams,
  ReadableStream, WritableStream, TransformStream,
  CompressionStream, DecompressionStream,
  FixedLengthStream, WebSocketPair,
];

const runtime = new WASMRuntime();

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    return runtime.fetch(request, env, ctx);
  },
};
```

### 3. Type declarations (src/wasm.d.ts)

```typescript
declare module '*.wasm' {
  const wasmModule: WebAssembly.Module;
  export default wasmModule;
}

declare namespace WebAssembly {
  class Suspending {
    constructor(fn: (...args: any[]) => Promise<any>);
  }
  function promising(fn: (...args: any[]) => any): (...args: any[]) => Promise<any>;
}
```

### 4. Configuration files

**wrangler.toml:**
```toml
name = "my-worker"
main = "src/index.ts"
compatibility_date = "2024-01-01"
compatibility_flags = ["nodejs_compat"]

[build]
command = "zig build"

[[rules]]
type = "CompiledWasm"
globs = ["**/*.wasm"]
```

**package.json:**
```json
{
  "name": "my-worker",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "npx wrangler@latest dev --port 8787",
    "deploy": "npx wrangler@latest deploy",
    "build": "zig build"
  }
}
```

**tsconfig.json:**
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "types": ["@cloudflare/workers-types"]
  },
  "include": ["src/**/*"]
}
```

### 5. Build and run

```bash
# Build WASM
zig build

# Run locally
npx wrangler@latest dev --port 8787

# Test
curl http://localhost:8787/
curl http://localhost:8787/hello/Zig
```

---

## Router API

### Defining Routes

```zig
const Route = workers.Router;

const routes: []const Route = &.{
    // Static routes
    Route.get("/", handleRoot),
    Route.get("/health", handleHealth),
    
    // Path parameters
    Route.get("/users/:id", handleGetUser),
    Route.post("/users", handleCreateUser),
    Route.put("/users/:id", handleUpdateUser),
    Route.delete("/users/:id", handleDeleteUser),
    
    // Wildcards (matches rest of path)
    Route.get("/files/*path", handleFiles),
    
    // Route groups with shared prefix
    Route.group("/api/v1", &.{
        Route.get("/status", handleApiStatus),
        Route.get("/echo/:message", handleApiEcho),
    }),
    
    // Match any HTTP method
    Route.all("/any", handleAnyMethod),
};

export fn handleFetch(ctx_id: u32) void {
    const ctx = workers.FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
```

### Route Methods

| Method | Description |
|--------|-------------|
| `Route.get(pattern, handler)` | GET request |
| `Route.post(pattern, handler)` | POST request |
| `Route.put(pattern, handler)` | PUT request |
| `Route.delete(pattern, handler)` | DELETE request |
| `Route.patch(pattern, handler)` | PATCH request |
| `Route.head(pattern, handler)` | HEAD request |
| `Route.options(pattern, handler)` | OPTIONS request |
| `Route.all(pattern, handler)` | Any HTTP method |
| `Route.group(prefix, children)` | Route group with prefix |

### Path Parameters

```zig
fn handleGetUser(ctx: *FetchContext) void {
    // Access path parameter by name
    const id = ctx.params.get("id") orelse {
        ctx.throw(400, "Missing user ID");
        return;
    };
    
    // Access by index
    const first = ctx.params.getIndex(0);
    
    // Access wildcard match
    const path = ctx.params.wildcard();
    
    // ...
}
```

### Pattern Syntax

| Pattern | Example Match | Params |
|---------|---------------|--------|
| `/users` | `/users` | (none) |
| `/users/:id` | `/users/123` | `id = "123"` |
| `/users/:id/posts/:postId` | `/users/1/posts/2` | `id = "1", postId = "2"` |
| `/files/*path` | `/files/a/b/c` | `path = "a/b/c"` |
| `/files/*` | `/files/readme.txt` | `* = "readme.txt"` |

### Response Helpers

The library provides Hono-style response helpers with `ctx.json()` supporting automatic JSON serialization:

```zig
fn handleExample(ctx: *FetchContext) void {
    // Struct -> JSON (auto-serialized)
    ctx.json(.{ .id = 1, .name = "Alice" }, 200);

    // Named struct -> JSON
    const User = struct { id: u32, name: []const u8 };
    ctx.json(User{ .id = 1, .name = "Alice" }, 200);

    // With explicit status codes
    ctx.json(.{ .id = 1 }, 201);  // Created

    // Raw JSON string (backward compatible)
    ctx.json("{\"raw\":true}", 200);

    // Error -> JSON error body {"error": "ErrorName"}
    ctx.json(error.NotFound, 404);

    // Other response types
    ctx.text("Hello, World!", 200);
    ctx.html("<h1>Hello</h1>", 200);
    ctx.redirect("/new-path", 302);
    ctx.noContent();  // 204
    ctx.throw(500, "Internal error");
}
```

---

## KV Storage

```zig
const KVNamespace = workers.KVNamespace;

fn handleKV(ctx: *FetchContext) void {
    const kv = ctx.env.kv("MY_KV") orelse {
        ctx.throw(500, "KV not configured");
        return;
    };
    defer kv.free();
    
    // Get text value
    if (kv.getText("my-key", .{})) |value| {
        // Use value...
    }
    
    // Put value
    kv.put("my-key", .{ .text = "my-value" }, .{});
    
    // Put with expiration (TTL in seconds)
    kv.put("temp-key", .{ .text = "expires soon" }, .{
        .expirationTtl = 3600,  // 1 hour
    });
    
    // Put with metadata
    const metadata = workers.Object.new();
    defer metadata.free();
    metadata.setNum("version", u32, 1);
    kv.put("with-meta", .{ .text = "value" }, .{ .metadata = &metadata });
    
    // Delete
    kv.delete("my-key");
    
    // List keys
    const list = kv.list(.{ .prefix = "user:", .limit = 100 });
    defer list.free();
}
```

---

## R2 Object Storage

```zig
const R2Bucket = workers.R2Bucket;

fn handleR2(ctx: *FetchContext) void {
    const bucket = ctx.env.r2("MY_BUCKET") orelse {
        ctx.throw(500, "R2 not configured");
        return;
    };
    defer bucket.free();
    
    // Put object
    const r2obj = bucket.put("my-key", .{ .text = "content" }, .{});
    defer r2obj.free();
    
    // Get object
    const result = bucket.get("my-key", .{});
    defer result.free();
    
    switch (result) {
        .r2objectBody => |body| {
            const data = body.text();
            const etag = body.httpEtag();
            // Use data...
        },
        .r2object => |_| {
            // Conditional request - not modified
        },
        .none => {
            // Object not found
        },
    }
    
    // List objects
    const list = bucket.list(.{ .limit = 100, .prefix = "uploads/" });
    defer list.free();
    
    // Delete
    bucket.delete("my-key");
    
    // Head (metadata only)
    if (bucket.head("my-key")) |obj| {
        defer obj.free();
        const size = obj.size();
        // ...
    }
}
```

---

## D1 Database

```zig
const D1Database = workers.D1Database;
const Array = workers.Array;
const String = workers.String;
const Object = workers.Object;

fn handleD1(ctx: *FetchContext) void {
    const db = ctx.env.d1("MY_DB") orelse {
        ctx.throw(500, "D1 not configured");
        return;
    };
    defer db.free();
    
    // Simple query
    const stmt = db.prepare("SELECT * FROM users WHERE id = ?");
    defer stmt.free();
    
    // Bind parameters
    const args = Array.new();
    defer args.free();
    args.pushNum(u32, 123);
    
    const bound = stmt.bind(&args);
    defer bound.free();
    
    // Get first row
    const row = bound.first(null);
    defer row.free();
    
    if (row.id > 6) {  // Valid object
        const name = row.get("name");  // Returns heap pointer
        if (name > 6) {
            const name_str = String.init(name);
            defer name_str.free();
            // Use name_str.value()...
        }
    }
    
    // Get all rows
    const result = bound.all();
    defer result.free();
    
    if (result.results()) |results| {
        defer results.free();
        while (results.next(Object)) |r| {
            defer r.free();
            // Process row...
        }
    }
    
    // Execute (for INSERT/UPDATE/DELETE)
    const insert_stmt = db.prepare("INSERT INTO users (name) VALUES (?)");
    defer insert_stmt.free();
    
    const insert_args = Array.new();
    defer insert_args.free();
    const name = String.new("Alice");
    defer name.free();
    insert_args.push(&name);
    
    const insert_bound = insert_stmt.bind(&insert_args);
    defer insert_bound.free();
    
    const run_result = insert_bound.run();
    defer run_result.free();
    
    // Get metadata
    const changes = run_result.changes();      // Number of rows changed
    const last_id = run_result.lastRowId();    // Last inserted ID
    const duration = run_result.duration();    // Query duration (f64)
}
```

---

## Cache API

```zig
const Cache = workers.Cache;
const Request = workers.Request;
const Response = workers.Response;
const Headers = workers.Headers;
const String = workers.String;

fn handleCache(ctx: *FetchContext) void {
    // Get the default cache
    const cache = Cache.new(.{ .none = {} });
    defer cache.free();
    
    const cache_url = "https://cache.local/my-key";
    
    // Match: Get cached response
    if (cache.match(.{ .text = cache_url }, .{})) |cached| {
        defer cached.free();
        const body = cached.text();
        // Use cached body...
        return;
    }
    
    // Cache miss - create response and cache it
    const cache_req = Request.new(.{ .text = cache_url }, .{ .none = {} });
    defer cache_req.free();
    
    const headers = Headers.new();
    defer headers.free();
    headers.setText("Cache-Control", "public, max-age=60");
    headers.setText("Content-Type", "application/json");
    
    const body_str = String.new("{\"cached\":true}");
    defer body_str.free();
    
    const response = Response.new(
        .{ .string = &body_str },
        .{ .status = 200, .statusText = "OK", .headers = &headers },
    );
    defer response.free();
    
    // Store in cache
    cache.put(.{ .request = &cache_req }, &response);
    
    // Delete from cache
    _ = cache.delete(.{ .text = cache_url }, .{});
}
```

---

## Queues

### Producer (sending messages)

```zig
const Queue = workers.Queue;

fn handleQueue(ctx: *FetchContext) void {
    const queue = ctx.env.queue("MY_QUEUE") orelse {
        ctx.throw(500, "Queue not configured");
        return;
    };
    defer queue.free();
    
    // Send a single message
    queue.send("{\"action\":\"process\",\"id\":123}");
    
    // Send with options
    queue.sendWithOptions("{\"priority\":\"high\"}", .{
        .contentType = .json,
        .delaySeconds = 60,  // Delay delivery by 60 seconds
    });
    
    // Send batch
    const messages = [_]workers.MessageSendRequest{
        .{ .body = "{\"id\":1}", .contentType = .json },
        .{ .body = "{\"id\":2}", .contentType = .json },
        .{ .body = "{\"id\":3}", .contentType = .json },
    };
    queue.sendBatch(&messages);
}
```

### Consumer (receiving messages)

```zig
const MessageBatch = workers.MessageBatch;

export fn handleQueue(batch_ptr: u32) void {
    const batch = MessageBatch.init(batch_ptr);
    defer batch.free();
    
    var messages = batch.messages();
    defer messages.free();
    
    while (messages.next()) |msg| {
        defer msg.free();
        
        const body = msg.body();       // JSON stringified body
        const attempts = msg.attempts(); // Delivery attempt count
        
        // Process message...
        
        msg.ack();    // Acknowledge (processed successfully)
        // or: msg.retry();  // Retry later
    }
    
    // Alternative: batch operations
    // batch.ackAll();
    // batch.retryAll();
}
```

---

## Service Bindings (Worker-to-Worker)

```zig
const Fetcher = workers.Fetcher;
const Headers = workers.Headers;
const String = workers.String;

fn handleService(ctx: *FetchContext) void {
    // Get the service binding
    const backend = ctx.env.service("BACKEND_WORKER") orelse {
        ctx.throw(500, "Service not configured");
        return;
    };
    defer backend.free();
    
    // Simple GET request
    const response = backend.fetch(.{ .text = "https://internal/api/data" }, null);
    defer response.free();
    
    const body = response.text() orelse "";
    // Use response body...
    
    // POST request with body
    const post_body = String.new("{\"action\":\"update\"}");
    defer post_body.free();
    
    const headers = Headers.new();
    defer headers.free();
    headers.setText("Content-Type", "application/json");
    
    const post_response = backend.fetch(.{ .text = "https://internal/api/update" }, .{
        .requestInit = .{
            .method = .Post,
            .body = .{ .string = &post_body },
            .headers = headers,
        },
    });
    defer post_response.free();
}
```

**wrangler.toml configuration:**
```toml
[[services]]
binding = "BACKEND_WORKER"
service = "backend-worker-name"
```

---

## Workers AI

```zig
const AI = workers.AI;

fn handleAI(ctx: *FetchContext) void {
    const ai = ctx.env.ai("AI") orelse {
        ctx.throw(500, "AI not configured");
        return;
    };
    defer ai.free();
    
    // Text generation (simple prompt)
    const result = ai.textGeneration(
        "@cf/meta/llama-3.1-8b-instruct",
        "Write a haiku about programming",
        .{ .max_tokens = 100, .temperature = 0.7 },
    ) orelse {
        ctx.throw(500, "AI request failed");
        return;
    };
    defer result.free();
    
    if (result.response()) |text| {
        // Use generated text...
    }
    
    // Chat (conversation format)
    const messages = [_]workers.ChatMessage{
        .{ .role = "system", .content = "You are a helpful assistant" },
        .{ .role = "user", .content = "Hello!" },
    };
    
    const chat_result = ai.chat(
        "@cf/meta/llama-3.1-8b-instruct",
        &messages,
        .{ .max_tokens = 256 },
    ) orelse {
        ctx.throw(500, "Chat failed");
        return;
    };
    defer chat_result.free();
    
    // Text embeddings
    const embed_result = ai.textEmbeddings(
        "@cf/baai/bge-base-en-v1.5",
        "Text to embed",
    ) orelse {
        ctx.throw(500, "Embedding failed");
        return;
    };
    defer embed_result.free();
    
    // Translation
    const translation = ai.translation(
        "@cf/meta/m2m100-1.2b",
        "Hello, how are you?",
        "en",  // source language
        "es",  // target language
    ) orelse {
        ctx.throw(500, "Translation failed");
        return;
    };
    defer translation.free();
    
    // Summarization
    const summary = ai.summarization(
        "@cf/facebook/bart-large-cnn",
        "Long text to summarize...",
        128,  // max_length
    ) orelse {
        ctx.throw(500, "Summarization failed");
        return;
    };
    defer summary.free();
}
```

**Available AI Models:**

| Task | Model | Notes |
|------|-------|-------|
| Text Generation | `@cf/meta/llama-3.1-8b-instruct` | General chat/completion |
| Text Generation | `@cf/mistral/mistral-7b-instruct-v0.1` | Fast inference |
| Embeddings | `@cf/baai/bge-base-en-v1.5` | 768 dimensions |
| Embeddings | `@cf/baai/bge-large-en-v1.5` | 1024 dimensions |
| Summarization | `@cf/facebook/bart-large-cnn` | News-style summaries |
| Translation | `@cf/meta/m2m100-1.2b` | 100+ languages |

**wrangler.toml configuration:**
```toml
[ai]
binding = "AI"
```

---

## Additional APIs

### JsonBody (Request Parsing)

The `JsonBody` helper provides Hono-style ergonomic JSON request parsing:

```zig
const workers = @import("cf-workerz");

fn handleCreateUser(ctx: *workers.FetchContext) void {
    // Parse request body as JSON
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .@"error" = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();
    
    // Get required string field
    const name = json.getString("name") orelse {
        ctx.json(.{ .@"error" = "Name is required" }, 400);
        return;
    };
    
    // Get optional string with default
    const role = json.getStringOr("role", "user");
    
    // Get typed numbers
    const age = json.getInt("age", u32) orelse 0;
    const score = json.getFloat("score", f64) orelse 0.0;
    
    // Get boolean
    const active = json.getBool("active") orelse true;
    
    // Check if field exists
    if (json.has("metadata")) {
        // Get nested object
        if (json.getObject("metadata")) |metadata| {
            // metadata is std.json.ObjectMap
            _ = metadata;
        }
    }
    
    // Get array field
    if (json.getArray("tags")) |tags| {
        // tags is []const std.json.Value
        for (tags) |tag| {
            if (tag == .string) {
                const tag_str = tag.string;
                _ = tag_str;
            }
        }
    }
    
    ctx.json(.{ 
        .name = name, 
        .role = role, 
        .age = age,
        .active = active 
    }, 201);
}
```

**JsonBody Methods:**

| Method | Return Type | Description |
|--------|-------------|-------------|
| `getString(key)` | `?[]const u8` | Get string or null |
| `getStringOr(key, default)` | `[]const u8` | Get string or default |
| `getInt(key, T)` | `?T` | Get integer of type T |
| `getIntOr(key, T, default)` | `T` | Get integer or default |
| `getFloat(key, T)` | `?T` | Get float of type T |
| `getFloatOr(key, T, default)` | `T` | Get float or default |
| `getBool(key)` | `?bool` | Get boolean or null |
| `getBoolOr(key, default)` | `bool` | Get boolean or default |
| `getObject(key)` | `?ObjectMap` | Get nested object |
| `getArray(key)` | `?[]Value` | Get array |
| `has(key)` | `bool` | Check if key exists |
| `get(key)` | `?Value` | Get raw JSON value |
| `deinit()` | `void` | Free parsed JSON |

**FetchContext Helpers:**

```zig
// Parse body as JSON (combines req.text() + JsonBody.parse())
var json = ctx.bodyJson() orelse return;
defer json.deinit();

// Shorthand for ctx.params.get(name)
const id = ctx.param("id") orelse return;
```

### Headers

```zig
const Headers = workers.Headers;

const headers = Headers.new();
defer headers.free();

headers.setText("Content-Type", "application/json");
headers.setText("X-Custom-Header", "value");
headers.append("Set-Cookie", "session=abc");
headers.append("Set-Cookie", "user=xyz");

if (headers.has("Content-Type")) {
    if (headers.getText("Content-Type")) |ct| {
        // Use content type...
    }
}

headers.delete("X-Custom-Header");
```

### Request

```zig
const Request = workers.Request;

fn handleRequest(ctx: *FetchContext) void {
    // Access incoming request
    const method = ctx.req.method();  // .Get, .Post, etc.
    const url = ctx.req.url();        // Full URL string
    const headers = ctx.req.headers();
    defer headers.free();
    
    // Get request body
    if (ctx.req.text()) |body| {
        // Use body text...
    }
    
    // Create new request
    const new_req = Request.new(.{ .text = "https://api.example.com" }, .{
        .method = .Post,
        .headers = &headers,
    });
    defer new_req.free();
}
```

### Response

```zig
const Response = workers.Response;
const String = workers.String;
const Headers = workers.Headers;

fn createResponse() void {
    const body = String.new("{\"success\":true}");
    defer body.free();
    
    const headers = Headers.new();
    defer headers.free();
    headers.setText("Content-Type", "application/json");
    
    const response = Response.new(
        .{ .string = &body },
        .{ .status = 200, .statusText = "OK", .headers = &headers },
    );
    defer response.free();
    
    // Clone response
    const cloned = response.clone();
    defer cloned.free();
    
    // Static constructors
    const redirect = Response.redirect("https://example.com", 302);
    defer redirect.free();
    
    const json = Response.json("{\"key\":\"value\"}");
    defer json.free();
}
```

### Crypto

```zig
const crypto = workers.apis;

// Generate random bytes
var buffer: [32]u8 = undefined;
crypto.getRandomValues(&buffer);

// Generate UUID
const uuid = crypto.randomUUID();
// uuid is a []const u8 like "550e8400-e29b-41d4-a716-446655440000"
```

---

## Memory Management

cf-workerz uses Zig's allocator for WASM memory. Always use `defer` to free resources:

```zig
fn example(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse return;
    defer db.free();  // Always free bindings
    
    const stmt = db.prepare("SELECT * FROM users");
    defer stmt.free();  // Always free prepared statements
    
    const result = stmt.all();
    defer result.free();  // Always free results
    
    const str = workers.String.new("hello");
    defer str.free();  // Always free strings
    
    const arr = workers.Array.new();
    defer arr.free();  // Always free arrays
    
    const obj = workers.Object.new();
    defer obj.free();  // Always free objects
    
    // Pattern: Check if value is valid before use
    // Heap pointers > 6 are valid (1-6 are reserved)
    const value = obj.get("key");
    if (value > 6) {
        const value_str = workers.String.init(value);
        defer value_str.free();
        // Use value_str.value()...
    }
}
```

---

## Examples

See the [examples directory](https://github.com/ealecho/workers-zig/tree/master/examples) for complete working examples:

- **hello-world**: Basic router example
- **todo-app**: Full CRUD with D1, Cache, KV, and AI
- **router**: Path params, wildcards, groups demo
- **r2-storage**: R2 object storage operations
- **d1-database**: SQL database operations
- **cache-api**: Cache API operations
- **queues**: Queue producer/consumer
- **service-bindings**: Worker-to-Worker communication
- **workers-ai**: AI text generation, chat, embeddings

---

## JSPI (JavaScript Promise Integration)

cf-workerz uses JSPI for async operations. JSPI is a WebAssembly standard (Phase 4, July 2024) that allows WASM to suspend and resume when calling async JavaScript functions.

**Benefits over Asyncify:**
- Zero code size overhead (Asyncify adds 25-50%)
- Near-zero runtime overhead
- No external build dependencies (no wasm-opt required)
- Simpler TypeScript runtime

**Requirements:**
- Cloudflare Workers (fully supported)
- Chrome 137+ / Firefox 139+ (for local development)

---

## Troubleshooting

### "handleFetch not exported"
Make sure your main.zig has:
```zig
export fn handleFetch(ctx_id: u32) void {
    // ...
}
```

### "memory access out of bounds"
Check that you're not using freed objects. Use `defer` consistently.

### KV/R2/D1 returns undefined
Verify your wrangler.toml has the correct bindings and the binding names match.

### Object.get() returns unexpected value
`Object.get()` returns a heap pointer (u32), not a direct value. Check if `> 6` for validity, then wrap with `String.init()` for strings.

### Array.pushNum() compile error
`pushNum` requires a type parameter: `args.pushNum(u32, value)` not `args.pushNum(value)`.

---

## Contributing

Contributions are welcome! Please see the [workers-zig repository](https://github.com/ealecho/workers-zig) for development setup.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Original work by [CraigglesO](https://github.com/CraigglesO)
- Inspired by [workers-rs](https://github.com/cloudflare/workers-rs)
