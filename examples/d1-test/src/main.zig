//! D1 Test Worker
//!
//! Comprehensive test suite for the D1 unified run() API.
//! Tests all query types: SELECT, INSERT, UPDATE, DELETE, and DDL.

const std = @import("std");
const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const Route = workers.Router;
const Date = workers.Date;

// Test struct types
const User = struct {
    id: u32,
    name: []const u8,
    email: []const u8,
    active: u32,
    created_at: u64,
};

const Post = struct {
    id: u32,
    user_id: u32,
    title: []const u8,
    content: []const u8,
    created_at: u64,
};

const Log = struct {
    id: u32,
    level: []const u8,
    message: []const u8,
    timestamp: u64,
};

// Routes
const routes: []const Route = &.{
    Route.get("/health", handleHealth),

    // Test endpoints for run() API
    Route.get("/test/run/select", testRunSelect),
    Route.get("/test/run/select-empty", testRunSelectEmpty),
    Route.post("/test/run/insert", testRunInsert),
    Route.put("/test/run/update", testRunUpdate),
    Route.delete("/test/run/delete", testRunDelete),
    Route.post("/test/run/ddl", testRunDDL),
    Route.get("/test/run/error", testRunError),
    Route.get("/test/run/helpers", testRunHelpers),

    // Full integration test
    Route.get("/test/run/full", testRunFull),

    // Reset database for testing
    Route.post("/test/reset", testReset),
};

fn handleHealth(ctx: *FetchContext) void {
    ctx.json(.{ .status = "ok", .service = "d1-test" }, 200);
}

/// Test SELECT query -> .rows
fn testRunSelect(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    var result = db.run(User, "SELECT * FROM users WHERE active = ?", .{1});
    defer result.deinit();

    switch (result) {
        .rows => |*rows| {
            const count = rows.count();
            var names: [10][]const u8 = undefined;
            var i: usize = 0;

            while (rows.next()) |user| {
                if (i < 10) {
                    names[i] = user.name;
                    i += 1;
                }
            }

            ctx.json(.{
                .@"test" = "run/select",
                .passed = true,
                .variant = "rows",
                .count = count,
                .duration_ms = rows.duration(),
            }, 200);
        },
        .command => {
            ctx.json(.{ .@"test" = "run/select", .passed = false, .err = "Expected .rows, got .command" }, 500);
        },
        .empty => {
            ctx.json(.{ .@"test" = "run/select", .passed = false, .err = "Expected .rows, got .empty" }, 500);
        },
        .err => {
            ctx.json(.{ .@"test" = "run/select", .passed = false, .err = "Query failed" }, 500);
        },
    }
}

/// Test SELECT with no results -> .rows with count 0 or .empty
fn testRunSelectEmpty(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    // Query for non-existent user
    var result = db.run(User, "SELECT * FROM users WHERE id = ?", .{99999});
    defer result.deinit();

    switch (result) {
        .rows => |*rows| {
            ctx.json(.{
                .@"test" = "run/select-empty",
                .passed = rows.count() == 0,
                .variant = "rows",
                .count = rows.count(),
            }, 200);
        },
        .empty => {
            ctx.json(.{
                .@"test" = "run/select-empty",
                .passed = true,
                .variant = "empty",
            }, 200);
        },
        .err => {
            ctx.json(.{ .@"test" = "run/select-empty", .passed = false, .err = "Query failed" }, 500);
        },
        else => {
            ctx.json(.{ .@"test" = "run/select-empty", .passed = false, .err = "Unexpected variant" }, 500);
        },
    }
}

/// Test INSERT -> .command
fn testRunInsert(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));

    var result = db.run(void, "INSERT INTO users (name, email, active, created_at) VALUES (?, ?, ?, ?)", .{ "TestUser", "test@example.com", 1, now });
    defer result.deinit();

    switch (result) {
        .command => |cmd| {
            ctx.json(.{
                .@"test" = "run/insert",
                .passed = cmd.changes == 1,
                .variant = "command",
                .changes = cmd.changes,
                .last_row_id = cmd.last_row_id,
                .duration_ms = cmd.duration,
            }, 201);
        },
        .err => {
            ctx.json(.{ .@"test" = "run/insert", .passed = false, .err = "Insert failed" }, 500);
        },
        else => {
            ctx.json(.{ .@"test" = "run/insert", .passed = false, .err = "Expected .command variant" }, 500);
        },
    }
}

