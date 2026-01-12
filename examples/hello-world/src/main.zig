// cf-workerz Example - Hello World with D1, JsonBody, and Struct Serialization
//
// This example demonstrates:
// - Built-in Router with path parameters and wildcards
// - Ergonomic D1 API (query, one, execute) with struct mapping
// - JsonBody for parsing JSON request bodies
// - ctx.json() with automatic struct serialization
// - Response helpers (ctx.text, ctx.redirect, ctx.throw)
// - URL and URLSearchParams APIs
// - FormData API for form handling
//
// Endpoints:
//   GET  /                    - Welcome message with API docs
//   GET  /hello/:name         - Personalized greeting (path params)
//   GET  /health              - Health check
//   POST /echo                - Echo JSON body back
//
// D1 Endpoints (requires D1 binding):
//   POST /setup               - Create users table
//   GET  /users               - List all users (ergonomic query)
//   GET  /users/:id           - Get single user (ergonomic one)
//   POST /users               - Create user (JsonBody + execute)
//   DELETE /users/:id         - Delete user (execute)
//
// Test Endpoints (URL/FormData APIs):
//   GET  /test/url            - Test URL parsing and manipulation
//   GET  /test/params         - Test URLSearchParams
//   POST /test/formdata       - Test FormData parsing
//   GET  /test/query          - Test ctx.query() and ctx.url() helpers
//   GET  /test/headers         - Test Headers iterator API
//   POST /test/streams         - Test Streams API (body reading)

const std = @import("std");
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;

// ============================================================================
// Data Types
// ============================================================================

/// User struct for D1 query result mapping
const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
};

/// API response types for ctx.json() struct serialization
const WelcomeResponse = struct {
    message: []const u8,
    version: []const u8,
    features: []const []const u8,
};

const HealthResponse = struct {
    status: []const u8,
    service: []const u8,
};

// ============================================================================
// Route Table
// ============================================================================

const routes: []const Route = &.{
    // Basic routes
    Route.get("/", handleRoot),
    Route.get("/hello/:name", handleHello),
    Route.get("/health", handleHealth),
    Route.post("/echo", handleEcho),

    // D1 Database routes (CRUD)
    Route.post("/setup", handleSetup),
    Route.get("/users", handleListUsers),
    Route.get("/users/:id", handleGetUser),
    Route.post("/users", handleCreateUser),
    Route.delete("/users/:id", handleDeleteUser),

    // Test routes for URL and FormData APIs
    Route.get("/test/url", handleTestUrl),
    Route.get("/test/params", handleTestParams),
    Route.post("/test/formdata", handleTestFormData),
    Route.get("/test/query", handleTestQuery),
    Route.get("/test/headers", handleTestHeaders),
    Route.post("/test/streams", handleTestStreams),
    Route.get("/test/url-iterators", handleTestUrlIterators),
    Route.post("/test/formdata-entries", handleTestFormDataEntries),
    Route.post("/test/reader", handleTestReader),
    Route.get("/test/file", handleTestFile),
};

// ============================================================================
// Basic Handlers
// ============================================================================

fn handleRoot(ctx: *FetchContext) void {
    // Demonstrate ctx.json() with struct serialization
    ctx.json(WelcomeResponse{
        .message = "Welcome to cf-workerz!",
        .version = "0.1.0",
        .features = &.{
            "Ergonomic D1 API with struct mapping",
            "JsonBody for JSON request parsing",
            "Automatic struct serialization",
            "Built-in Router with path params",
            "JSPI async (zero overhead)",
        },
    }, 200);
}

fn handleHello(ctx: *FetchContext) void {
    // Use ctx.param() shorthand for path parameters
    const name = ctx.param("name") orelse "World";

    // ctx.json() with anonymous struct
    ctx.json(.{
        .message = "Hello!",
        .name = name,
    }, 200);
}

fn handleHealth(ctx: *FetchContext) void {
    // Struct serialization
    ctx.json(HealthResponse{
        .status = "healthy",
        .service = "cf-workerz",
    }, 200);
}

fn handleEcho(ctx: *FetchContext) void {
    // Parse JSON body with JsonBody helper
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    // Extract fields with typed getters
    const message = json.getStringOr("message", "(no message)");
    const count = json.getIntOr("count", i32, 0);
    const enabled = json.getBoolOr("enabled", false);

    // Echo back with struct serialization
    ctx.json(.{
        .echoed = true,
        .message = message,
        .count = count,
        .enabled = enabled,
    }, 200);
}

