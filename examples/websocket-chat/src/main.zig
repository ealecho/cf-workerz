// cf-workerz Example - WebSocket Chat with Durable Objects
//
// This example demonstrates:
// - Real-time WebSocket chat using Durable Objects
// - WebSocket message broadcasting to all connected clients
// - Message persistence using DO storage
// - WebSocket hibernation for efficiency
//
// Based on Upstash's cloudflare-websockets example, ported to cf-workerz.
// Original: https://github.com/upstash/examples/tree/main/examples/cloudflare-websockets
//
// Endpoints:
//   GET  /              - Welcome message with API docs
//   GET  /ws            - Upgrade to WebSocket (chat)
//   GET  /history       - Get chat history (last 20 messages)
//   POST /message       - Send message via HTTP (for testing)

const std = @import("std");
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;
const Middleware = workers.Middleware;

// ============================================================================
// CORS Middleware
// ============================================================================

/// CORS middleware - handles preflight OPTIONS requests and adds CORS headers.
/// Required for cross-origin requests from the React client on Cloudflare Pages.
fn corsMiddleware(ctx: *FetchContext) bool {
    // Handle preflight OPTIONS requests
    if (ctx.method() == .Options) {
        const headers = workers.Headers.new();
        defer headers.free();
        headers.setText("Access-Control-Allow-Origin", "*");
        headers.setText("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        headers.setText("Access-Control-Allow-Headers", "Content-Type, Authorization, Upgrade, Connection");
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

const middleware = Middleware{
    .before = &.{corsMiddleware},
    .after = &.{},
};

// ============================================================================
// Route Table
// ============================================================================

const routes: []const Route = &.{
    Route.get("/", handleRoot),
    Route.get("/ws", handleWebSocket),
    Route.get("/history", handleHistory),
    Route.post("/message", handlePostMessage),
};

// ============================================================================
// Handlers
// ============================================================================

fn handleRoot(ctx: *FetchContext) void {
    ctx.json(.{
        .name = "cf-workerz WebSocket Chat",
        .description = "Real-time chat using WebSockets and Durable Objects",
        .endpoints = .{
            .root = "GET / - This message",
            .ws = "GET /ws - Upgrade to WebSocket for chat",
            .history = "GET /history - Get chat history (last 20 messages)",
            .message = "POST /message - Send message via HTTP",
        },
        .features = .{
            .realtime = "WebSocket bidirectional communication",
            .persistence = "Messages stored in Durable Object storage",
            .broadcast = "Messages broadcast to all connected clients",
            .hibernation = "Efficient WebSocket hibernation support",
        },
        .usage = .{
            .step1 = "Connect via WebSocket to /ws",
            .step2 = "Send JSON: {\"type\":\"init\",\"userId\":\"your-name\"}",
            .step3 = "Send JSON: {\"type\":\"message\",\"content\":\"Hello!\"}",
            .step4 = "Receive messages from other users in real-time",
        },
    }, 200);
}

/// Upgrade to WebSocket and connect to chat room
/// GET /ws
fn handleWebSocket(ctx: *FetchContext) void {
    // Check for WebSocket upgrade header
    const upgrade = ctx.header("Upgrade") orelse "";
    if (!std.mem.eql(u8, upgrade, "websocket")) {
        ctx.json(.{
            .err = "Expected WebSocket upgrade",
            .hint = "Connect using a WebSocket client",
        }, 426);
        return;
    }

    // Get the ChatRoom Durable Object
    const namespace = ctx.env.durableObject("CHAT_ROOM") orelse {
        ctx.json(.{
            .err = "CHAT_ROOM Durable Object not configured",
            .hint = "Add [[durable_objects.bindings]] to wrangler.toml",
        }, 500);
        return;
    };
    defer namespace.free();

    // Get or create the default chat room
    const stub = namespace.getWithLocationHint("default", "enam");
    defer stub.free();

    // Forward the WebSocket upgrade to the Durable Object
    // The DO will handle the actual WebSocket connection
    const response = stub.fetch(.{ .request = &ctx.req }, null);
    defer response.free();

    // Send the response (which includes the WebSocket upgrade)
    ctx.send(&response);
}

/// Get chat history
/// GET /history
fn handleHistory(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("CHAT_ROOM") orelse {
        ctx.json(.{ .err = "CHAT_ROOM not configured" }, 500);
        return;
    };
    defer namespace.free();

    const stub = namespace.getWithLocationHint("default", "enam");
    defer stub.free();

    const response = stub.fetch(.{ .text = "https://do/history" }, null);
    defer response.free();

    const body = response.text() orelse "[]";
    ctx.text(body, 200);
}

/// Send a message via HTTP (for testing without WebSocket client)
/// POST /message
/// Body: { "userId": "test-user", "content": "Hello!" }
fn handlePostMessage(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("CHAT_ROOM") orelse {
        ctx.json(.{ .err = "CHAT_ROOM not configured" }, 500);
        return;
    };
    defer namespace.free();

    const stub = namespace.getWithLocationHint("default", "enam");
    defer stub.free();

    // Forward the request to the Durable Object
    // The DO will handle validation and processing
    const response = stub.fetch(.{ .request = &ctx.req }, null);
    defer response.free();

    const responseBody = response.text() orelse "{}";
    ctx.text(responseBody, @intFromEnum(response.status()));
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatchWithMiddleware(routes, ctx, middleware);
}
