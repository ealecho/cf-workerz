# cf-workerz LLM Reference

> This document is optimized for LLMs/AI agents. It provides concise, copy-paste ready code patterns for building Cloudflare Workers in Zig.

## Quick Facts

- **Language**: Zig (0.14+)
- **Target**: WebAssembly (wasm32-freestanding)
- **Runtime**: Cloudflare Workers with JSPI
- **Binary Size**: ~10-15KB WASM

## Installation

```zig
// build.zig.zon
.dependencies = .{
    .cf_workerz = .{
        .url = "https://github.com/ealecho/cf-workerz/archive/refs/heads/main.tar.gz",
        .hash = "...", // run: zig fetch --save <url>
    },
},
```

## Minimal Worker

```zig
const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const Route = workers.Router;

const routes: []const Route = &.{
    Route.get("/", handleRoot),
};

fn handleRoot(ctx: *FetchContext) void {
    ctx.json(.{ .message = "Hello from cf-workerz!" }, 200);
}

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
```

## Router Patterns

### Route Definition

```zig
const routes: []const Route = &.{
    // Static routes
    Route.get("/", handleRoot),
    Route.post("/users", createUser),
    Route.put("/users/:id", updateUser),
    Route.delete("/users/:id", deleteUser),
    
    // Path parameters
    Route.get("/users/:id", getUser),
    Route.get("/users/:userId/posts/:postId", getPost),
    
    // Wildcards
    Route.get("/files/*path", serveFile),
    
    // Route groups
    Route.group("/api/v1", &.{
        Route.get("/health", health),
        Route.get("/users", listUsers),
    }),
    
    // Any HTTP method
    Route.all("/webhook", handleWebhook),
};
```

### Path Parameters

```zig
fn getUser(ctx: *FetchContext) void {
    // Preferred: ctx.param() shorthand
    const id = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing id" }, 400);
        return;
    };
    
    // Alternative: ctx.params.get()
    const name = ctx.params.get("name");
    
    // Wildcard match
    const path = ctx.params.wildcard();
    
    ctx.json(.{ .id = id }, 200);
}
```

### Query Parameters

```zig
// GET /search?q=zig&limit=10&debug=true
fn handleSearch(ctx: *FetchContext) void {
    // Get query parameters with ctx.query()
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

```zig
fn handleRequest(ctx: *FetchContext) void {
    // Get full parsed URL with ctx.url()
    const url = ctx.url();
    defer url.free();
    
    // Access URL components
    const host = url.hostname();   // "api.example.com"
    const proto = url.protocol();  // "https:"
    const path = url.pathname();   // "/api/v1/users"
    const search = url.search();   // "?page=1&limit=10"
    const port = url.port();       // "8080" or ""
    const origin = url.origin();   // "https://api.example.com:8080"
    
    ctx.json(.{
        .host = host,
        .path = path,
        .search = search,
    }, 200);
}
```

## Response Helpers

```zig
fn examples(ctx: *FetchContext) void {
    // JSON with auto-serialization (structs, anonymous structs)
    ctx.json(.{ .id = 1, .name = "Alice" }, 200);
    ctx.json(.{ .created = true }, 201);
    
    // Raw JSON string
    ctx.json("{\"raw\":true}", 200);
    
    // Error to JSON: {"error": "NotFound"}
    ctx.json(error.NotFound, 404);
    
    // Plain text
    ctx.text("Hello, World!", 200);
    
    // HTML
    ctx.html("<h1>Hello</h1>", 200);
    
    // Redirect
    ctx.redirect("/new-path", 302);
    
    // No content
    ctx.noContent(); // 204
    
    // Error with message
    ctx.throw(500, "Internal error");
}
```

## Request Body Parsing

```zig
fn createUser(ctx: *FetchContext) void {
    // Parse JSON body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON" }, 400);
        return;
    };
    defer json.deinit();
    
    // Required string field
    const name = json.getString("name") orelse {
        ctx.json(.{ .err = "Name required" }, 400);
        return;
    };
    
    // Optional with default
    const role = json.getStringOr("role", "user");
    
    // Typed numbers
    const age = json.getInt("age", u32) orelse 0;
    const score = json.getFloat("score", f64) orelse 0.0;
    
    // Boolean
    const active = json.getBool("active") orelse true;
    
    // Check existence
    if (json.has("metadata")) {
        // Field exists
    }
    
    // Nested object
    if (json.getObject("address")) |addr| {
        _ = addr.get("city");
    }
    
    // Array
    if (json.getArray("tags")) |tags| {
        for (tags.items) |tag| {
            if (tag == .string) {
                _ = tag.string;
            }
        }
    }
    
    ctx.json(.{ .created = true, .name = name, .role = role }, 201);
}
```

## D1 Database

### Ergonomic API (Recommended)

```zig
const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    active: bool,
};