// ============================================================================
// D1 Database Handlers (Ergonomic API)
// ============================================================================

fn handleSetup(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "D1 not configured. Add [[d1_databases]] to wrangler.toml" }, 500);
        return;
    };
    defer db.free();

    // Use db.execute() for DDL statements
    _ = db.execute(
        \\CREATE TABLE IF NOT EXISTS users (
        \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\  name TEXT NOT NULL,
        \\  email TEXT NOT NULL UNIQUE
        \\)
    , .{});

    ctx.json(.{
        .success = true,
        .message = "Users table created",
    }, 200);
}

fn handleListUsers(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "D1 not configured" }, 500);
        return;
    };
    defer db.free();

    // Ergonomic query with struct mapping
    var users = db.query(User, "SELECT id, name, email FROM users LIMIT 100", .{});
    defer users.deinit();

    // Collect users into response
    // Note: In production, you'd use a proper JSON array builder
    var count: u32 = 0;
    while (users.next()) |_| {
        count += 1;
    }

    ctx.json(.{
        .count = count,
        .message = "Use GET /users/:id to fetch individual users",
    }, 200);
}

fn handleGetUser(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "D1 not configured" }, 500);
        return;
    };
    defer db.free();

    // Get ID from path parameter
    const id_str = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing user ID" }, 400);
        return;
    };

    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        ctx.json(.{ .err = "Invalid user ID" }, 400);
        return;
    };

    // Ergonomic one() for single row with inline params
    const user = db.one(User, "SELECT id, name, email FROM users WHERE id = ?", .{id});

    if (user) |u| {
        ctx.json(.{
            .id = u.id,
            .name = u.name,
            .email = u.email,
        }, 200);
    } else {
        ctx.json(.{ .err = "User not found" }, 404);
    }
}

fn handleCreateUser(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "D1 not configured" }, 500);
        return;
    };
    defer db.free();

    // Parse JSON body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    // Extract required fields
    const name = json.getString("name") orelse {
        ctx.json(.{ .err = "Name is required" }, 400);
        return;
    };

    const email = json.getString("email") orelse {
        ctx.json(.{ .err = "Email is required" }, 400);
        return;
    };

    // Ergonomic execute() with inline params
    const affected = db.execute(
        "INSERT INTO users (name, email) VALUES (?, ?)",
        .{ name, email },
    );

    if (affected > 0) {
        ctx.json(.{
            .success = true,
            .message = "User created",
            .name = name,
            .email = email,
        }, 201);
    } else {
        ctx.json(.{ .err = "Failed to create user (email may already exist)" }, 400);
    }
}

fn handleDeleteUser(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "D1 not configured" }, 500);
        return;
    };
    defer db.free();

    const id_str = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing user ID" }, 400);
        return;
    };

    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        ctx.json(.{ .err = "Invalid user ID" }, 400);
        return;
    };

    // Ergonomic execute() for DELETE
    const affected = db.execute("DELETE FROM users WHERE id = ?", .{id});

    if (affected > 0) {
        ctx.json(.{ .success = true, .deleted = id }, 200);
    } else {
        ctx.json(.{ .err = "User not found" }, 404);
    }
}

// ============================================================================
// URL and FormData Test Handlers
// ============================================================================

/// Test URL parsing and manipulation
/// GET /test/url?example=value
fn handleTestUrl(ctx: *FetchContext) void {
    // Parse a complex URL
    const url = workers.URL.new("https://user:pass@example.com:8080/path/to/resource?foo=bar&baz=qux#section");
    defer url.free();

    // Test all property getters
    ctx.json(.{
        .api = "URL",
        .href = url.href(),
        .protocol = url.protocol(),
        .username = url.username(),
        .password = url.password(),
        .host = url.host(),
        .hostname = url.hostname(),
        .port = url.port(),
        .pathname = url.pathname(),
        .search = url.search(),
        .hash = url.hash(),
        .origin = url.origin(),
    }, 200);
}

