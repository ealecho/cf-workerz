# cf-workerz

A Zig library for building Cloudflare Workers with WebAssembly. Write high-performance serverless functions in Zig with full access to Cloudflare's platform APIs.

## Features

- **Cloudflare APIs**: KV, R2, D1, Cache, Queues, Service Bindings, Workers AI, Durable Objects, Rate Limiting
- **Web Crypto**: Full SubtleCrypto API - digest, encrypt, decrypt, sign, verify, key generation
- **WebSockets**: Inbound upgrades, outbound connections, hibernation support
- **Durable Objects**: Full DO support with state, storage, alarms, SQL, location hints
- **Ergonomic D1**: pg.zig-inspired query API with inline params and struct mapping
- **Built-in Router**: Path parameters, wildcards, route groups, middleware support
- **Response Helpers**: JSON, text, HTML, redirect, binary, file downloads, streaming
- **Request Helpers**: Headers, content negotiation, FormData, body streaming
- **JSPI Async**: Zero-overhead JavaScript Promise Integration (no Asyncify)
- **Tiny Binaries**: WASM output typically 10-15KB
- **Type Safe**: Full Zig type safety with compile-time route checking
- **Modern Zig**: Supports Zig 0.14+ (tested with 0.15 and 0.16)

## Requirements

- **Zig**: 0.14.0 or later
- **Runtime**: Cloudflare Workers (or Chrome 137+, Firefox 139+ for local testing)
- **Node.js**: 18+ (for wrangler CLI)

## Installation

> **Note:** Use the `main` branch for the latest features including ergonomic APIs (`ctx.param()`, `ctx.bodyJson()`, `db.query()`, etc.). A stable v0.2.0 release is coming soon.

### Via zig fetch

```bash
zig fetch --save https://github.com/ealecho/cf-workerz/archive/refs/heads/main.tar.gz
```

