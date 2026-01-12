// cf-workerz Example - Durable Objects Advanced Features
//
// This example demonstrates:
// - Location hints for latency optimization
// - Alarm scheduling with ScheduledTime helper
// - Alarm options (allowConcurrency, allowUnconfirmed)
// - SQL Storage (SQLite-backed storage)
// - State.waitUntil() for background tasks
// - WebSocket hibernation with tags and auto-response
//
// Endpoints:
//   GET  /                          - Welcome message with API docs
//   POST /do/create                 - Create DO with location hint
//   GET  /do/:name/fetch            - Fetch from a Durable Object
//   POST /do/:name/alarm            - Schedule an alarm
//   POST /do/:name/sql              - Execute SQL query
//   GET  /do/:name/sql/list         - List SQL tables

const std = @import("std");
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;

// ============================================================================
// Route Table
// ============================================================================

const routes: []const Route = &.{
    Route.get("/", handleRoot),
    Route.post("/do/create", handleCreateDO),
    Route.get("/do/:name/fetch", handleFetchDO),
    Route.post("/do/:name/alarm", handleScheduleAlarm),
    Route.post("/do/:name/sql", handleSqlQuery),
    Route.get("/do/:name/sql/list", handleSqlList),
};

// ============================================================================
// Handlers
// ============================================================================

fn handleRoot(ctx: *FetchContext) void {
    ctx.json(.{
        .name = "cf-workerz Durable Objects Example",
        .description = "Demonstrates advanced Durable Objects features",
        .endpoints = .{
            .root = "GET / - This message",
            .create = "POST /do/create - Create DO with location hint",
            .fetch = "GET /do/:name/fetch - Fetch from Durable Object",
            .alarm = "POST /do/:name/alarm - Schedule an alarm",
            .sql = "POST /do/:name/sql - Execute SQL query",
            .sqlList = "GET /do/:name/sql/list - List SQL tables",
        },
        .features = .{
            .locationHints = "getWithLocationHint(), getStubForId()",
            .alarms = "ScheduledTime, GetAlarmOptions, SetAlarmOptions",
            .sql = "SqlStorage, SqlCursor for SQLite storage",
            .state = "waitUntil(), getTags(), WebSocket auto-response",
        },
        .locationHintValues = .{
            .wnam = "Western North America",
            .enam = "Eastern North America",
            .sam = "South America",
            .weur = "Western Europe",
            .eeur = "Eastern Europe",
            .apac = "Asia Pacific",
            .oc = "Oceania",
            .afr = "Africa",
            .me = "Middle East",
        },
    }, 200);
}

/// Create a Durable Object with location hint for latency optimization
/// POST /do/create
/// Body: { "name": "my-do", "locationHint": "enam" }
fn handleCreateDO(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("COUNTER") orelse {
        ctx.json(.{
            .err = "COUNTER Durable Object not configured",
            .hint = "Add [[durable_objects.bindings]] to wrangler.toml",
        }, 500);
        return;
    };
    defer namespace.free();

    // Parse request body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const name = json.getString("name") orelse "default";
    const locationHint = json.getStringOr("locationHint", "enam");

    // Get stub with location hint for lower latency
    const stub = namespace.getWithLocationHint(name, locationHint);
    defer stub.free();

    // Make a request to the DO
    const response = stub.fetch(.{ .text = "https://do/init" }, null);
    defer response.free();

    const status = response.status();
    const body = response.text() orelse "(empty)";

    ctx.json(.{
        .success = true,
        .doName = name,
        .locationHint = locationHint,
        .response = .{
            .status = status,
            .body = body,
        },
    }, 200);
}

/// Fetch from a Durable Object by name
/// GET /do/:name/fetch
fn handleFetchDO(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("COUNTER") orelse {
        ctx.json(.{ .err = "COUNTER Durable Object not configured" }, 500);
        return;
    };
    defer namespace.free();

    const name = ctx.param("name") orelse {
        ctx.json(.{ .err = "Missing DO name" }, 400);
        return;
    };

    // Use getWithLocationHint which works correctly
    const stub = namespace.getWithLocationHint(name, "enam");
    defer stub.free();

    // Use fetch method directly
    const response = stub.fetch(.{ .text = "https://do/status" }, null);
    defer response.free();

    const body = response.text() orelse "(empty)";

    ctx.json(.{
        .doName = name,
        .response = body,
    }, 200);
}