fn handleUsers(ctx: *FetchContext) void {
    const db = ctx.env.d1("MY_DB") orelse {
        ctx.throw(500, "D1 not configured");
        return;
    };
    defer db.free();

    // Query multiple rows -> iterator
    var users = db.query(User, "SELECT * FROM users WHERE active = ?", .{true});
    defer users.deinit();
    while (users.next()) |user| {
        // user.id, user.name, user.email, user.active
        _ = user;
    }

    // Query single row -> ?T
    if (db.one(User, "SELECT * FROM users WHERE id = ?", .{123})) |user| {
        ctx.json(.{ .id = user.id, .name = user.name }, 200);
        return;
    }

    // Execute INSERT/UPDATE/DELETE -> affected rows
    const deleted = db.execute("DELETE FROM users WHERE active = ?", .{false});
    ctx.json(.{ .deleted = deleted }, 200);
}
```

### Supported Parameter Types

| Type | Example |
|------|---------|
| Integers | `i32`, `u32`, `i64`, `u64` |
| Floats | `f32`, `f64` |
| Boolean | `bool` (converts to 0/1) |
| String | `[]const u8` |
| Null | `null` |
| Optional | `?i32`, `?[]const u8` |

### Prepared Statement API (Lower-level)

```zig
fn handleD1(ctx: *FetchContext) void {
    const db = ctx.env.d1("MY_DB") orelse return;
    defer db.free();

    const stmt = db.prepare("SELECT * FROM users WHERE id = ?");
    defer stmt.free();

    const args = workers.Array.new();
    defer args.free();
    args.pushNum(u32, 123);

    const bound = stmt.bind(&args);
    defer bound.free();

    // First row
    const row = bound.first(null);
    defer row.free();

    // All rows
    const result = bound.all();
    defer result.free();
    if (result.results()) |results| {
        defer results.free();
        while (results.next(workers.Object)) |r| {
            defer r.free();
            // process row
        }
    }

    // Run (INSERT/UPDATE/DELETE)
    const run_result = bound.run();
    defer run_result.free();
    const changes = run_result.changes();
    const last_id = run_result.lastRowId();
    _ = changes;
    _ = last_id;
}
```

## KV Storage

```zig
fn handleKV(ctx: *FetchContext) void {
    const kv = ctx.env.kv("MY_KV") orelse return;
    defer kv.free();

    // Get
    if (kv.getText("key", .{})) |value| {
        _ = value;
    }

    // Put
    kv.put("key", .{ .text = "value" }, .{});

    // Put with TTL (seconds)
    kv.put("temp", .{ .text = "expires" }, .{ .expirationTtl = 3600 });

    // Delete
    kv.delete("key");

    // List
    const list = kv.list(.{ .prefix = "user:", .limit = 100 });
    defer list.free();
}
```

## R2 Object Storage

```zig
fn handleR2(ctx: *FetchContext) void {
    const bucket = ctx.env.r2("MY_BUCKET") orelse return;
    defer bucket.free();

    // Put
    const obj = bucket.put("key", .{ .text = "content" }, .{});
    defer obj.free();

    // Get
    const result = bucket.get("key", .{});
    defer result.free();
    switch (result) {
        .r2objectBody => |body| {
            const data = body.text();
            _ = data;
        },
        .r2object => |_| {}, // conditional request - not modified
        .none => {},         // not found
    }

    // Delete
    bucket.delete("key");

    // Head (metadata only)
    if (bucket.head("key")) |head| {
        defer head.free();
        const size = head.size();
        _ = size;
    }

    // List
    const list = bucket.list(.{ .limit = 100, .prefix = "uploads/" });
    defer list.free();
}
```

## Cache API

```zig
fn handleCache(ctx: *FetchContext) void {
    const cache = workers.Cache.new(.{ .none = {} });
    defer cache.free();

    const url = "https://cache.local/key";

    // Match (get cached)
    if (cache.match(.{ .text = url }, .{})) |cached| {
        defer cached.free();
        const body = cached.text();
        _ = body;
        return;
    }

    // Put (cache response)
    const req = workers.Request.new(.{ .text = url }, .{ .none = {} });
    defer req.free();

    const headers = workers.Headers.new();
    defer headers.free();
    headers.setText("Cache-Control", "public, max-age=60");

    const body = workers.String.new("{\"cached\":true}");
    defer body.free();

    const response = workers.Response.new(
        .{ .string = &body },
        .{ .status = 200, .statusText = "OK", .headers = &headers },
    );
    defer response.free();

    cache.put(.{ .request = &req }, &response);

    // Delete
    _ = cache.delete(.{ .text = url }, .{});
}
```

## Queues

### Producer

```zig
fn sendToQueue(ctx: *FetchContext) void {
    const queue = ctx.env.queue("MY_QUEUE") orelse return;
    defer queue.free();

    // Single message
    queue.send("{\"action\":\"process\"}");

    // With options
    queue.sendWithOptions("{\"priority\":\"high\"}", .{
        .contentType = .json,
        .delaySeconds = 60,
    });

    // Batch
    const messages = [_]workers.MessageSendRequest{
        .{ .body = "{\"id\":1}", .contentType = .json },
        .{ .body = "{\"id\":2}", .contentType = .json },
    };
    queue.sendBatch(&messages);
}
```

### Consumer

```zig
export fn handleQueue(batch_ptr: u32) void {
    const batch = workers.MessageBatch.init(batch_ptr);
    defer batch.free();

    var messages = batch.messages();
    defer messages.free();

    while (messages.next()) |msg| {
        defer msg.free();

        const body = msg.body();
        const attempts = msg.attempts();
        _ = body;
        _ = attempts;

        msg.ack();    // success
        // msg.retry(); // retry later
    }

    // Or batch: batch.ackAll(); / batch.retryAll();
}
```

## Service Bindings

```zig
fn callService(ctx: *FetchContext) void {
    const backend = ctx.env.service("BACKEND") orelse return;
    defer backend.free();

    // GET
    const response = backend.fetch(.{ .text = "https://internal/api" }, null);
    defer response.free();
    const body = response.text() orelse "";
    _ = body;

    // POST
    const post_body = workers.String.new("{\"data\":true}");
    defer post_body.free();

    const headers = workers.Headers.new();
    defer headers.free();
    headers.setText("Content-Type", "application/json");

    const post_response = backend.fetch(.{ .text = "https://internal/api" }, .{
        .requestInit = .{
            .method = .Post,
            .body = .{ .string = &post_body },
            .headers = headers,
        },
    });
    defer post_response.free();
}
```

## Workers AI

```zig
fn handleAI(ctx: *FetchContext) void {
    const ai = ctx.env.ai("AI") orelse return;
    defer ai.free();

    // Text generation
    if (ai.textGeneration(
        "@cf/meta/llama-3.1-8b-instruct",
        "Write a haiku",
        .{ .max_tokens = 100 },
    )) |result| {
        defer result.free();
        if (result.response()) |text| {
            ctx.json(.{ .text = text }, 200);
            return;
        }
    }

    // Chat
    const messages = [_]workers.ChatMessage{
        .{ .role = "system", .content = "You are helpful" },
        .{ .role = "user", .content = "Hello!" },
    };
    if (ai.chat("@cf/meta/llama-3.1-8b-instruct", &messages, .{})) |result| {
        defer result.free();
        // use result
        _ = result;
    }

    // Embeddings
    if (ai.textEmbeddings("@cf/baai/bge-base-en-v1.5", "text")) |result| {
        defer result.free();
        _ = result;
    }

    ctx.throw(500, "AI failed");
}
```

## Memory Management

Always use `defer` to free resources:

```zig
fn example(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse return;
    defer db.free();

    const stmt = db.prepare("SELECT * FROM users");
    defer stmt.free();

    const str = workers.String.new("hello");
    defer str.free();

    const arr = workers.Array.new();
    defer arr.free();

    const obj = workers.Object.new();
    defer obj.free();

    // Check heap pointer validity (> 6 is valid)
    const value = obj.get("key");
    if (value > 6) {
        const value_str = workers.String.init(value);
        defer value_str.free();
        // use value_str.value()
    }
}
```

## TypeScript Runtime (Required)

The TypeScript runtime bridges WASM and JavaScript. Create `src/index.ts`:

```typescript
import wasmModule from '../zig-out/bin/worker.wasm';