### Manual (build.zig.zon)

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .cf_workerz = .{
        .url = "https://github.com/ealecho/cf-workerz/archive/refs/heads/main.tar.gz",
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
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;

// Define routes
const routes: []const Route = &.{
    Route.get("/", handleRoot),
    Route.get("/hello/:name", handleHello),
    Route.post("/users", handleCreateUser),
    Route.get("/api/health", handleHealth),
};

fn handleRoot(ctx: *FetchContext) void {
    // Auto-serialize struct to JSON
    ctx.json(.{ .message = "Hello from cf-workerz!" }, 200);
}

fn handleHello(ctx: *FetchContext) void {
    // Use ctx.param() shorthand for path parameters
    const name = ctx.param("name") orelse "World";
    ctx.json(.{ .hello = name }, 200);
}

fn handleCreateUser(ctx: *FetchContext) void {
    // Parse JSON request body with ctx.bodyJson()
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const name = json.getString("name") orelse {
        ctx.json(.{ .err = "Name is required" }, 400);
        return;
    };
    const email = json.getStringOr("email", "");

    ctx.json(.{ .created = true, .name = name, .email = email }, 201);
}

fn handleHealth(ctx: *FetchContext) void {
    ctx.json(.{ .status = "healthy" }, 200);
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

### Middleware

cf-workerz supports before/after middleware hooks for cross-cutting concerns like CORS, authentication, and logging.

```zig
const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const Route = workers.Router;
const Middleware = workers.Middleware;

// CORS middleware - handles preflight and adds headers
fn corsMiddleware(ctx: *FetchContext) bool {
    if (ctx.method() == .Options) {
        const headers = workers.Headers.new();
        defer headers.free();
        headers.setText("Access-Control-Allow-Origin", "*");
        headers.setText("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        headers.setText("Access-Control-Allow-Headers", "Content-Type, Authorization");
        headers.setText("Access-Control-Max-Age", "86400");

        const res = workers.Response.new(
            .{ .none = {} },
            .{ .status = 204, .statusText = "No Content", .headers = &headers },
        );
        defer res.free();
        ctx.send(&res);
        return false; // Stop chain, request handled
    }
    return true; // Continue to next middleware/handler
}

// Auth middleware
fn authMiddleware(ctx: *FetchContext) bool {
    const token = ctx.header("Authorization") orelse {
        ctx.json(.{ .err = "Unauthorized" }, 401);
        return false; // Stop the chain
    };
    // Validate token...
    _ = token;
    return true;
}

// Create middleware chain
const middleware = Middleware{
    .before = &.{ corsMiddleware, authMiddleware },
    .after = &.{}, // Optional after-handlers
};

// Dispatch with middleware
export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatchWithMiddleware(routes, ctx, middleware);
}
```

**Middleware Return Values:**
- `return true` - Continue to next middleware or route handler
- `return false` - Stop the chain (must send response before returning)

**Note:** `ctx.json()` does NOT add CORS headers automatically. Use middleware for CORS.

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
    // Preferred: use ctx.param() shorthand (Hono-style)
    const id = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing user ID" }, 400);
        return;
    };
    
    // Alternative: access via ctx.params directly
    const name = ctx.params.get("name");
    
    // Access by index
    const first = ctx.params.getIndex(0);
    
    // Access wildcard match
    const path = ctx.params.wildcard();
    
    // Use the parameter
    ctx.json(.{ .id = id, .name = name }, 200);
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

### Query Parameters

Access query string parameters using `ctx.query()`:

```zig
fn handleSearch(ctx: *FetchContext) void {
    // GET /search?q=zig&limit=10&debug=true
    const params = ctx.query();
    defer params.free();
    
    // Get parameter values
    const q = params.get("q") orelse "";           // "zig"
    const limit = params.get("limit") orelse "20"; // "10"
    
    // Check if parameter exists
    if (params.has("debug")) {
        // debug mode enabled
    }
    
    // Count parameters
    const count = params.size(); // 3
    
    ctx.json(.{ .query = q, .limit = limit, .count = count }, 200);
}
```

### URL Access

Access the full parsed URL using `ctx.url()`:

```zig
fn handleRequest(ctx: *FetchContext) void {
    // Get parsed URL object
    const url = ctx.url();
    defer url.free();
    
    // Access URL components
    const host = url.hostname();   // "api.example.com"
    const proto = url.protocol();  // "https:"
    const path = url.pathname();   // "/api/v1/users"
    const search = url.search();   // "?page=1&limit=10"
    const port = url.port();       // "8080" or ""
    const origin = url.origin();   // "https://api.example.com:8080"
    
    ctx.json(.{ .host = host, .path = path }, 200);
}
```

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
    
    // Binary data
    const data = [_]u8{ 0x89, 0x50, 0x4E, 0x47 }; // PNG magic
    ctx.bytes(&data, 200); // application/octet-stream
    ctx.bytesWithType(&data, "image/png", 200);
    
    // File download (sets Content-Disposition header)
    ctx.file(fileData, "report.pdf", "application/pdf");
    
    // Streaming response
    const stream = getReadableStream();
    ctx.stream(&stream, "application/octet-stream", 200);
}
```

**Response Helper Methods:**

| Method | Description |
|--------|-------------|
| `ctx.json(value, status)` | JSON with auto-serialization (structs, strings, errors) |
| `ctx.text(text, status)` | Plain text response |
| `ctx.html(html, status)` | HTML response |
| `ctx.redirect(url, status)` | Redirect response (301, 302, etc.) |
| `ctx.noContent()` | 204 No Content |
| `ctx.throw(status, message)` | Error response |
| `ctx.bytes(data, status)` | Binary data (application/octet-stream) |
| `ctx.bytesWithType(data, contentType, status)` | Binary with custom content type |
| `ctx.file(data, filename, contentType)` | File download with Content-Disposition |
| `ctx.stream(readable, contentType, status)` | Streaming response |

### Request Helpers

Access request data with convenient helper methods:

```zig
fn handleRequest(ctx: *FetchContext) void {
    // Get a single header value (shorthand)
    const auth = ctx.header("Authorization") orelse {
        ctx.json(.{ .err = "Unauthorized" }, 401);
        return;
    };
    
    // Get HTTP method
    const method = ctx.method();
    if (method == .Post or method == .Put) {
        // handle body
    }
    
    // Content negotiation - check what client accepts
    if (ctx.accepts("application/json")) {
        ctx.json(.{ .data = "value" }, 200);
    } else if (ctx.accepts("text/html")) {
        ctx.html("<p>value</p>", 200);
    } else {
        ctx.text("value", 200);
    }
    
    // Parse FormData body (multipart/form-data)
    var form = ctx.bodyFormData() orelse {
        ctx.throw(400, "Invalid form data");
        return;
    };
    defer form.free();
    
    if (form.get("file")) |entry| {
        switch (entry) {
            .field => |value| { _ = value; },
            .file => |file| {
                defer file.free();
                const filename = file.name();
                const content = file.bytes();
                // Process uploaded file
            },
        }
    }
    
    // Get body as stream for large payloads
    const stream = ctx.bodyStream();
    defer stream.free();
    
    const reader = stream.getReader();
    defer reader.free();
    
    while (true) {
        const result = reader.read();
        if (result.done) break;
        if (result.value) |chunk| {
            // Process chunk
        }
    }
}
```

**Request Helper Methods:**

| Method | Return Type | Description |
|--------|-------------|-------------|
| `ctx.header(name)` | `?[]const u8` | Get single header value |
| `ctx.method()` | `Method` | HTTP method (.Get, .Post, etc.) |
| `ctx.accepts(contentType)` | `bool` | Check Accept header for content type |
| `ctx.bodyJson()` | `?JsonBody` | Parse body as JSON |
| `ctx.bodyFormData()` | `?FormData` | Parse body as FormData |
| `ctx.bodyStream()` | `ReadableStream` | Get body as stream |
| `ctx.query()` | `URLSearchParams` | Get query parameters |
| `ctx.url()` | `URL` | Get parsed URL |
| `ctx.param(name)` | `?[]const u8` | Get path parameter |

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

cf-workerz provides two APIs for D1: an **ergonomic query API** (recommended) and the lower-level **prepared statement API**.

### Ergonomic Query API (Recommended)

Inspired by [pg.zig](https://github.com/ziglang/pg.zig), the ergonomic API provides inline parameter binding and automatic struct mapping:

```zig
const workers = @import("cf-workerz");