/// Test URLSearchParams
/// GET /test/params?name=Alice&tags=zig&tags=wasm
fn handleTestParams(ctx: *FetchContext) void {
    // Create URLSearchParams and manipulate it
    const params = workers.URLSearchParams.new();
    defer params.free();

    // Test append
    params.append("name", "Alice");
    params.append("age", "30");
    params.append("tags", "zig");
    params.append("tags", "wasm"); // Multiple values for same key

    // Test has
    const hasName = params.has("name");
    const hasEmail = params.has("email");

    // Test get
    const name = params.get("name") orelse "(null)";
    const missing = params.get("missing") orelse "(null)";

    // Test set (replaces existing)
    params.set("age", "31");
    const newAge = params.get("age") orelse "(null)";

    // Test size
    const size = params.size();

    // Test toString
    const queryString = params.toString();

    // Test delete
    params.delete("tags");
    const afterDelete = params.toString();

    ctx.json(.{
        .api = "URLSearchParams",
        .hasName = hasName,
        .hasEmail = hasEmail,
        .name = name,
        .missing = missing,
        .ageAfterSet = newAge,
        .size = size,
        .queryString = queryString,
        .afterDeleteTags = afterDelete,
    }, 200);
}

/// Test FormData parsing
/// POST /test/formdata with Content-Type: application/x-www-form-urlencoded
/// or multipart/form-data
fn handleTestFormData(ctx: *FetchContext) void {
    // Create FormData and test it
    const form = workers.FormData.new();
    defer form.free();

    // Test append
    form.append("username", "alice");
    form.append("email", "alice@example.com");
    form.append("roles", "admin");
    form.append("roles", "user"); // Multiple values

    // Test has
    const hasUsername = form.has("username");
    const hasPassword = form.has("password");

    // Test get
    var usernameValue: []const u8 = "(null)";
    if (form.get("username")) |entry| {
        switch (entry) {
            .field => |value| {
                usernameValue = value;
            },
            .file => |_| {
                usernameValue = "(file)";
            },
        }
    }

    // Test set (replaces existing)
    form.set("email", "bob@example.com");
    var emailAfterSet: []const u8 = "(null)";
    if (form.get("email")) |entry| {
        switch (entry) {
            .field => |value| {
                emailAfterSet = value;
            },
            .file => |_| {
                emailAfterSet = "(file)";
            },
        }
    }

    // Test delete
    form.delete("roles");
    const hasRolesAfterDelete = form.has("roles");

    ctx.json(.{
        .api = "FormData",
        .hasUsername = hasUsername,
        .hasPassword = hasPassword,
        .username = usernameValue,
        .emailAfterSet = emailAfterSet,
        .hasRolesAfterDelete = hasRolesAfterDelete,
    }, 200);
}

/// Test query parameter access via ctx.query()
/// GET /test/query?name=Alice&age=30&debug=true
fn handleTestQuery(ctx: *FetchContext) void {
    // Get query parameters from the request URL
    const params = ctx.query();
    defer params.free();

    // Test get - retrieve parameter values
    const name = params.get("name") orelse "(none)";
    const age = params.get("age") orelse "(none)";
    const missing = params.get("nonexistent") orelse "(none)";

    // Test has - check if parameter exists
    const hasDebug = params.has("debug");
    const hasVerbose = params.has("verbose");

    // Test size - count of parameters
    const count = params.size();

    // Also test ctx.url() for full URL access
    const fullUrl = ctx.url();
    defer fullUrl.free();
    const pathname = fullUrl.pathname();
    const search = fullUrl.search();
    const host = fullUrl.hostname();

    ctx.json(.{
        .api = "ctx.query() and ctx.url()",
        .params = .{
            .name = name,
            .age = age,
            .missing = missing,
        },
        .has = .{
            .debug = hasDebug,
            .verbose = hasVerbose,
        },
        .count = count,
        .url = .{
            .pathname = pathname,
            .search = search,
            .hostname = host,
        },
    }, 200);
}

