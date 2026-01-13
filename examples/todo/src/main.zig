//! Todo API Example
//!
//! A complete CRUD API demonstrating the unified D1 run() API.
//! Shows all D1Result variants: .rows, .command, .empty, .err
//!
//! ## Endpoints
//!
//! - GET    /health           - Health check
//! - POST   /setup            - Initialize database schema
//! - GET    /todos            - List all todos (with optional filters)
//! - GET    /todos/:id        - Get a single todo
//! - POST   /todos            - Create a new todo
//! - PUT    /todos/:id        - Update a todo
//! - PATCH  /todos/:id/toggle - Toggle todo completion
//! - DELETE /todos/:id        - Delete a todo
//! - DELETE /todos/completed  - Delete all completed todos
//! - GET    /stats            - Get todo statistics

const std = @import("std");
const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const Route = workers.Router;
const Date = workers.Date;

// ============================================================================
// Data Types
// ============================================================================

/// Todo struct for D1 result mapping
const Todo = struct {
    id: u32,
    title: []const u8,
    description: ?[]const u8,
    completed: u32, // SQLite stores booleans as integers
    priority: []const u8,
    created_at: u64,
    updated_at: u64,
};

/// Stats struct for aggregate queries
const Stats = struct {
    total: u32,
    completed: u32,
    pending: u32,
};

// ============================================================================
// Routes
// ============================================================================

const routes: []const Route = &.{
    // Health check
    Route.get("/health", handleHealth),

    // Database setup
    Route.post("/setup", handleSetup),

    // Todo CRUD
    Route.get("/todos", handleListTodos),
    Route.get("/todos/:id", handleGetTodo),
    Route.post("/todos", handleCreateTodo),
    Route.put("/todos/:id", handleUpdateTodo),
    Route.delete("/todos/:id", handleDeleteTodo),

    // Additional operations
    Route.patch("/todos/:id/toggle", handleToggleTodo),
    Route.delete("/todos/completed", handleDeleteCompleted),
    Route.get("/stats", handleStats),
};

// ============================================================================
// Handlers
// ============================================================================

/// Health check endpoint
fn handleHealth(ctx: *FetchContext) void {
    ctx.json(.{
        .status = "ok",
        .service = "todo-api",
        .version = "1.0.0",
    }, 200);
}

/// Initialize the database schema
/// POST /setup
fn handleSetup(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    // Use run() for DDL -> returns .empty on success
    var result = db.run(void,
        \\CREATE TABLE IF NOT EXISTS todos (
        \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
        \\    title TEXT NOT NULL,
        \\    description TEXT,
        \\    completed INTEGER NOT NULL DEFAULT 0,
        \\    priority TEXT NOT NULL DEFAULT 'medium',
        \\    created_at INTEGER NOT NULL,
        \\    updated_at INTEGER NOT NULL
        \\)
    , .{});
    defer result.deinit();

    switch (result) {
        .empty => |meta| {
            ctx.json(.{
                .success = true,
                .message = "Database schema initialized",
                .duration_ms = meta.duration,
            }, 200);
        },
        .command => {
            // Some D1 versions return .command for DDL
            ctx.json(.{
                .success = true,
                .message = "Database schema initialized",
            }, 200);
        },
        else => {
            ctx.json(.{ .err = "Failed to initialize database" }, 500);
        },
    }
}

/// List all todos with optional filtering
/// GET /todos
/// GET /todos?completed=true
/// GET /todos?priority=high
fn handleListTodos(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    // Get query parameters for filtering
    const params = ctx.query();
    defer params.free();

    // Build query based on filters
    var sql: []const u8 = "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos";
    var filter_completed: ?u32 = null;
    var filter_priority: ?[]const u8 = null;

    if (params.get("completed")) |completed| {
        if (std.mem.eql(u8, completed, "true")) {
            filter_completed = 1;
            sql = "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos WHERE completed = ?";
        } else if (std.mem.eql(u8, completed, "false")) {
            filter_completed = 0;
            sql = "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos WHERE completed = ?";
        }
    }

    if (params.get("priority")) |priority| {
        filter_priority = priority;
        if (filter_completed != null) {
            sql = "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos WHERE completed = ? AND priority = ?";
        } else {
            sql = "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos WHERE priority = ?";
        }
    }

    // Execute query with appropriate parameters
    if (filter_completed) |completed| {
        if (filter_priority) |priority| {
            var result = db.run(Todo, sql, .{ completed, priority });
            defer result.deinit();
            sendTodoList(ctx, &result);
        } else {
            var result = db.run(Todo, sql, .{completed});
            defer result.deinit();
            sendTodoList(ctx, &result);
        }
    } else if (filter_priority) |priority| {
        var result = db.run(Todo, sql, .{priority});
        defer result.deinit();
        sendTodoList(ctx, &result);
    } else {
        // No filters - use comptime-known SQL string with ordering
        var result = db.run(Todo, "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos ORDER BY created_at DESC LIMIT 100", .{});
        defer result.deinit();
        sendTodoList(ctx, &result);
    }
}

