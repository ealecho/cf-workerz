# cf-workerz LLM Reference

> This document is optimized for LLMs/AI agents. It provides concise, copy-paste ready code patterns for building Cloudflare Workers in Zig.

## Quick Facts

- **Language**: Zig (0.14+)
- **Target**: WebAssembly (wasm32-freestanding)
- **Runtime**: Cloudflare Workers with JSPI
- **Binary Size**: ~10-15KB WASM

## Live Demo

- **WebSocket Chat Client**: https://websocket-chat-client.pages.dev
- **WebSocket Chat API**: https://websocket-chat.alaara.workers.dev

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

## Request Helpers

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
                _ = filename;
                _ = content;
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
            // process chunk
            _ = chunk;
        }
    }
}
```

## Middleware

```zig
const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const Route = workers.Router;
const Middleware = workers.Middleware;
const MiddlewareFn = workers.MiddlewareFn;

// Define middleware functions

/// CORS middleware - handles preflight requests and adds CORS headers.
/// Note: ctx.json() does NOT add CORS headers automatically.
fn corsMiddleware(ctx: *FetchContext) bool {
    // Handle preflight OPTIONS requests
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

fn authMiddleware(ctx: *FetchContext) bool {
    const token = ctx.header("Authorization") orelse {
        ctx.json(.{ .err = "Unauthorized" }, 401);
        return false; // Stop the chain
    };
    // Validate token...
    _ = token;
    return true;
}

fn logMiddleware(ctx: *FetchContext) bool {
    // Log request details
    _ = ctx;
    return true;
}

// Create middleware chain
const middleware = Middleware{
    .before = &.{ corsMiddleware, authMiddleware, logMiddleware },
    .after = &.{}, // Optional after-handlers
};

// Dispatch with middleware
export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatchWithMiddleware(routes, ctx, middleware);
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

## Headers

### Reading Headers

```zig
fn handleRequest(ctx: *FetchContext) void {
    const headers = ctx.req.headers();
    defer headers.free();
    
    // Get header value (returns ?[]const u8)
    const contentType = headers.getText("content-type") orelse "text/plain";
    const auth = headers.getText("authorization");
    
    // Check if header exists
    if (headers.has("x-custom-header")) {
        // header present
    }
    
    ctx.json(.{ .contentType = contentType }, 200);
}
```

### Iterating Headers

```zig
fn listHeaders(ctx: *FetchContext) void {
    const headers = ctx.req.headers();
    defer headers.free();
    
    // Iterate over header names
    var keysIter = headers.keys();
    defer keysIter.free();
    while (keysIter.next()) |name| {
        // name is []const u8: "content-type", "accept", etc.
        _ = name;
    }
    
    // Iterate over header values
    var valuesIter = headers.values();
    defer valuesIter.free();
    while (valuesIter.next()) |value| {
        // value is []const u8
        _ = value;
    }
    
    // Iterate over name/value pairs
    var entriesIter = headers.entries();
    defer entriesIter.free();
    while (entriesIter.nextEntry()) |entry| {
        // entry.name, entry.value are []const u8
        _ = entry.name;
        _ = entry.value;
    }
    
    // Get iterator count
    const count = keysIter.count();
    _ = count;
    
    // Reset iterator to beginning
    keysIter.reset();
}
```

### Creating Headers

```zig
fn createHeaders() void {
    const headers = workers.Headers.new();
    defer headers.free();
    
    // Set headers
    headers.setText("Content-Type", "application/json");
    headers.setText("X-Custom", "value");
    
    // Append (allows multiple values for same key)
    headers.append("Set-Cookie", "a=1");
    headers.append("Set-Cookie", "b=2");
    
    // Delete
    headers.delete("X-Custom");
}
```

## Streams

### ReadableStream

```zig
fn handleStreams(ctx: *FetchContext) void {
    // Get body as stream
    const body = ctx.req.body();
    defer body.free();
    
    // Read as text
    const text = body.text();
    _ = text;
    
    // Read as bytes
    const bytes = body.bytes();
    _ = bytes;
    
    // Get a reader
    const reader = body.getReader();
    defer reader.free();
    // reader.read(), reader.cancel(), etc.
}
```

### ReadableStreamDefaultReader

```zig
fn readWithReader(ctx: *FetchContext) void {
    const body = ctx.req.body();
    defer body.free();
    
    // Get a reader (locks the stream)
    const reader = body.getReader();
    defer reader.free();
    
    // Read chunks until done
    var totalBytes: usize = 0;
    while (true) {
        const result = reader.read();
        if (result.done) break;
        if (result.value) |chunk| {
            totalBytes += chunk.len;
            // process chunk bytes
        }
    }
    
    // Cancel reading early
    // reader.cancel();
    
    // Release lock without freeing
    // reader.releaseLock();
}
```

### Stream Piping

```zig
fn pipeStreams() void {
    const readable = getReadableStream();
    defer readable.free();
    
    const writable = getWritableStream();
    defer writable.free();
    
    // Pipe to writable stream
    readable.pipeTo(&writable, .{
        .preventClose = false,
        .preventAbort = false,
        .preventCancel = false,
    });
}
```

### Compression/Decompression

```zig
fn compressResponse(ctx: *FetchContext) void {
    const body = ctx.req.body();
    defer body.free();
    
    // Compress with gzip
    const compression = workers.CompressionStream.new(.gzip);
    defer compression.free();
    
    const compressed = body.pipeThrough(&compression.asTransform(), .{});
    defer compressed.free();
    
    // Read compressed data
    const data = compressed.bytes();
    _ = data;
}

fn decompressRequest() void {
    const compressed = getCompressedStream();
    defer compressed.free();
    
    // Decompress
    const decompression = workers.DecompressionStream.new(.gzip);
    defer decompression.free();
    
    const decompressed = compressed.pipeThrough(&decompression.asTransform(), .{});
    defer decompressed.free();
    
    const text = decompressed.text();
    _ = text;
}
```

### Stream Teeing

```zig
fn teeStream() void {
    const stream = getReadableStream();
    defer stream.free();
    
    // Split into two independent streams
    const branches = stream.tee();
    defer branches[0].free();
    defer branches[1].free();
    
    // Read from both independently
    const text1 = branches[0].text();
    const text2 = branches[1].text();
    _ = text1;
    _ = text2;
}
```

### WritableStream Writer

```zig
fn writeToStream() void {
    const writable = getWritableStream();
    defer writable.free();
    
    // Get exclusive writer
    const writer = writable.getWriter();
    defer writer.free();
    
    // Write text
    writer.write("Hello, ");
    writer.write("World!");
    
    // Write bytes
    writer.writeBytes(&[_]u8{ 0x48, 0x69 });
    
    // Close when done
    writer.close();
    
    // Or abort on error
    // writer.abort();
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

## WebSockets

WebSockets enable real-time, bidirectional communication between clients and your Worker.

### Basic WebSocket Handler

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

### WebSocket Methods

```zig
fn websocketOperations(ws: *workers.WebSocket) void {
    // Check connection state
    if (ws.readyState() == .Open) {
        // Send text message
        ws.sendText("Hello, client!");

        // Send binary data
        const data = [_]u8{ 0x00, 0x01, 0x02 };
        ws.sendBytes(&data);

        // Close with code and reason
        ws.close(.NormalClosure, "Goodbye!");
    }
}
```

### WebSocket Close Codes

| Code | Name | Description |
|------|------|-------------|
| 1000 | NormalClosure | Normal close |
| 1001 | GoingAway | Server shutting down |
| 1002 | ProtocolError | Protocol error |
| 1003 | UnsupportedData | Invalid data type |
| 1008 | PolicyViolation | Policy violation |
| 1011 | InternalError | Server error |

### Outbound WebSocket Connections

Connect to external WebSocket servers from your Worker:

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

### WebSocket Event Types

Handle different types of WebSocket events:

```zig
const workers = @import("cf-workerz");

// Incoming message can be text or binary
fn handleIncomingMessage(msg: workers.WebSocketIncomingMessage) void {
    switch (msg) {
        .text => |text| {
            // Handle text message
            _ = text;
        },
        .binary => |bytes| {
            // Handle binary data
            _ = bytes;
        },
    }
}

// Message event with metadata
fn handleMessageEvent(event: workers.MessageEvent) void {
    defer event.free();

    // Get as text
    if (event.text()) |text| {
        _ = text;
    }

    // Get as bytes
    const bytes = event.bytes();
    _ = bytes;

    // Get origin
    const origin = event.origin();
    _ = origin;
}

// Close event
fn handleCloseEvent(event: workers.CloseEvent) void {
    defer event.free();

    const code = event.code();      // e.g., 1000
    const reason = event.reason();  // e.g., "Normal closure"
    const clean = event.wasClean(); // true if clean close
    _ = code;
    _ = reason;
    _ = clean;
}

// Error event
fn handleErrorEvent(event: workers.ErrorEvent) void {
    defer event.free();

    const msg = event.message();
    const errType = event.errorType();
    _ = msg;
    _ = errType;
}

// Combined WebSocket event union
fn handleWebSocketEvent(event: workers.WebSocketEvent) void {
    switch (event) {
        .message => |msg| handleMessageEvent(msg),
        .close => |close| handleCloseEvent(close),
        .error => |err| handleErrorEvent(err),
    }
}
```

### Configuration

No special wrangler.toml configuration needed for basic WebSockets.

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

### Creating Durable Object IDs

```zig
fn createDOIds(namespace: *workers.DurableObjectNamespace) void {
    // By name (deterministic - same name always = same DO)
    const byName = namespace.idFromName("user:123");
    defer byName.free();

    // From stored string (restore from database/KV)
    const fromString = namespace.idFromString("abc123hex...");
    defer fromString.free();

    // New unique ID (random, globally unique)
    const unique = namespace.newUniqueId(.{});
    defer unique.free();

    // New unique ID with jurisdiction (data locality)
    const euId = namespace.newUniqueId(.{ .jurisdiction = "eu" });
    defer euId.free();

    // Get string representation for storage
    const idString = byName.toString();
    // Store idString in KV/D1 for later use
    _ = idString;
}
```

### Location Hints

Optimize latency by hinting where the Durable Object should run:

```zig
fn useDOWithLocationHint(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("MY_DO") orelse return;
    defer namespace.free();

    // Get stub with location hint for lower latency
    // Hint suggests where the DO should be created (not guaranteed)
    const stub = namespace.getWithLocationHint("user:123", "enam"); // Eastern North America
    defer stub.free();

    // Or get stub for an existing ID with location hint
    const id = namespace.idFromName("room:lobby");
    defer id.free();

    const stubById = namespace.getStubForId(&id, "weur"); // Western Europe
    defer stubById.free();

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

### Sending Requests to a Durable Object

```zig
fn callDO(stub: *workers.DurableObjectStub) void {
    // Simple GET
    const getRes = stub.fetch(.{ .text = "https://do/status" }, null);
    defer getRes.free();

    // POST with JSON body
    const body = workers.String.new("{\"action\":\"increment\"}");
    defer body.free();

    const headers = workers.Headers.new();
    defer headers.free();
    headers.setText("Content-Type", "application/json");

    const postRes = stub.fetch(.{ .text = "https://do/counter" }, .{
        .requestInit = .{
            .method = .Post,
            .body = .{ .string = &body },
            .headers = headers,
        },
    });
    defer postRes.free();

    // Convenience method
    const simpleGet = stub.get("https://do/data");
    defer simpleGet.free();
}
```

### Durable Object Storage

Inside a Durable Object, use storage for persistent data:

```zig
fn handleInDO(state: *workers.DurableObjectState) void {
    const storage = state.storage();
    defer storage.free();

    // Get values
    if (storage.getText("counter")) |value| {
        _ = value;
    }

    // Get as typed struct
    const Config = struct { theme: []const u8, count: u32 };
    if (storage.getJSON(Config, "config")) |config| {
        _ = config.theme;
    }

    // Put values
    storage.putText("counter", "42");
    storage.putNum("visits", u64, 100);

    // Delete
    _ = storage.delete("old-key");
    storage.deleteAll(); // Clear everything

    // List with options
    var entries = storage.list(.{
        .prefix = "user:",
        .limit = 100,
        .reverse = false,
    });
    defer entries.free();
}
```

### Durable Object Alarms

Schedule code to run at a specific time:

```zig
fn setupAlarm(state: *workers.DurableObjectState) void {
    // Set alarm for 1 hour from now (Unix ms)
    const oneHour: u64 = 60 * 60 * 1000;
    const now = @as(u64, @intFromFloat(std.time.timestamp() * 1000));
    state.setAlarm(now + oneHour);

    // Check current alarm
    if (state.getAlarm()) |scheduledTime| {
        _ = scheduledTime;
    }

    // Cancel alarm
    state.deleteAlarm();
}
```

### ScheduledTime Helper

Use the `ScheduledTime` helper for more convenient alarm scheduling:

```zig
fn setupAlarmWithHelper(storage: *workers.DurableObjectStorage) void {
    // Using absolute timestamp
    const time1 = workers.ScheduledTime.fromTimestamp(1704067200000);
    storage.setAlarmWithOptions(time1.toTimestamp(), .{});

    // Using offsets from now (more convenient)
    const time2 = workers.ScheduledTime.fromOffsetSecs(30);   // 30 seconds from now
    const time3 = workers.ScheduledTime.fromOffsetMins(5);    // 5 minutes from now
    const time4 = workers.ScheduledTime.fromOffsetHours(1);   // 1 hour from now
    const time5 = workers.ScheduledTime.fromOffsetMs(500);    // 500ms from now

    // Set with options
    storage.setAlarmWithOptions(time2.toTimestamp(), .{
        .allowConcurrency = true,   // Allow alarm during request
        .allowUnconfirmed = false,  // Wait for confirmation
    });

    // Get alarm with options
    if (storage.getAlarmWithOptions(.{ .allowConcurrency = true })) |alarm| {
        _ = alarm;
    }

    // Delete with options
    storage.deleteAlarmWithOptions(.{ .allowConcurrency = true });
    _ = time3;
    _ = time4;
    _ = time5;
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

fn attachData(ws: *workers.WebSocket) void {
    // Attach data that survives hibernation
    const data = workers.Object.new();
    defer data.free();
    data.setText("userId", "user123");
    ws.serializeAttachment(&data);

    // Retrieve after hibernation
    if (ws.deserializeAttachment()) |attachment| {
        defer attachment.free();
        _ = attachment.get("userId");
    }
}
```

### SQL Storage (SQLite)

Durable Objects support SQLite-backed storage for relational data:

```zig
fn useSqlStorage(state: *workers.DurableObjectState) void {
    const storage = state.storage();
    defer storage.free();

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

    // Get column names
    const columns = cursor.columnNames();
    _ = columns;

    // Iterate rows
    while (cursor.next()) |row| {
        // row is a JSON object with column values
        defer row.free();
        if (row.get("name")) |name| {
            _ = name;
        }
    }

    // Get single row
    if (cursor.one()) |row| {
        defer row.free();
        // use row
    }

    // Get all rows as array
    const allRows = cursor.toArray();
    defer allRows.free();

    // Get statistics
    const dbSize = sql.databaseSize();
    const rowsRead = cursor.rowsRead();
    const rowsWritten = cursor.rowsWritten();
    _ = dbSize;
    _ = rowsRead;
    _ = rowsWritten;
}
```

### Configuration

```toml
# wrangler.toml
[[durable_objects.bindings]]
name = "MY_DO"
class_name = "MyDurableObject"

[[migrations]]
tag = "v1"
new_classes = ["MyDurableObject"]
```

## Rate Limiting

The Rate Limiting API lets you enforce rate limits directly from your Worker. Limits are applied per Cloudflare location for low latency.

```zig
fn handleRequest(ctx: *FetchContext) void {
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

| Key Type | Example | Use Case |
|----------|---------|----------|
| User ID | `"user:123"` | Per-user limiting |
| API Key | `"apikey:abc123"` | Per-client limiting |
| User + Route | `"user:123:/api/expensive"` | Per-endpoint limiting |

Avoid using IP addresses as keys since many users may share an IP.

### Configuration

```toml
# wrangler.toml
[[ratelimits]]
name = "MY_RATE_LIMITER"
namespace_id = "1001"
simple = { limit = 100, period = 60 }
```

**Period Options:** 10 or 60 seconds only.

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

## SubtleCrypto

Full Web Crypto API for hashing, encryption, signing, and key management.

### Convenience Hash Functions

```zig
const workers = @import("cf-workerz");

fn hashExamples() void {
    const data = "Hello, World!";
    
    // One-liner hash functions (return hex strings)
    const sha256Hash = workers.sha256(data);   // 64 char hex
    const sha1Hash = workers.sha1(data);       // 40 char hex
    const sha512Hash = workers.sha512(data);   // 128 char hex
    const md5Hash = workers.md5(data);         // 32 char hex
    
    _ = sha256Hash;
    _ = sha1Hash;
    _ = sha512Hash;
    _ = md5Hash;
}
```

### SubtleCrypto API

```zig
fn cryptoExamples(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();
    
    // Digest (hash)
    const hash = subtle.digest(.@"SHA-256", "data to hash");
    defer hash.free();
    const hashBytes = hash.bytes();
    _ = hashBytes;
    
    // Generate AES key
    const aesKey = subtle.generateKey(.{
        .AesKeyGenParams = .{ .name = .@"AES-GCM", .length = 256 },
    }, true, &.{ .encrypt, .decrypt });
    defer aesKey.free();
    
    // Generate HMAC key
    const hmacKey = subtle.generateKey(.{
        .HmacKeyGenParams = .{ .name = .HMAC, .hash = .@"SHA-256" },
    }, true, &.{ .sign, .verify });
    defer hmacKey.free();
    
    // Sign with HMAC
    const signature = subtle.sign(.{ .HMAC = {} }, &hmacKey, "message");
    defer signature.free();
    
    // Verify signature
    const isValid = subtle.verify(.{ .HMAC = {} }, &hmacKey, &signature, "message");
    _ = isValid;
    
    // Encrypt with AES-GCM
    const iv = [_]u8{0} ** 12; // 12 bytes for GCM
    const encrypted = subtle.encrypt(.{
        .AesGcmParams = .{ .name = .@"AES-GCM", .iv = &iv },
    }, &aesKey, "plaintext");
    defer encrypted.free();
    
    // Decrypt
    const decrypted = subtle.decrypt(.{
        .AesGcmParams = .{ .name = .@"AES-GCM", .iv = &iv },
    }, &aesKey, encrypted.bytes());
    defer decrypted.free();
    
    // Export key to raw bytes
    const exported = subtle.exportKey(.raw, &aesKey);
    defer exported.free();
    
    // Import key from raw bytes
    const imported = subtle.importKey(
        .raw,
        exported.bytes(),
        .{ .AesKeyAlgorithm = .{ .name = .@"AES-GCM" } },
        true,
        &.{ .encrypt, .decrypt },
    );
    defer imported.free();
    
    ctx.json(.{ .success = true }, 200);
}
```

### Supported Algorithms

| Category | Algorithms |
|----------|------------|
| **Hash** | SHA-1, SHA-256, SHA-384, SHA-512, MD5 |
| **HMAC** | HMAC with any hash algorithm |
| **AES** | AES-GCM, AES-CBC, AES-CTR, AES-KW |
| **RSA** | RSA-OAEP, RSASSA-PKCS1-v1_5, RSA-PSS |
| **EC** | ECDSA, ECDH (P-256, P-384, P-521) |
| **KDF** | PBKDF2, HKDF |

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

### Authentication Handler

```zig
const std = @import("std");
const workers = @import("cf-workerz");
const auth = workers.auth;
const FetchContext = workers.FetchContext;
const Date = workers.Date;

const allocator = std.heap.page_allocator;
const JWT_SECRET = "your-256-bit-secret";
const JWT_ISSUER = "my-app";
const JWT_AUDIENCE = "api.myapp.com";

fn handleLogin(ctx: *FetchContext) void {
    // Rate limit check
    const ip = ctx.header("CF-Connecting-IP") orelse "unknown";
    if (ctx.env.rateLimiter("LOGIN_LIMITER")) |limiter| {
        defer limiter.free();
        if (!limiter.limit(ip).success) {
            ctx.json(.{ .@"error" = "Too many attempts" }, 429);
            return;
        }
    }

    // Parse credentials
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .@"error" = "Invalid JSON" }, 400);
        return;
    };
    defer json.deinit();

    const email = json.getString("email") orelse {
        ctx.json(.{ .@"error" = "Email required" }, 400);
        return;
    };
    const password = json.getString("password") orelse {
        ctx.json(.{ .@"error" = "Password required" }, 400);
        return;
    };

    // Get user from database
    const db = ctx.env.d1("DB") orelse return;
    defer db.free();

    const User = struct { id: []const u8, password_hash: []const u8 };
    const user = db.one(User, "SELECT id, password_hash FROM users WHERE email = ?", .{email}) orelse {
        ctx.json(.{ .@"error" = "Invalid credentials" }, 401);
        return;
    };

    // Verify password
    const valid = auth.verifyPassword(allocator, password, user.password_hash) catch {
        ctx.json(.{ .@"error" = "Invalid credentials" }, 401);
        return;
    };
    if (!valid) {
        ctx.json(.{ .@"error" = "Invalid credentials" }, 401);
        return;
    }

    // Generate JWT
    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));
    const token = auth.jwt.create(allocator, .{
        .sub = user.id,
        .iss = JWT_ISSUER,
        .aud = JWT_AUDIENCE,
        .exp = now + 3600,
        .iat = now,
    }, JWT_SECRET, .{}) catch {
        ctx.json(.{ .@"error" = "Token generation failed" }, 500);
        return;
    };
    defer token.deinit();

    ctx.json(.{ .token = token.toString(), .expiresIn = 3600 }, 200);
}