/// Test Headers iterator API
/// GET /test/headers
fn handleTestHeaders(ctx: *FetchContext) void {
    // Get request headers
    const headers = ctx.req.headers();
    defer headers.free();

    // Test keys() iterator - iterate over header names
    var keysList = workers.Array.new();
    defer keysList.free();

    var keysIter = headers.keys();
    defer keysIter.free();
    var keyCount: u32 = 0;
    while (keysIter.next()) |key| {
        if (keyCount < 5) { // Limit to first 5 for demo
            const keyStr = workers.String.new(key);
            defer keyStr.free();
            keysList.push(&keyStr);
        }
        keyCount += 1;
    }

    // Test values() iterator - iterate over header values
    var valuesIter = headers.values();
    defer valuesIter.free();
    var valueCount: u32 = 0;
    while (valuesIter.next()) |_| {
        valueCount += 1;
    }

    // Test entries() iterator - iterate over name/value pairs
    var entriesIter = headers.entries();
    defer entriesIter.free();
    var entryCount: u32 = 0;
    var sampleHeader: ?[]const u8 = null;
    var sampleValue: ?[]const u8 = null;
    while (entriesIter.nextEntry()) |entry| {
        if (entryCount == 0) {
            sampleHeader = entry.name;
            sampleValue = entry.value;
        }
        entryCount += 1;
    }

    // Test getText() convenience method
    const contentType = headers.getText("content-type") orelse "(none)";
    const userAgent = headers.getText("user-agent") orelse "(none)";
    const host = headers.getText("host") orelse "(none)";

    // Test has()
    const hasAccept = headers.has("accept");
    const hasCustom = headers.has("x-custom-header");

    ctx.json(.{
        .api = "Headers Iterator API",
        .iterators = .{
            .keyCount = keyCount,
            .valueCount = valueCount,
            .entryCount = entryCount,
        },
        .sample = .{
            .firstHeaderName = sampleHeader orelse "(none)",
            .firstHeaderValue = sampleValue orelse "(none)",
        },
        .getText = .{
            .contentType = contentType,
            .userAgent = userAgent,
            .host = host,
        },
        .has = .{
            .accept = hasAccept,
            .customHeader = hasCustom,
        },
    }, 200);
}

/// Test Streams API
/// POST /test/streams with a body
fn handleTestStreams(ctx: *FetchContext) void {
    // Read request body using existing Request methods
    const bodyText = ctx.req.text() orelse "(empty)";
    defer std.heap.page_allocator.free(bodyText);

    // Test CompressionStream creation with different formats
    const gzipCompression = workers.CompressionStream.new(.gzip);
    defer gzipCompression.free();

    const deflateCompression = workers.CompressionStream.new(.deflate);
    defer deflateCompression.free();

    // Get the transform from compression stream
    const compressTransform = gzipCompression.asTransform();
    // Note: We don't free compressTransform since it shares the same ID as compression

    // Verify we can get readable/writable from compression
    const compressReadable = gzipCompression.readable();
    defer compressReadable.free();
    const compressWritable = gzipCompression.writable();
    defer compressWritable.free();

    // Test DecompressionStream creation
    const gzipDecompression = workers.DecompressionStream.new(.gzip);
    defer gzipDecompression.free();

    const deflateDecompression = workers.DecompressionStream.new(.deflate);
    defer deflateDecompression.free();

    // Test asTransform on decompression
    const decompressTransform = gzipDecompression.asTransform();

    // Test TransformStream creation (just verify it can be created)
    const transform = workers.TransformStream.new();
    defer transform.free();

    ctx.json(.{
        .api = "Streams API",
        .requestBody = .{
            .text = bodyText,
            .length = bodyText.len,
        },
        .transformStream = .{
            .created = transform.id > 0,
        },
        .compressionStream = .{
            .gzipCreated = gzipCompression.id > 0,
            .deflateCreated = deflateCompression.id > 0,
            .hasTransform = compressTransform.id > 0,
            .hasReadable = compressReadable.id > 0,
            .hasWritable = compressWritable.id > 0,
        },
        .decompressionStream = .{
            .gzipCreated = gzipDecompression.id > 0,
            .deflateCreated = deflateDecompression.id > 0,
            .hasTransform = decompressTransform.id > 0,
        },
    }, 200);
}

/// Test URLSearchParams iterators API
/// GET /test/url-iterators?name=Alice&age=30&city=NYC
fn handleTestUrlIterators(ctx: *FetchContext) void {
    // Create params with some values
    const params = workers.URLSearchParams.new();
    defer params.free();

    params.append("name", "Alice");
    params.append("age", "30");
    params.append("city", "NYC");
    params.append("hobbies", "coding");
    params.append("hobbies", "reading");

    // Test keys() iterator
    var keysIter = params.keys();
    defer keysIter.free();
    var keyCount: u32 = 0;
    var firstKey: ?[]const u8 = null;
    while (keysIter.next()) |key| {
        if (keyCount == 0) {
            firstKey = key;
        }
        keyCount += 1;
    }

    // Test values() iterator
    var valuesIter = params.values();
    defer valuesIter.free();
    var valueCount: u32 = 0;
    var firstValue: ?[]const u8 = null;
    while (valuesIter.next()) |value| {
        if (valueCount == 0) {
            firstValue = value;
        }
        valueCount += 1;
    }

    // Test entries() iterator with nextEntry()
    var entriesIter = params.entries();
    defer entriesIter.free();
    var entryCount: u32 = 0;
    var sampleName: ?[]const u8 = null;
    var sampleValue: ?[]const u8 = null;
    while (entriesIter.nextEntry()) |entry| {
        if (entryCount == 0) {
            sampleName = entry.name;
            sampleValue = entry.value;
        }
        entryCount += 1;
    }

    ctx.json(.{
        .api = "URLSearchParams Iterators",
        .keys = .{
            .count = keyCount,
            .first = firstKey orelse "(none)",
        },
        .values = .{
            .count = valueCount,
            .first = firstValue orelse "(none)",
        },
        .entries = .{
            .count = entryCount,
            .sampleName = sampleName orelse "(none)",
            .sampleValue = sampleValue orelse "(none)",
        },
    }, 200);
}

