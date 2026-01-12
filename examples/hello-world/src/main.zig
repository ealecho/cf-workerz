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

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