fn handleProtected(ctx: *FetchContext) void {
    const auth_header = ctx.header("Authorization") orelse {
        ctx.json(.{ .@"error" = "Unauthorized" }, 401);
        return;
    };

    // Extract Bearer token
    const token = if (std.mem.startsWith(u8, auth_header, "Bearer "))
        auth_header[7..]
    else {
        ctx.json(.{ .@"error" = "Invalid format" }, 401);
        return;
    };

    // Verify JWT
    const claims = auth.jwt.verify(allocator, token, JWT_SECRET, .{
        .issuer = JWT_ISSUER,
        .audience = JWT_AUDIENCE,
    }) catch {
        ctx.json(.{ .@"error" = "Invalid token" }, 401);
        return;
    };
    defer claims.deinit();

    const user_id = claims.sub orelse {
        ctx.json(.{ .@"error" = "Invalid token" }, 401);
        return;
    };

    ctx.json(.{ .userId = user_id, .message = "Authenticated!" }, 200);
}

fn handleRegister(ctx: *FetchContext) void {
    var json = ctx.bodyJson() orelse return;
    defer json.deinit();

    const email = json.getString("email") orelse return;
    const password = json.getString("password") orelse return;

    // Hash password (OWASP-compliant)
    const hashed = auth.hashPassword(allocator, password, .{
        .weakPasswordList = &.{ "password", "12345678", "password123" },
    }) catch |err| {
        switch (err) {
            auth.PasswordError.WeakPassword => {
                ctx.json(.{ .@"error" = "Password too common" }, 400);
            },
            auth.PasswordError.PasswordTooShort => {
                ctx.json(.{ .@"error" = "Password too short" }, 400);
            },
            else => {
                ctx.json(.{ .@"error" = "Registration failed" }, 500);
            },
        }
        return;
    };
    defer hashed.deinit();

    // Store in database
    const db = ctx.env.d1("DB") orelse return;
    defer db.free();

    const user_id = workers.apis.randomUUID();
    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));
    _ = db.execute(
        "INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)",
        .{ user_id, email, hashed.toString(), now },
    );

    ctx.json(.{ .success = true, .userId = user_id }, 201);
}
```

### Password Hashing

```zig
const auth = @import("cf-workerz").auth;

