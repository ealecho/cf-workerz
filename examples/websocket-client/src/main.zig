// cf-workerz Example - WebSocket Client (Outbound Connections)
//
// This example demonstrates:
// - Outbound WebSocket connections using wsConnect()
// - WebSocket connections with subprotocol negotiation
// - WebSocket event types (MessageEvent, CloseEvent, ErrorEvent)
// - WebSocketIncomingMessage for text/binary handling
// - Inbound WebSocket handling (server-side)
//
// Endpoints:
//   GET  /                     - Welcome message with API docs
//   GET  /ws/echo              - Connect to external echo server
//   GET  /ws/connect           - Upgrade to WebSocket (inbound)
//   POST /ws/send              - Send message via outbound WebSocket

const std = @import("std");
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;

// ============================================================================
// Route Table
// ============================================================================

const routes: []const Route = &.{
    Route.get("/", handleRoot),
    Route.get("/ws/echo", handleEchoClient),
    Route.get("/ws/connect", handleWebSocketUpgrade),
    Route.post("/ws/send", handleSendMessage),
};

// ============================================================================
// Handlers
// ============================================================================

fn handleRoot(ctx: *FetchContext) void {
    ctx.json(.{
        .name = "cf-workerz WebSocket Client Example",
        .description = "Demonstrates outbound WebSocket connections and event handling",
        .endpoints = .{
            .root = "GET / - This message",
            .echo = "GET /ws/echo - Connect to external echo server",
            .connect = "GET /ws/connect - Upgrade to WebSocket",
            .send = "POST /ws/send - Send message via outbound WebSocket",
        },
        .features = .{
            .outbound = "wsConnect() / wsConnectWithProtocols()",
            .events = "MessageEvent, CloseEvent, ErrorEvent",
            .messages = "WebSocketIncomingMessage (text/binary)",
        },
    }, 200);
}

/// Connect to an external WebSocket echo server and send a test message
/// GET /ws/echo
fn handleEchoClient(ctx: *FetchContext) void {
    // Connect to a public WebSocket echo server
    // Note: In production, use a real WebSocket endpoint
    var ws = workers.wsConnect("wss://echo.websocket.org") orelse {
        ctx.json(.{
            .success = false,
            .err = "Failed to connect to WebSocket server",
        }, 502);
        return;
    };
    defer ws.free();

    // Accept the connection (required before sending)
    ws.accept();

    // Check connection state
    const state = ws.readyState();

    // Send a test message
    ws.sendText("Hello from cf-workerz!");

    // Get extensions if any
    const extensions = ws.extensions();
    const protocol = ws.protocol();

    ctx.json(.{
        .success = true,
        .action = "Connected to echo.websocket.org",
        .readyState = @tagName(state),
        .extensions = extensions,
        .protocol = protocol,
        .messageSent = "Hello from cf-workerz!",
    }, 200);
}

/// Upgrade incoming HTTP request to WebSocket (server-side)
/// GET /ws/connect
fn handleWebSocketUpgrade(ctx: *FetchContext) void {
    // Check for WebSocket upgrade header
    const upgrade = ctx.header("Upgrade") orelse "";
    if (!std.mem.eql(u8, upgrade, "websocket")) {
        ctx.json(.{
            .err = "Expected WebSocket upgrade",
            .hint = "Send request with 'Upgrade: websocket' header",
        }, 426);
        return;
    }

    // Create a WebSocket pair
    const pair = workers.WebSocketPair.new();
    defer pair.free();

    // Get server-side WebSocket
    var server = pair.server();
    defer server.free();

    // Accept the connection
    server.accept();

    // Send a welcome message
    server.sendText("{\"type\":\"connected\",\"message\":\"Welcome to cf-workerz WebSocket!\"}");

    // Get client WebSocket for response
    const client = pair.client();
    defer client.free();

    // Return upgrade response
    const response = workers.Response.webSocketUpgrade(&client);
    defer response.free();
    ctx.send(&response);
}

/// Send a message via outbound WebSocket with protocol negotiation
/// POST /ws/send
fn handleSendMessage(ctx: *FetchContext) void {
    // Parse JSON body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const url = json.getString("url") orelse "wss://echo.websocket.org";
    const message = json.getStringOr("message", "Hello!");

    // Check if protocols are specified
    if (json.getString("protocol")) |protocol| {
        // Connect with subprotocol negotiation
        const protocols = [_][]const u8{protocol};
        var ws = workers.wsConnectWithProtocols(url, &protocols) orelse {
            ctx.json(.{ .success = false, .err = "Failed to connect" }, 502);
            return;
        };
        defer ws.free();

        // Accept connection before sending
        ws.accept();
        ws.sendText(message);

        ctx.json(.{
            .success = true,
            .url = url,
            .protocol = protocol,
            .messageSent = message,
        }, 200);
    } else {
        // Simple connection without protocols
        var ws = workers.wsConnect(url) orelse {
            ctx.json(.{ .success = false, .err = "Failed to connect" }, 502);
            return;
        };
        defer ws.free();

        // Accept connection before sending
        ws.accept();
        ws.sendText(message);

        ctx.json(.{
            .success = true,
            .url = url,
            .messageSent = message,
        }, 200);
    }
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