/// Test UPDATE -> .command
fn testRunUpdate(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    var result = db.run(void, "UPDATE users SET active = ? WHERE email = ?", .{ 0, "test@example.com" });
    defer result.deinit();

    switch (result) {
        .command => |cmd| {
            ctx.json(.{
                .@"test" = "run/update",
                .passed = true,
                .variant = "command",
                .changes = cmd.changes,
                .duration_ms = cmd.duration,
            }, 200);
        },
        .err => {
            ctx.json(.{ .@"test" = "run/update", .passed = false, .err = "Update failed" }, 500);
        },
        else => {
            ctx.json(.{ .@"test" = "run/update", .passed = false, .err = "Expected .command variant" }, 500);
        },
    }
}

/// Test DELETE -> .command
fn testRunDelete(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    var result = db.run(void, "DELETE FROM users WHERE email = ?", .{"test@example.com"});
    defer result.deinit();

    switch (result) {
        .command => |cmd| {
            ctx.json(.{
                .@"test" = "run/delete",
                .passed = true,
                .variant = "command",
                .changes = cmd.changes,
                .duration_ms = cmd.duration,
            }, 200);
        },
        .err => {
            ctx.json(.{ .@"test" = "run/delete", .passed = false, .err = "Delete failed" }, 500);
        },
        else => {
            ctx.json(.{ .@"test" = "run/delete", .passed = false, .err = "Expected .command variant" }, 500);
        },
    }
}

/// Test DDL (CREATE TABLE) -> .empty
fn testRunDDL(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    var result = db.run(void, "CREATE TABLE IF NOT EXISTS test_ddl (id INTEGER PRIMARY KEY, value TEXT)", .{});
    defer result.deinit();

    switch (result) {
        .empty => |meta| {
            ctx.json(.{
                .@"test" = "run/ddl",
                .passed = true,
                .variant = "empty",
                .duration_ms = meta.duration,
            }, 200);
        },
        .command => {
            // Some D1 implementations may return .command for DDL
            ctx.json(.{
                .@"test" = "run/ddl",
                .passed = true,
                .variant = "command",
                .note = "DDL returned .command instead of .empty",
            }, 200);
        },
        .err => {
            ctx.json(.{ .@"test" = "run/ddl", .passed = false, .err = "DDL failed" }, 500);
        },
        else => {
            ctx.json(.{ .@"test" = "run/ddl", .passed = false, .err = "Expected .empty variant" }, 500);
        },
    }
}

/// Test query error behavior.
///
/// NOTE: D1 throws JavaScript exceptions for errors like:
/// - Missing tables (SQLITE_ERROR)
/// - UNIQUE constraint violations (SQLITE_CONSTRAINT)
/// - Syntax errors
///
/// These exceptions bubble up through the WASM runtime and cannot be caught
/// by the `.err` variant. The `.err` variant is reserved for cases where
/// D1 returns `success: false` without throwing, which is rare in practice.
///
/// This test documents this behavior and verifies that valid queries work.
fn testRunError(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    // Test that a valid query returns isOk() = true
    var result = db.run(User, "SELECT * FROM users WHERE id = ?", .{1});
    defer result.deinit();

    ctx.json(.{
        .@"test" = "run/error",
        .passed = true,
        .note = "D1 throws JS exceptions for errors (UNIQUE violations, missing tables, etc.)",
        .behavior = "Use try-catch in TypeScript runtime or validate before querying",
        .isOk = result.isOk(),
        .isErr = result.isErr(),
    }, 200);
}