/// Test FormData entries() iterator
/// POST /test/formdata-entries
fn handleTestFormDataEntries(ctx: *FetchContext) void {
    // Create FormData with multiple entries
    const form = workers.FormData.new();
    defer form.free();

    form.append("username", "alice");
    form.append("email", "alice@example.com");
    form.append("role", "admin");

    // Test entries() iterator
    var entriesIter = form.entries();
    defer entriesIter.free();
    var entryCount: u32 = 0;
    var firstFieldName: ?[]const u8 = null;
    var firstFieldValue: ?[]const u8 = null;

    while (entriesIter.nextEntry()) |entry| {
        if (entryCount == 0) {
            firstFieldName = entry.name;
            switch (entry.value) {
                .field => |value| {
                    firstFieldValue = value;
                },
                .file => |_| {
                    firstFieldValue = "(file)";
                },
            }
        }
        entryCount += 1;
    }

    // Test reset and count
    entriesIter.reset();
    const totalCount = entriesIter.count();

    ctx.json(.{
        .api = "FormData entries() iterator",
        .entries = .{
            .count = entryCount,
            .totalCount = totalCount,
            .firstFieldName = firstFieldName orelse "(none)",
            .firstFieldValue = firstFieldValue orelse "(none)",
        },
    }, 200);
}

/// Test ReadableStreamDefaultReader API
/// POST /test/reader with body content
fn handleTestReader(ctx: *FetchContext) void {
    // Get the request body as a stream
    const body = ctx.req.body();
    defer body.free();

    // Check if locked
    const wasLocked = body.locked();

    // Get a reader
    const reader = body.getReader();
    defer reader.free();

    // Now it should be locked
    const isLockedAfterReader = body.locked();

    // Read chunks (we'll read until done)
    var chunkCount: u32 = 0;
    var totalBytes: usize = 0;
    var allDone = false;

    while (!allDone) {
        const result = reader.read();
        if (result.done) {
            allDone = true;
        } else if (result.value) |chunk| {
            chunkCount += 1;
            totalBytes += chunk.len;
        }
    }

    ctx.json(.{
        .api = "ReadableStreamDefaultReader",
        .stream = .{
            .wasLocked = wasLocked,
            .isLockedAfterReader = isLockedAfterReader,
        },
        .reading = .{
            .chunkCount = chunkCount,
            .totalBytes = totalBytes,
            .done = allDone,
        },
    }, 200);
}

/// Test File.new() constructor
/// GET /test/file
fn handleTestFile(ctx: *FetchContext) void {
    // Create a file from text
    const textFile = workers.File.new("Hello, World!", "hello.txt", .{
        .contentType = "text/plain",
    });
    defer textFile.free();

    // Create a file from bytes
    const bytes = [_]u8{ 0x48, 0x65, 0x6c, 0x6c, 0x6f }; // "Hello"
    const binaryFile = workers.File.fromBytes(&bytes, "hello.bin", .{
        .contentType = "application/octet-stream",
        .lastModified = 1704067200000, // 2024-01-01
    });
    defer binaryFile.free();

    // Read properties
    const textFileName = textFile.name();
    const textFileSize = textFile.size();
    const textFileType = textFile.contentType();
    const textContent = textFile.text();

    const binFileName = binaryFile.name();
    const binFileSize = binaryFile.size();
    const binFileType = binaryFile.contentType();
    const binLastMod = binaryFile.lastModified();

    ctx.json(.{
        .api = "File.new() constructor",
        .textFile = .{
            .name = textFileName,
            .size = textFileSize,
            .type = textFileType,
            .content = textContent,
        },
        .binaryFile = .{
            .name = binFileName,
            .size = binFileSize,
            .type = binFileType,
            .lastModified = binLastMod,
        },
    }, 200);
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
