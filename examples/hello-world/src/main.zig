// cf-workerz Example - Hello World with D1, JsonBody, and Struct Serialization
//
// This example demonstrates:
// - Built-in Router with path parameters and wildcards
// - Ergonomic D1 API (query, one, execute) with struct mapping
// - JsonBody for parsing JSON request bodies
// - ctx.json() with automatic struct serialization
// - Response helpers (ctx.text, ctx.redirect, ctx.throw)
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
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