// Define your data struct
const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    active: bool,
};

fn handleUsers(ctx: *workers.FetchContext) void {
    const db = ctx.env.d1("MY_DB") orelse {
        ctx.throw(500, "D1 not configured");
        return;
    };
    defer db.free();

    // Query multiple rows - returns iterator of typed structs
    var users = db.query(User, "SELECT * FROM users WHERE active = ?", .{true});
    defer users.deinit();

    while (users.next()) |user| {
        // user.id, user.name, user.email, user.active - fully typed!
        _ = user;
    }

    // Query single row - returns ?T
    const user = db.one(User, "SELECT * FROM users WHERE id = ?", .{123});
    if (user) |u| {
        ctx.json(.{ .id = u.id, .name = u.name, .email = u.email }, 200);
        return;
    }

    // Execute INSERT/UPDATE/DELETE - returns affected row count
    const affected = db.execute("DELETE FROM users WHERE active = ?", .{false});
    ctx.json(.{ .deleted = affected }, 200);
}
```

**Ergonomic API Methods:**

| Method | Return Type | Description |
|--------|-------------|-------------|
| `db.query(T, sql, params)` | `D1Query(T)` | Query multiple rows, returns iterator |
| `db.one(T, sql, params)` | `?T` | Query single row, returns struct or null |
| `db.execute(sql, params)` | `u64` | Execute statement, returns affected rows |

**Supported Parameter Types:**

| Type | Example | Notes |
|------|---------|-------|
| Integers | `i32`, `u32`, `i64`, `u64` | All integer types |
| Floats | `f32`, `f64` | Floating point |
| Boolean | `bool` | Converted to 0/1 |
| String | `[]const u8` | Text values |
| Null | `null` | SQL NULL |
| Optional | `?i32`, `?[]const u8` | Null if none |

**Supported Struct Field Types:**

| Type | Example | Notes |
|------|---------|-------|
| Integers | `id: u32` | Numeric columns |
| Floats | `score: f64` | Floating point columns |
| Boolean | `active: bool` | Boolean columns |
| String | `name: []const u8` | Text columns |
| Optional | `email: ?[]const u8` | Nullable columns |

**Security:** Unsupported types (structs, arrays, pointers) are rejected at **compile time** to prevent injection vulnerabilities.

### Prepared Statement API (Lower-level)

For more control, use the lower-level prepared statement API:

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

## WebSockets

WebSockets enable real-time, bidirectional communication between clients and your Worker.

### Inbound WebSocket (Server)

Handle incoming WebSocket upgrade requests:

```zig
const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const WebSocketPair = workers.WebSocketPair;
const Response = workers.Response;

fn handleWebSocket(ctx: *FetchContext) void {
    // Check if this is a WebSocket upgrade request
    const upgrade = ctx.header("Upgrade") orelse "";
    if (!std.mem.eql(u8, upgrade, "websocket")) {
        ctx.text("Expected WebSocket upgrade", 426);
        return;
    }

    // Create a WebSocket pair
    const pair = WebSocketPair.new();
    defer pair.free();

    // Get the server-side WebSocket
    var server = pair.server();
    defer server.free();

    // Accept the connection
    server.accept();

    // Send a welcome message
    server.sendText("{\"type\":\"connected\"}");

    // Get the client WebSocket for the response
    const client = pair.client();
    defer client.free();

    // Return the upgrade response
    const response = Response.webSocketUpgrade(&client);
    defer response.free();
    ctx.send(&response);
}
```

### Outbound WebSocket (Client)

Connect to external WebSocket servers:

```zig
const workers = @import("cf-workerz");