/// Helper to send todo list response - production-style JSON array serialization
fn sendTodoList(ctx: *FetchContext, result: anytype) void {
    switch (result.*) {
        .rows => |*rows| {
            const count = rows.count();

            // Build JSON array of todos
            const todosArray = workers.Array.new();
            defer todosArray.free();

            while (rows.next()) |todo| {
                // Create a JSON object for each todo
                const todoObj = workers.Object.new();
                defer todoObj.free();

                todoObj.setNum("id", u32, todo.id);
                todoObj.setText("title", todo.title);
                if (todo.description) |desc| {
                    todoObj.setText("description", desc);
                }
                todoObj.setBool("completed", todo.completed == 1);
                todoObj.setText("priority", todo.priority);
                todoObj.setNum("createdAt", u64, todo.created_at);
                todoObj.setNum("updatedAt", u64, todo.updated_at);

                // Push the object to the array
                todosArray.push(&todoObj);
            }

            // Build response object
            const response = workers.Object.new();
            defer response.free();
            response.setArray("todos", &todosArray);
            response.setNum("count", u32, count);

            // Stringify and send
            const jsonStr = response.stringify();
            defer jsonStr.free();
            ctx.json(jsonStr.value(), 200);
        },
        .empty => {
            ctx.json(.{
                .todos = &[_]Todo{},
                .count = 0,
            }, 200);
        },
        else => {
            ctx.json(.{ .err = "Failed to fetch todos" }, 500);
        },
    }
}

/// Get a single todo by ID
/// GET /todos/:id
fn handleGetTodo(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    const id_str = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing todo ID" }, 400);
        return;
    };

    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        ctx.json(.{ .err = "Invalid todo ID" }, 400);
        return;
    };

    // Use run() for SELECT single row
    var result = db.run(Todo, "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos WHERE id = ?", .{id});
    defer result.deinit();

    const todo = switch (result) {
        .rows => |*rows| rows.next(),
        else => null,
    };

    if (todo) |t| {
        ctx.json(.{
            .id = t.id,
            .title = t.title,
            .description = t.description,
            .completed = t.completed == 1,
            .priority = t.priority,
            .createdAt = t.created_at,
            .updatedAt = t.updated_at,
        }, 200);
    } else {
        ctx.json(.{ .err = "Todo not found" }, 404);
    }
}

/// Create a new todo
/// POST /todos
/// Body: { "title": "...", "description": "...", "priority": "high|medium|low" }
fn handleCreateTodo(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    // Parse JSON body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    // Extract fields
    const title = json.getString("title") orelse {
        ctx.json(.{ .err = "Title is required" }, 400);
        return;
    };

    const description = json.getString("description");
    const priority = json.getStringOr("priority", "medium");

    // Validate priority
    if (!std.mem.eql(u8, priority, "high") and
        !std.mem.eql(u8, priority, "medium") and
        !std.mem.eql(u8, priority, "low"))
    {
        ctx.json(.{ .err = "Priority must be 'high', 'medium', or 'low'" }, 400);
        return;
    }

    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));

    // Use run() for INSERT -> returns .command with last_row_id
    var result = db.run(void, "INSERT INTO todos (title, description, priority, completed, created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?)", .{ title, description, priority, now, now });
    defer result.deinit();

    switch (result) {
        .command => |cmd| {
            ctx.json(.{
                .success = true,
                .id = cmd.last_row_id,
                .title = title,
                .description = description,
                .priority = priority,
                .completed = false,
                .createdAt = now,
            }, 201);
        },
        else => {
            ctx.json(.{ .err = "Failed to create todo" }, 500);
        },
    }
}

/// Update a todo
/// PUT /todos/:id
/// Body: { "title": "...", "description": "...", "priority": "...", "completed": true }
fn handleUpdateTodo(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    const id_str = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing todo ID" }, 400);
        return;
    };

    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        ctx.json(.{ .err = "Invalid todo ID" }, 400);
        return;
    };

    // Parse JSON body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    // Check if todo exists first
    {
        var check = db.run(Todo, "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos WHERE id = ?", .{id});
        defer check.deinit();
        const exists = switch (check) {
            .rows => |*rows| rows.next() != null,
            else => false,
        };
        if (!exists) {
            ctx.json(.{ .err = "Todo not found" }, 404);
            return;
        }
    }

    // Extract fields
    const title = json.getString("title") orelse {
        ctx.json(.{ .err = "Title is required" }, 400);
        return;
    };

    const description = json.getString("description");
    const priority = json.getStringOr("priority", "medium");
    const completed: u32 = if (json.getBool("completed") orelse false) 1 else 0;

    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));

    // Use run() for UPDATE -> returns .command with changes count
    var result = db.run(void, "UPDATE todos SET title = ?, description = ?, priority = ?, completed = ?, updated_at = ? WHERE id = ?", .{ title, description, priority, completed, now, id });
    defer result.deinit();

    switch (result) {
        .command => |cmd| {
            if (cmd.changes > 0) {
                ctx.json(.{
                    .success = true,
                    .id = id,
                    .title = title,
                    .description = description,
                    .priority = priority,
                    .completed = completed == 1,
                    .updatedAt = now,
                }, 200);
            } else {
                ctx.json(.{ .err = "Todo not found" }, 404);
            }
        },
        else => {
            ctx.json(.{ .err = "Failed to update todo" }, 500);
        },
    }
}