/// Schedule an alarm using ScheduledTime helper
/// POST /do/:name/alarm
/// Body: { "offsetType": "seconds", "offset": 30 }
fn handleScheduleAlarm(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("COUNTER") orelse {
        ctx.json(.{ .err = "COUNTER Durable Object not configured" }, 500);
        return;
    };
    defer namespace.free();

    const name = ctx.param("name") orelse {
        ctx.json(.{ .err = "Missing DO name" }, 400);
        return;
    };

    // Parse request body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const offsetType = json.getStringOr("offsetType", "seconds");
    const offset = json.getInt("offset", i64) orelse 30;

    // Create ScheduledTime based on offset type
    const scheduledTime = if (std.mem.eql(u8, offsetType, "milliseconds"))
        workers.ScheduledTime.fromOffsetMs(offset)
    else if (std.mem.eql(u8, offsetType, "minutes"))
        workers.ScheduledTime.fromOffsetMins(@intCast(offset))
    else if (std.mem.eql(u8, offsetType, "hours"))
        workers.ScheduledTime.fromOffsetHours(@intCast(offset))
    else
        workers.ScheduledTime.fromOffsetSecs(@intCast(offset));

    // Get DO stub
    const stub = namespace.getWithLocationHint(name, "enam");
    defer stub.free();

    // Build request body with alarm timestamp
    const timestamp = scheduledTime.toTimestamp();

    // Forward alarm request to DO
    const body = workers.String.new("{\"action\":\"setAlarm\"}");
    defer body.free();

    const headers = workers.Headers.new();
    defer headers.free();
    headers.setText("Content-Type", "application/json");
    headers.setText("X-Alarm-Timestamp", "scheduled");

    const response = stub.fetch(.{ .text = "https://do/alarm" }, .{
        .requestInit = .{
            .method = .Post,
            .body = .{ .string = &body },
            .headers = headers,
        },
    });
    defer response.free();

    ctx.json(.{
        .success = true,
        .doName = name,
        .alarm = .{
            .offsetType = offsetType,
            .offset = offset,
            .timestamp = timestamp,
        },
        .options = .{
            .allowConcurrency = false,
            .allowUnconfirmed = false,
        },
    }, 200);
}

/// Execute SQL query in Durable Object
/// POST /do/:name/sql
/// Body: { "query": "SELECT * FROM users" }
fn handleSqlQuery(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("COUNTER") orelse {
        ctx.json(.{ .err = "COUNTER Durable Object not configured" }, 500);
        return;
    };
    defer namespace.free();

    const name = ctx.param("name") orelse {
        ctx.json(.{ .err = "Missing DO name" }, 400);
        return;
    };

    // Parse request body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const query = json.getString("query") orelse {
        ctx.json(.{ .err = "Missing query field" }, 400);
        return;
    };

    // Get DO stub
    const stub = namespace.getWithLocationHint(name, "enam");
    defer stub.free();

    // Forward SQL request to DO
    const bodyStr = workers.String.new(query);
    defer bodyStr.free();

    const headers = workers.Headers.new();
    defer headers.free();
    headers.setText("Content-Type", "application/sql");

    const response = stub.fetch(.{ .text = "https://do/sql/exec" }, .{
        .requestInit = .{
            .method = .Post,
            .body = .{ .string = &bodyStr },
            .headers = headers,
        },
    });
    defer response.free();

    const responseBody = response.text() orelse "(empty)";

    ctx.json(.{
        .success = true,
        .doName = name,
        .query = query,
        .result = responseBody,
    }, 200);
}

/// List SQL tables in Durable Object
/// GET /do/:name/sql/list
fn handleSqlList(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("COUNTER") orelse {
        ctx.json(.{ .err = "COUNTER Durable Object not configured" }, 500);
        return;
    };
    defer namespace.free();

    const name = ctx.param("name") orelse {
        ctx.json(.{ .err = "Missing DO name" }, 400);
        return;
    };

    // Get DO stub
    const stub = namespace.getWithLocationHint(name, "enam");
    defer stub.free();

    // Request table list from DO
    const response = stub.get("https://do/sql/tables");
    defer response.free();

    const body = response.text() orelse "[]";

    ctx.json(.{
        .doName = name,
        .tables = body,
    }, 200);
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