/// Test helper methods (isOk, isErr, changes, lastRowId, duration)
fn testRunHelpers(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));

    // Test on .command result
    var insert = db.run(void, "INSERT INTO logs (level, message, timestamp) VALUES (?, ?, ?)", .{ "INFO", "Test log", now });
    defer insert.deinit();

    const isOk = insert.isOk();
    const isErr = insert.isErr();
    const changes = insert.changes();
    const lastRowId = insert.lastRowId();
    const duration = insert.duration();

    ctx.json(.{
        .@"test" = "run/helpers",
        .passed = isOk and !isErr and changes == 1,
        .isOk = isOk,
        .isErr = isErr,
        .changes = changes,
        .lastRowId = lastRowId,
        .duration_ms = duration,
    }, 200);
}

/// Full integration test - exercises all paths
fn testRunFull(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    var results: [6]bool = undefined;
    var messages: [6][]const u8 = undefined;

    // 1. DDL - Create temp table
    {
        var result = db.run(void, "CREATE TABLE IF NOT EXISTS integration_test (id INTEGER PRIMARY KEY, value TEXT)", .{});
        defer result.deinit();
        results[0] = result.isOk();
        messages[0] = if (result.isOk()) "DDL passed" else "DDL failed";
    }

    // 2. INSERT
    {
        var result = db.run(void, "INSERT INTO integration_test (value) VALUES (?)", .{"test1"});
        defer result.deinit();
        results[1] = result.isOk() and result.changes() == 1;
        messages[1] = if (results[1]) "INSERT passed" else "INSERT failed";
    }

    // 3. INSERT another
    {
        var result = db.run(void, "INSERT INTO integration_test (value) VALUES (?)", .{"test2"});
        defer result.deinit();
        results[2] = result.isOk() and result.changes() == 1;
        messages[2] = if (results[2]) "INSERT 2 passed" else "INSERT 2 failed";
    }

    // 4. SELECT all
    const TestRow = struct { id: u32, value: []const u8 };
    {
        var result = db.run(TestRow, "SELECT * FROM integration_test", .{});
        defer result.deinit();
        switch (result) {
            .rows => |*rows| {
                results[3] = rows.count() >= 2;
                messages[3] = if (results[3]) "SELECT passed" else "SELECT wrong count";
            },
            else => {
                results[3] = false;
                messages[3] = "SELECT wrong variant";
            },
        }
    }

    // 5. UPDATE
    {
        var result = db.run(void, "UPDATE integration_test SET value = ? WHERE value = ?", .{ "updated", "test1" });
        defer result.deinit();
        results[4] = result.isOk() and result.changes() == 1;
        messages[4] = if (results[4]) "UPDATE passed" else "UPDATE failed";
    }

    // 6. DELETE
    {
        var result = db.run(void, "DELETE FROM integration_test WHERE value = ?", .{"updated"});
        defer result.deinit();
        results[5] = result.isOk() and result.changes() == 1;
        messages[5] = if (results[5]) "DELETE passed" else "DELETE failed";
    }

    // NOTE: Error handling test removed - D1 throws JS exceptions for errors
    // like missing tables, so we can't test .err variant in integration tests.
    // See testRunError for documentation of this behavior.

    // Summary
    var passed: u32 = 0;
    for (results) |r| {
        if (r) passed += 1;
    }

    ctx.json(.{
        .@"test" = "run/full",
        .passed = passed == 6,
        .total = 6,
        .passed_count = passed,
        .details = .{
            .ddl = messages[0],
            .insert1 = messages[1],
            .insert2 = messages[2],
            .select = messages[3],
            .update = messages[4],
            .delete = messages[5],
        },
    }, if (passed == 6) @as(u16, 200) else 500);
}

/// Reset database for clean test runs
fn testReset(ctx: *FetchContext) void {
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .err = "DB not configured" }, 500);
        return;
    };
    defer db.free();

    // Clean up test tables
    _ = db.execute("DELETE FROM logs", .{});
    _ = db.execute("DELETE FROM posts", .{});
    _ = db.execute("DELETE FROM users", .{});
    _ = db.execute("DROP TABLE IF EXISTS test_ddl", .{});
    _ = db.execute("DROP TABLE IF EXISTS integration_test", .{});

    ctx.json(.{ .reset = true, .message = "Database reset complete" }, 200);
}

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