// Hash a password (PBKDF2-HMAC-SHA256, 600K iterations)
const hash = try auth.hashPassword(allocator, "password", .{
    .iterations = 600_000,  // OWASP 2024 minimum
    .weakPasswordList = &.{ "password", "123456" },
});
defer hash.deinit();

// Store hash.toString() in database
// Format: "base64salt$iterations$base64hash"

// Verify a password
const valid = try auth.verifyPassword(allocator, "password", stored_hash);
```

### JWT Creation and Verification

```zig
const jwt = @import("cf-workerz").auth.jwt;

// Create token
const token = try jwt.create(allocator, .{
    .sub = "user123",
    .iss = "my-app",
    .aud = "api.myapp.com",
    .exp = now + 3600,  // 1 hour
    .iat = now,
}, secret, .{});
defer token.deinit();

// Verify token
const claims = try jwt.verify(allocator, token_str, secret, .{
    .issuer = "my-app",
    .audience = "api.myapp.com",
    .clockSkewSeconds = 60,
});
defer claims.deinit();

// Access claims
const user_id = claims.sub orelse "unknown";
```

### Auth Event Logging

```zig
const auth = @import("cf-workerz").auth;

// Log authentication events
auth.log.event(.login_success, "user@example.com", .{
    .ip = ctx.header("CF-Connecting-IP") orelse "unknown",
    .path = "/api/login",
});

// Available event types:
// .login_success, .login_failed, .auth_success, .auth_failed,
// .rate_limited, .password_changed, .logout, .account_created, .account_locked
```

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