fn connectToExternalWS(ctx: *FetchContext) void {
    // Connect to an external WebSocket server
    const ws = workers.wsConnect("wss://echo.websocket.org");
    defer ws.free();

    // Send a message
    ws.sendText("Hello from Worker!");

    // Or connect with specific subprotocols
    const wsWithProtocol = workers.wsConnectWithProtocols(
        "wss://api.example.com/ws",
        &.{ "graphql-ws", "subscriptions-transport-ws" },
    );
    defer wsWithProtocol.free();

    wsWithProtocol.sendText("{\"type\":\"connection_init\"}");
}
```

### WebSocket Methods

| Method | Description |
|--------|-------------|
| `ws.accept()` | Accept an incoming connection (server-side) |
| `ws.sendText(text)` | Send a text message |
| `ws.sendBytes(data)` | Send binary data |
| `ws.close(code, reason)` | Close with code and reason |
| `ws.readyState()` | Get connection state (.Connecting, .Open, .Closing, .Closed) |

### WebSocket Close Codes

| Code | Name | Description |
|------|------|-------------|
| 1000 | NormalClosure | Normal close |
| 1001 | GoingAway | Server shutting down |
| 1002 | ProtocolError | Protocol error |
| 1003 | UnsupportedData | Invalid data type |
| 1008 | PolicyViolation | Policy violation |
| 1011 | InternalError | Server error |

---

## Durable Objects

Durable Objects provide strongly consistent, globally distributed coordination and storage. Each DO instance is single-threaded and has its own persistent storage.

### Accessing a Durable Object

```zig
fn handleDO(ctx: *FetchContext) void {
    // Get the DO namespace from environment
    const namespace = ctx.env.durableObject("MY_DO") orelse {
        ctx.throw(500, "DO not configured");
        return;
    };
    defer namespace.free();

    // Get a DO instance by name (deterministic - same name = same DO)
    const id = namespace.idFromName("room:lobby");
    defer id.free();

    // Get a stub to communicate with the DO
    const stub = id.getStub();
    defer stub.free();

    // Make a request to the DO
    const response = stub.fetch(.{ .text = "https://do/join" }, null);
    defer response.free();

    // Forward the response
    ctx.send(&response);
}
```

### Location Hints

Optimize latency by hinting where the Durable Object should run:

```zig
fn useDOWithLocationHint(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("MY_DO") orelse return;
    defer namespace.free();

    // Get stub with location hint for lower latency
    const stub = namespace.getWithLocationHint("user:123", "enam"); // Eastern North America
    defer stub.free();

    const response = stub.fetch(.{ .text = "https://do/action" }, null);
    defer response.free();
    ctx.send(&response);
}
```

**Location Hint Values:**
| Hint | Region |
|------|--------|
| `wnam` | Western North America |
| `enam` | Eastern North America |
| `sam` | South America |
| `weur` | Western Europe |
| `eeur` | Eastern Europe |
| `apac` | Asia Pacific |
| `oc` | Oceania |
| `afr` | Africa |
| `me` | Middle East |

### Durable Object Alarms

Schedule code to run at a specific time:

```zig
fn setupAlarm(storage: *workers.DurableObjectStorage) void {
    // Using ScheduledTime helper for convenient scheduling
    const time = workers.ScheduledTime.fromOffsetMins(5);  // 5 minutes from now
    storage.setAlarmWithOptions(time.toTimestamp(), .{});

    // Other offset helpers
    _ = workers.ScheduledTime.fromOffsetSecs(30);   // 30 seconds
    _ = workers.ScheduledTime.fromOffsetHours(1);   // 1 hour
    _ = workers.ScheduledTime.fromOffsetMs(500);    // 500ms

    // Get current alarm
    if (storage.getAlarmWithOptions(.{ .allowConcurrency = true })) |alarm| {
        _ = alarm;
    }

    // Delete alarm
    storage.deleteAlarmWithOptions(.{ .allowConcurrency = true });
}
```

### SQL Storage (SQLite)

Durable Objects support SQLite-backed storage for relational data:

```zig
fn useSqlStorage(storage: *workers.DurableObjectStorage) void {
    // Get SQL interface
    const sql = storage.sql();
    defer sql.free();

    // Execute DDL/DML without results
    sql.exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)");

    // Execute with parameters
    sql.execWithParams("INSERT INTO users (name) VALUES (?)", &.{"Alice"});

    // Query with cursor
    var cursor = sql.exec("SELECT * FROM users WHERE id > ?");
    defer cursor.free();

    // Iterate rows
    while (cursor.next()) |row| {
        defer row.free();
        if (row.get("name")) |name| {
            _ = name;
        }
    }

    // Get statistics
    const dbSize = sql.databaseSize();
    _ = dbSize;
}
```

### WebSocket Hibernation (Durable Objects)

For WebSockets in Durable Objects, use hibernation for efficiency:

```zig
fn acceptHibernatingWebSocket(state: *workers.DurableObjectState, ws: *workers.WebSocket) void {
    // Accept with optional tags for filtering
    state.acceptWebSocket(ws, &.{ "room:lobby", "user:123" });

    // Get all WebSockets
    var allWs = state.getWebSockets(null);
    defer allWs.free();
    while (allWs.next()) |socket| {
        defer socket.free();
        socket.sendText("broadcast message");
    }

    // Get WebSockets by tag
    var roomWs = state.getWebSockets("room:lobby");
    defer roomWs.free();
    while (roomWs.next()) |socket| {
        defer socket.free();
        socket.sendText("room message");
    }
}
```

**wrangler.toml configuration:**
```toml
[[durable_objects.bindings]]
name = "MY_DO"
class_name = "MyDurableObject"

[[migrations]]
tag = "v1"
new_classes = ["MyDurableObject"]
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

## Rate Limiting

The Rate Limiting API lets you enforce rate limits directly from your Worker. Limits are applied per Cloudflare location for low latency.

```zig
const workers = @import("cf-workerz");

fn handleRequest(ctx: *workers.FetchContext) void {
    const limiter = ctx.env.rateLimiter("MY_RATE_LIMITER") orelse {
        ctx.throw(500, "Rate limiter not configured");
        return;
    };
    defer limiter.free();

    // Use a unique key to identify the actor (user ID, API key, etc.)
    const user_id = ctx.header("X-User-ID") orelse "anonymous";
    const outcome = limiter.limit(user_id);

    if (!outcome.success) {
        ctx.json(.{ .error = "Rate limit exceeded" }, 429);
        return;
    }

    ctx.json(.{ .message = "Success!" }, 200);
}
```