// Full runtime code available in README.md
// Key exports: handleFetch, heap management, JSPI integration
```

## wrangler.toml

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

# Bindings (as needed)
[[kv_namespaces]]
binding = "MY_KV"
id = "..."

[[d1_databases]]
binding = "MY_DB"
database_id = "..."

[[r2_buckets]]
binding = "MY_BUCKET"
bucket_name = "..."

[[queues.producers]]
binding = "MY_QUEUE"
queue = "..."

[[services]]
binding = "BACKEND"
service = "backend-worker"

[ai]
binding = "AI"
```

## build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const workers_dep = b.dependency("cf_workerz", .{
        .target = wasm_target,
        .optimize = optimize,
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });

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

## Common Patterns

### CRUD Handler

```zig
const User = struct { id: u32, name: []const u8, email: []const u8 };

fn getUser(ctx: *FetchContext) void {
    const id_str = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing id" }, 400);
        return;
    };
    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        ctx.json(.{ .err = "Invalid id" }, 400);
        return;
    };

    const db = ctx.env.d1("DB") orelse {
        ctx.throw(500, "DB error");
        return;
    };
    defer db.free();

    if (db.one(User, "SELECT * FROM users WHERE id = ?", .{id})) |user| {
        ctx.json(.{ .id = user.id, .name = user.name, .email = user.email }, 200);
    } else {
        ctx.json(.{ .err = "Not found" }, 404);
    }
}

fn createUser(ctx: *FetchContext) void {
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON" }, 400);
        return;
    };
    defer json.deinit();

    const name = json.getString("name") orelse {
        ctx.json(.{ .err = "Name required" }, 400);
        return;
    };
    const email = json.getStringOr("email", "");

    const db = ctx.env.d1("DB") orelse {
        ctx.throw(500, "DB error");
        return;
    };
    defer db.free();

    _ = db.execute("INSERT INTO users (name, email) VALUES (?, ?)", .{ name, email });
    ctx.json(.{ .created = true }, 201);
}
```

### Error Handling

```zig
fn handler(ctx: *FetchContext) void {
    // Early return pattern
    const db = ctx.env.d1("DB") orelse {
        ctx.throw(500, "DB not configured");
        return;
    };
    defer db.free();

    const id = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing id" }, 400);
        return;
    };

    // Use error union with ctx.json(error.X, status)
    ctx.json(error.NotFound, 404); // -> {"error":"NotFound"}
}
```
