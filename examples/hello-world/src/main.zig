// Hello World Example - cf-workerz
//
// A minimal example demonstrating:
// - Built-in Router with path parameters
// - Response helpers (ctx.json, ctx.text, ctx.redirect)
// - Basic request handling
//
// Endpoints:
//   GET  /              - Welcome message
//   GET  /hello/:name   - Personalized greeting
//   GET  /health        - Health check
//   GET  /echo          - Echo request info

const std = @import("std");
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;

// ============================================================================
// Route Table
// ============================================================================

const routes: []const Route = &.{
    Route.get("/", handleRoot),
    Route.get("/hello/:name", handleHello),
    Route.get("/health", handleHealth),
    Route.get("/echo", handleEcho),
};

// ============================================================================
// Handlers
// ============================================================================

fn handleRoot(ctx: *FetchContext) void {
    const json =
        \\{
        \\  "message": "Welcome to cf-workerz!",
        \\  "version": "0.1.0",
        \\  "endpoints": {
        \\    "GET /": "This message",
        \\    "GET /hello/:name": "Personalized greeting",
        \\    "GET /health": "Health check",
        \\    "GET /echo": "Echo request info"
        \\  }
        \\}
    ;
    ctx.json(json, 200);
}

fn handleHello(ctx: *FetchContext) void {
    const name = ctx.params.get("name") orelse "World";

    var buf: [256]u8 = undefined;
    const response = std.fmt.bufPrint(&buf, "{{\"message\":\"Hello, {s}!\"}}", .{name}) catch {
        ctx.throw(500, "Name too long");
        return;
    };

    ctx.json(response, 200);
}

fn handleHealth(ctx: *FetchContext) void {
    ctx.json("{\"status\":\"healthy\",\"service\":\"cf-workerz\"}", 200);
}

fn handleEcho(ctx: *FetchContext) void {
    const method = ctx.req.method();
    const method_str = @tagName(method);
    const path = ctx.path;

    var buf: [512]u8 = undefined;
    const response = std.fmt.bufPrint(&buf, "{{\"method\":\"{s}\",\"path\":\"{s}\"}}", .{ method_str, path }) catch {
        ctx.throw(500, "Buffer overflow");
        return;
    };

    ctx.json(response, 200);
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