### Key Selection

Choose keys that uniquely identify the actor you want to rate limit:

| Key Type | Example | Use Case |
|----------|---------|----------|
| User ID | `"user:123"` | Per-user limiting |
| API Key | `"apikey:abc123"` | Per-client limiting |
| User + Route | `"user:123:/api/expensive"` | Per-endpoint limiting |

**Note:** Avoid using IP addresses as keys since many users may share an IP (e.g., corporate networks, mobile carriers).

### Locality

Rate limits are enforced **per Cloudflare location**. A user hitting your Worker from Sydney has a separate limit from one in London. This design provides:
- Very low latency (no cross-datacenter coordination)
- High availability
- Approximate global limiting (good enough for most use cases)

### Configuration

```toml
# wrangler.toml
[[ratelimits]]
name = "MY_RATE_LIMITER"
namespace_id = "1001"
simple = { limit = 100, period = 60 }
```

| Parameter | Description |
|-----------|-------------|
| `name` | Binding name to access in code |
| `namespace_id` | Unique identifier for this limiter |
| `limit` | Maximum requests allowed in the period |
| `period` | Time window in seconds (**10 or 60 only**) |

---

## Additional APIs

### JsonBody (Request Parsing)

The `JsonBody` helper provides Hono-style ergonomic JSON request parsing:

```zig
const workers = @import("cf-workerz");

fn handleCreateUser(ctx: *workers.FetchContext) void {
    // Parse request body as JSON
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();
    
    // Get required string field
    const name = json.getString("name") orelse {
        ctx.json(.{ .err = "Name is required" }, 400);
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

#### Random Values and UUID

```zig
const crypto = workers.apis;

// Generate random bytes
var buffer: [32]u8 = undefined;
crypto.getRandomValues(&buffer);

// Generate UUID
const uuid = crypto.randomUUID();
// uuid is a []const u8 like "550e8400-e29b-41d4-a716-446655440000"
```

#### SubtleCrypto API

The full Web Crypto SubtleCrypto API is available for cryptographic operations:

```zig
const workers = @import("cf-workerz");

fn handleCrypto(ctx: *FetchContext) void {
    // Get the SubtleCrypto object
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    // Hash data with digest()
    if (subtle.digest(.@"SHA-256", "hello world")) |hash| {
        // hash is []const u8 containing the digest
        ctx.bytes(hash, 200);
    }
}
```

#### Convenience Hash Functions

```zig
// One-liner hash functions
const hash256 = workers.sha256("hello world");  // SHA-256
const hash1 = workers.sha1("hello world");      // SHA-1
const hash512 = workers.sha512("hello world");  // SHA-512
const hashMd5 = workers.md5("hello world");     // MD5
```

#### HMAC Sign and Verify

```zig
fn hmacSign(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    const secretKey = "my-secret-key";
    const message = "data to sign";

    // Import the key for HMAC
    const importAlgo = workers.SubtleCryptoImportKeyAlgorithm{
        .name = "HMAC",
        .hash = .{ .name = "SHA-256" },
    };

    if (subtle.importKey(.raw, secretKey, &importAlgo, false, &.{.sign})) |key| {
        defer key.free();

        // Sign the message
        const signAlgo = workers.SubtleCryptoSignAlgorithm{ .name = "HMAC" };
        if (subtle.sign(&signAlgo, &key, message)) |signature| {
            ctx.bytes(signature, 200);
        }
    }
}