/// Toggle todo completion status
/// PATCH /todos/:id/toggle
fn handleToggleTodo(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    const id_str = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing todo ID" }, 400);
        return;
    };

    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        ctx.json(.{ .err = "Invalid todo ID" }, 400);
        return;
    };

    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));

    // Toggle completed status using SQL
    var result = db.run(void, "UPDATE todos SET completed = 1 - completed, updated_at = ? WHERE id = ?", .{ now, id });
    defer result.deinit();

    switch (result) {
        .command => |cmd| {
            if (cmd.changes > 0) {
                // Fetch the updated todo to return current state
                var fetch = db.run(Todo, "SELECT id, title, description, completed, priority, created_at, updated_at FROM todos WHERE id = ?", .{id});
                defer fetch.deinit();

                const todo = switch (fetch) {
                    .rows => |*rows| rows.next(),
                    else => null,
                };

                if (todo) |t| {
                    ctx.json(.{
                        .success = true,
                        .id = t.id,
                        .title = t.title,
                        .completed = t.completed == 1,
                        .message = if (t.completed == 1) "Todo marked as completed" else "Todo marked as pending",
                    }, 200);
                } else {
                    ctx.json(.{ .success = true, .id = id, .toggled = true }, 200);
                }
            } else {
                ctx.json(.{ .err = "Todo not found" }, 404);
            }
        },
        else => {
            ctx.json(.{ .err = "Failed to toggle todo" }, 500);
        },
    }
}

/// Delete a todo
/// DELETE /todos/:id
fn handleDeleteTodo(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    const id_str = ctx.param("id") orelse {
        ctx.json(.{ .err = "Missing todo ID" }, 400);
        return;
    };

    const id = std.fmt.parseInt(u32, id_str, 10) catch {
        ctx.json(.{ .err = "Invalid todo ID" }, 400);
        return;
    };

    // Use run() for DELETE -> returns .command with changes count
    var result = db.run(void, "DELETE FROM todos WHERE id = ?", .{id});
    defer result.deinit();

    if (result.changes() > 0) {
        ctx.json(.{
            .success = true,
            .deleted = id,
            .message = "Todo deleted successfully",
        }, 200);
    } else {
        ctx.json(.{ .err = "Todo not found" }, 404);
    }
}

/// Delete all completed todos
/// DELETE /todos/completed
fn handleDeleteCompleted(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    // Use run() for batch DELETE
    var result = db.run(void, "DELETE FROM todos WHERE completed = 1", .{});
    defer result.deinit();

    const deleted = result.changes();
    ctx.json(.{
        .success = true,
        .deleted = deleted,
        .message = if (deleted > 0)
            "Completed todos deleted"
        else
            "No completed todos to delete",
    }, 200);
}

/// Get todo statistics
/// GET /stats
fn handleStats(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    // Get total count
    const CountResult = struct { count: u32 };

    var total_result = db.run(CountResult, "SELECT COUNT(*) as count FROM todos", .{});
    defer total_result.deinit();

    const total = switch (total_result) {
        .rows => |*rows| if (rows.next()) |r| r.count else 0,
        else => 0,
    };

    var completed_result = db.run(CountResult, "SELECT COUNT(*) as count FROM todos WHERE completed = 1", .{});
    defer completed_result.deinit();

    const completed = switch (completed_result) {
        .rows => |*rows| if (rows.next()) |r| r.count else 0,
        else => 0,
    };

    // Get counts by priority
    var high_result = db.run(CountResult, "SELECT COUNT(*) as count FROM todos WHERE priority = 'high' AND completed = 0", .{});
    defer high_result.deinit();

    const high_priority = switch (high_result) {
        .rows => |*rows| if (rows.next()) |r| r.count else 0,
        else => 0,
    };

    ctx.json(.{
        .total = total,
        .completed = completed,
        .pending = total - completed,
        .highPriority = high_priority,
        .completionRate = if (total > 0)
            @as(f32, @floatFromInt(completed)) / @as(f32, @floatFromInt(total)) * 100.0
        else
            0.0,
    }, 200);
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