fn hmacVerify(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    const importAlgo = workers.SubtleCryptoImportKeyAlgorithm{
        .name = "HMAC",
        .hash = .{ .name = "SHA-256" },
    };

    if (subtle.importKey(.raw, secretKey, &importAlgo, false, &.{.verify})) |key| {
        defer key.free();

        const signAlgo = workers.SubtleCryptoSignAlgorithm{ .name = "HMAC" };
        const isValid = subtle.verify(&signAlgo, &key, signature, message);
        ctx.json(.{ .valid = isValid }, 200);
    }
}
```

#### AES-GCM Encryption

```zig
fn aesEncrypt(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    // Generate an AES-256-GCM key
    const genAlgo = workers.SubtleCryptoGenerateKeyAlgorithm{
        .name = "AES-GCM",
        .length = 256,
    };

    if (subtle.generateKey(&genAlgo, true, &.{ .encrypt, .decrypt })) |key| {
        defer key.free();

        // Generate IV (12 bytes for AES-GCM)
        var iv: [12]u8 = undefined;
        workers.getRandomValues(&iv);

        // Encrypt
        const encryptAlgo = workers.SubtleCryptoEncryptAlgorithm{
            .name = "AES-GCM",
            .iv = &iv,
        };

        if (subtle.encrypt(&encryptAlgo, &key, "secret message")) |ciphertext| {
            // ciphertext contains encrypted data + auth tag
            ctx.bytes(ciphertext, 200);
        }
    }
}
```

#### Key Import/Export

```zig
fn keyOperations(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    // Import raw key bytes
    const keyBytes = [_]u8{ 0x00, 0x01, 0x02, ... }; // 32 bytes for AES-256
    const importAlgo = workers.SubtleCryptoImportKeyAlgorithm{
        .name = "AES-GCM",
        .length = 256,
    };

    if (subtle.importKey(.raw, &keyBytes, &importAlgo, true, &.{ .encrypt, .decrypt })) |key| {
        defer key.free();

        // Export key back to raw bytes
        if (subtle.exportKey(.raw, &key)) |exported| {
            // exported is []const u8
            _ = exported;
        }

        // Export as JWK
        if (subtle.exportKey(.jwk, &key)) |jwk| {
            // jwk is JSON string
            _ = jwk;
        }
    }
}
```

#### Key Derivation (PBKDF2, HKDF)

```zig
fn deriveKey(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    const password = "user-password";
    var salt: [16]u8 = undefined;
    workers.getRandomValues(&salt);

    // Import password as key material
    const importAlgo = workers.SubtleCryptoImportKeyAlgorithm{ .name = "PBKDF2" };

    if (subtle.importKey(.raw, password, &importAlgo, false, &.{.deriveKey})) |baseKey| {
        defer baseKey.free();

        // Derive an AES key from password
        const deriveAlgo = workers.SubtleCryptoDeriveKeyAlgorithm{
            .name = "PBKDF2",
            .salt = &salt,
            .iterations = 100000,
            .hash = .{ .name = "SHA-256" },
        };

        const derivedAlgo = workers.SubtleCryptoGenerateKeyAlgorithm{
            .name = "AES-GCM",
            .length = 256,
        };

        if (subtle.deriveKey(&deriveAlgo, &baseKey, &derivedAlgo, true, &.{ .encrypt, .decrypt })) |derivedKey| {
            defer derivedKey.free();
            // Use derivedKey for encryption...
        }
    }
}
```

#### RSA Key Pairs

```zig
fn rsaKeyPair(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    // Generate RSA-OAEP key pair
    const genAlgo = workers.SubtleCryptoGenerateKeyAlgorithm{
        .name = "RSA-OAEP",
        .modulusLength = 2048,
        .publicExponent = &.{ 0x01, 0x00, 0x01 }, // 65537
        .hash = .{ .name = "SHA-256" },
    };

    if (subtle.generateKeyPair(&genAlgo, true, &.{ .encrypt, .decrypt })) |pair| {
        defer pair.free();

        const publicKey = pair.publicKey();
        const privateKey = pair.privateKey();
        defer publicKey.free();
        defer privateKey.free();

        // Encrypt with public key
        const encAlgo = workers.SubtleCryptoEncryptAlgorithm{ .name = "RSA-OAEP" };
        if (subtle.encrypt(&encAlgo, &publicKey, "secret")) |encrypted| {
            _ = encrypted;
        }
    }
}
```

#### Timing-Safe Comparison

```zig
fn verifyToken(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    const expected = "secret-token-value";
    const provided = ctx.header("X-Token") orelse "";

    // Constant-time comparison (prevents timing attacks)
    const isValid = subtle.timingSafeEqual(expected, provided);
    if (!isValid) {
        ctx.throw(401, "Invalid token");
        return;
    }
    ctx.json(.{ .authenticated = true }, 200);
}
```

#### Supported Algorithms

| Category | Algorithms |
|----------|------------|
| **Digest** | SHA-1, SHA-256, SHA-384, SHA-512, MD5 |
| **HMAC** | HMAC with any digest algorithm |
| **AES** | AES-GCM, AES-CBC, AES-CTR, AES-KW |
| **RSA** | RSA-OAEP, RSASSA-PKCS1-v1_5, RSA-PSS |
| **ECDSA** | P-256, P-384, P-521 curves |
| **ECDH** | P-256, P-384, P-521 curves |
| **Key Derivation** | PBKDF2, HKDF |

#### Key Formats

| Format | Description |
|--------|-------------|
| `raw` | Raw key bytes |
| `pkcs8` | PKCS#8 private key |
| `spki` | SubjectPublicKeyInfo public key |
| `jwk` | JSON Web Key |

#### Key Usages

| Usage | Description |
|-------|-------------|
| `encrypt` | Encrypt data |
| `decrypt` | Decrypt data |
| `sign` | Create signatures |
| `verify` | Verify signatures |
| `deriveKey` | Derive new keys |
| `deriveBits` | Derive raw bits |
| `wrapKey` | Wrap (encrypt) keys |
| `unwrapKey` | Unwrap (decrypt) keys |

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

See the [examples directory](https://github.com/ealecho/cf-workerz/tree/master/examples) for complete working examples:

- **hello-world**: Basic router example with path parameters and JSON responses
- **websocket-client**: Outbound WebSocket connections and inbound upgrades
- **websocket-chat**: Real-time chat with WebSockets and Durable Objects + React client ([Live Demo](https://websocket-chat-client.pages.dev))
- **durable-objects**: Location hints, alarms, SQL storage, counter DO
- **crypto**: SubtleCrypto API - hashing, HMAC, AES encryption, key derivation
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

## Security Considerations

### CORS

`ctx.json()` does **not** add CORS headers automatically. You must use middleware to handle CORS:

```zig
fn corsMiddleware(ctx: *FetchContext) bool {
    if (ctx.method() == .Options) {
        const headers = workers.Headers.new();
        defer headers.free();
        headers.setText("Access-Control-Allow-Origin", "*");
        headers.setText("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        headers.setText("Access-Control-Allow-Headers", "Content-Type, Authorization");
        
        const res = workers.Response.new(
            .{ .none = {} },
            .{ .status = 204, .statusText = "No Content", .headers = &headers },
        );
        defer res.free();
        ctx.send(&res);
        return false;
    }
    return true;
}
```

### File Downloads

Filenames passed to `ctx.file()` are automatically sanitized to prevent HTTP header injection. The following characters are replaced with underscores:
- Quotes (`"`)
- Backslashes (`\`)
- Carriage returns and newlines (`\r`, `\n`)
- Control characters (< 32) and DEL (127)

### JSON Response Size

JSON responses use a tiered buffer strategy:
- **Stack buffer**: 4KB (fast path for small responses)
- **Heap fallback**: Up to 1MB for larger responses
- Responses exceeding 1MB return a 500 error

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

## Feature Parity with workers-rs

cf-workerz aims for feature parity with [workers-rs](https://github.com/cloudflare/workers-rs), the official Rust SDK for Cloudflare Workers.

> **Current Status: ~95% feature parity**
>
> All core Cloudflare APIs are fully implemented including KV, R2, D1, Cache, Queues, AI, Service Bindings, **Durable Objects**, **WebSockets**, **SubtleCrypto**, and **Rate Limiting**.
> Remaining gaps: Hyperdrive, Vectorize, RPC.

### Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | **Complete** - Production-ready, full API coverage |
| ⚠️ | **Partial** - Works but missing some methods/features |
| ❌ | **Stub** - Exists but not functional (init/free only) |
| ➖ | **Not Started** - No implementation yet |

---

### Fully Implemented (✅)

These features are complete and production-ready:

| Feature | workers-rs | cf-workerz | Notes |
|---------|-----------|------------|-------|
| **Storage** | | | |
| KV Namespace | ✅ | ✅ | Full CRUD, list, metadata, TTL expiration |
| R2 Bucket | ✅ | ✅ | Get, put, delete, list, head, conditional requests |
| D1 Database | ✅ | ✅ | Prepared statements, batch, **ergonomic query API** |
| Cache API | ✅ | ✅ | Match, put, delete |
| **Messaging** | | | |
| Queues (Producer) | ✅ | ✅ | send, sendWithOptions, sendBatch |
| Queues (Consumer) | ✅ | ✅ | Message iteration, ack, retry, batch ops |
| **Compute** | | | |
| Service Bindings | ✅ | ✅ | Worker-to-Worker via Fetcher API |
| Workers AI | ✅ | ✅ | Text gen, chat, embeddings, translation, summarization |
| Scheduled Events | ✅ | ✅ | Cron triggers via handleSchedule |
| **HTTP** | | | |
| Fetch API | ✅ | ✅ | Global fetch with Request/Response |
| Request | ✅ | ✅ | Method, URL, headers, body (text/json/bytes) |
| Response | ✅ | ✅ | Status, headers, body, clone, redirect, json |
| **Routing** | | | |
| Path Parameters | ✅ | ✅ | `/users/:id` with ctx.param() |
| Wildcards | ✅ | ✅ | `/files/*path` with params.wildcard() |
| Route Groups | ✅ | ✅ | `Route.group("/api", routes)` |
| Middleware | ✅ | ✅ | Before/after hooks with `dispatchWithMiddleware()` |
| Response Helpers | ✅ | ✅ | json, text, html, redirect, noContent, throw |
| **Utilities** | | | |
| CF Properties | ✅ | ✅ | Geo, colo, ASN, bot score, etc. |
| crypto.randomUUID | ✅ | ✅ | Generate UUIDs |
| crypto.getRandomValues | ✅ | ✅ | Cryptographic random bytes |
| **SubtleCrypto** | ✅ | ✅ | digest, encrypt, decrypt, sign, verify, generateKey, importKey, exportKey, deriveKey, deriveBits, wrapKey, unwrapKey |
| Execution Context | ✅ | ✅ | waitUntil, passThroughOnException |
| **Web APIs** | | | |
| URL | ✅ | ✅ | Parsing, properties, setters, searchParams |
| URLSearchParams | ✅ | ✅ | Full CRUD, iteration, toString |
| FormData | ✅ | ✅ | Get, set, append, delete, has, keys/values |
| File | ✅ | ✅ | name, size, type, lastModified, text, bytes |
| **Rate Limiting** | | | |
| Rate Limiter | ✅ | ✅ | limit() with per-location enforcement |

---

### Not Started (➖)

These features exist in workers-rs but have no implementation in cf-workerz:

| Feature | workers-rs | Priority | Notes |
|---------|-----------|----------|-------|
| Workflows | ➖ No | 🔴 Not Planned | Durable multi-step execution; class-based API incompatible with WASM |
| RPC Support | ✅ Experimental | 🟡 Medium | Worker-to-Worker RPC |
| Hyperdrive | ✅ | 🟡 Medium | PostgreSQL connection pooling |
| Vectorize | ✅ | 🟡 Medium | Vector database for AI apps |
| Analytics Engine | ✅ | 🟢 Low | Custom analytics/metrics |
| Browser Rendering | ✅ | 🟢 Low | Puppeteer-like API |
| Email Workers | ✅ | 🟢 Low | Inbound email handling |
| mTLS | ✅ | 🟢 Low | Client certificates |
| TCP Sockets | ✅ | 🟢 Low | Raw TCP connections |

---

### cf-workerz Advantages

Features unique to cf-workerz (not available in workers-rs):

| Feature | Description |
|---------|-------------|
| **Ergonomic D1 API** | pg.zig-inspired `db.query(User, sql, params)` with automatic struct mapping |
| **JSPI Async** | Zero-overhead async via JavaScript Promise Integration (no Asyncify bloat) |
| **JsonBody Helper** | Hono-style `ctx.bodyJson()` with typed getters (`getString`, `getInt`, etc.) |
| **Tiny Binaries** | 10-15KB WASM output vs 100KB+ for Rust workers |
| **No Macros** | Pure Zig without proc-macro complexity |
| **LSP Documentation** | Comprehensive hover docs for all APIs |
| **ScheduledTime Helper** | Convenient alarm scheduling with `fromOffsetSecs()`, `fromOffsetMins()`, `fromOffsetHours()` |
| **DO Location Hints** | Optimize latency with `getWithLocationHint()` for Durable Objects |
| **Convenience Hash Functions** | One-liner `sha256()`, `sha1()`, `sha512()`, `md5()` functions |

---

### Side-by-Side Comparison

| Aspect | workers-rs (Rust) | cf-workerz (Zig) |
|--------|------------------|------------------|
| Binary Size | ~100-500KB | ~10-15KB |
| Compile Time | ~30-60s | ~1-3s |
| Async Model | tokio-style (Asyncify) | JSPI (native) |
| Type Safety | ✅ Strong | ✅ Strong |
| Learning Curve | Moderate (Rust) | Lower (Zig) |
| Ecosystem | Large (crates.io) | Growing |
| Axum/http compat | ✅ Yes | ➖ No (different ecosystem) |
| Feature Parity | 100% (official) | ~95% |

---

## Roadmap

### v0.2.0 (Next Release) - Core Gaps

Focus: Close the critical feature gaps

- [x] **Durable Objects** - Full implementation with state/storage ✅
- [x] **DO Location Hints** - Optimize latency with location hints ✅
- [x] **DO SQL Storage** - SQLite-backed storage with SqlCursor ✅
- [x] **DO Alarms** - Scheduled alarms with ScheduledTime helper ✅
- [x] **WebSocket (Inbound)** - WebSocketPair, accept, send, close ✅
- [x] **WebSocket (Outbound)** - Connect to external WebSocket servers ✅
- [x] **WebSocket Events** - MessageEvent, CloseEvent, ErrorEvent ✅
- [x] **WebSocket Hibernation** - DO WebSocket hibernation support ✅
- [x] **FormData** - Parse multipart, file uploads ✅
- [x] **URL/URLSearchParams** - Full URL manipulation API ✅
- [x] **Middleware** - Before/after hooks for router ✅
- [x] **Headers Iteration** - keys(), values(), entries() iterators ✅
- [x] **SubtleCrypto** - Encrypt, decrypt, sign, verify, hash ✅

### v0.3.0 - Extended APIs

- [ ] Hyperdrive support (PostgreSQL connection pooling)
- [ ] Vectorize support (Vector database)
- [ ] RPC support (Worker-to-Worker RPC)

### v0.4.0 - Advanced Features

- [x] Rate Limiting API ✅
- [ ] Browser Rendering API
- [ ] Email Workers support

### Not Planned

These features are not planned for cf-workerz due to architectural incompatibility with WASM:

| Feature | Reason |
|---------|--------|
| **Workflows** | Requires class-based inheritance (`extends WorkflowEntrypoint`) incompatible with WASM. Even workers-rs doesn't support it. Use Durable Objects for durable execution needs. |

### v1.0.0 (Stable)

- [ ] Full workers-rs feature parity
- [ ] Comprehensive test suite
- [ ] Production stability guarantees
- [ ] Semantic versioning

---

## Contributing

### Help Wanted: Priority Features

We welcome contributions! These features have the highest impact:

| Feature | Complexity | Good First Issue? |
|---------|-----------|-------------------|
| Hyperdrive | Medium | No |
| Vectorize | Medium | No |
| RPC Support | High | No |

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, or open an [issue](https://github.com/ealecho/cf-workerz/issues) to discuss!

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Original work by [CraigglesO](https://github.com/CraigglesO)
- Inspired by [workers-rs](https://github.com/cloudflare/workers-rs)
