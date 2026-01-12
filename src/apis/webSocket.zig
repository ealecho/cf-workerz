//! WebSocket API for Cloudflare Workers.
//!
//! WebSockets enable real-time, bidirectional communication between clients
//! and your Worker. Cloudflare Workers supports the standard WebSocket API
//! with extensions for hibernation and Durable Objects.
//!
//! ## Quick Start - Basic WebSocket Handler
//!
//! ```zig
//! const workers = @import("cf-workerz");
//! const FetchContext = workers.FetchContext;
//! const WebSocketPair = workers.WebSocketPair;
//! const Response = workers.Response;
//!
//! fn handleWebSocket(ctx: *FetchContext) void {
//!     // Create a WebSocket pair
//!     const pair = WebSocketPair.new();
//!     defer pair.free();
//!
//!     // Get the server-side WebSocket
//!     var server = pair.server();
//!     defer server.free();
//!
//!     // Accept the connection
//!     server.accept();
//!
//!     // Send a welcome message
//!     server.sendText("Welcome to the WebSocket server!");
//!
//!     // Get the client WebSocket for the response
//!     const client = pair.client();
//!     defer client.free();
//!
//!     // Return the upgrade response
//!     const response = Response.webSocket(&client);
//!     defer response.free();
//!     ctx.send(&response);
//! }
//! ```
//!
//! ## Configuration
//!
//! No special configuration is required for basic WebSocket support.
//! For Durable Objects with WebSocket hibernation, see the Durable Objects API.

const std = @import("std");
const allocator = std.heap.page_allocator;
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const Null = common.Null;
const Undefined = common.Undefined;
const True = common.True;
const False = common.False;
const DefaultValueSize = common.DefaultValueSize;
const Classes = common.Classes;
const jsCreateClass = common.jsCreateClass;
const object = @import("../bindings/object.zig");
const Object = object.Object;
const getObjectValue = object.getObjectValue;
const getObjectValueNum = object.getObjectValueNum;
const string = @import("../bindings/string.zig");
const String = string.String;
const getStringFree = string.getStringFree;
const Array = @import("../bindings/array.zig").Array;
const ArrayBuffer = @import("../bindings/arraybuffer.zig").ArrayBuffer;
const Function = @import("../bindings/function.zig").Function;
const AsyncFunction = @import("../bindings/function.zig").AsyncFunction;
const Headers = @import("../bindings/headers.zig").Headers;
const Response = @import("../bindings/response.zig").Response;
const fetch_api = @import("fetch.zig");

/// WebSocket ready states.
///
/// These correspond to the standard WebSocket readyState values.
pub const ReadyState = enum(u16) {
    /// The connection is not yet open (connecting).
    Connecting = 0,
    /// The connection is open and ready to communicate.
    Open = 1,
    /// The connection is in the process of closing.
    Closing = 2,
    /// The connection is closed.
    Closed = 3,

    pub fn fromInt(value: u16) ReadyState {
        return switch (value) {
            0 => .Connecting,
            1 => .Open,
            2 => .Closing,
            3 => .Closed,
            else => .Closed,
        };
    }
};

/// WebSocket close codes.
///
/// Standard WebSocket close codes as defined in RFC 6455.
pub const CloseCode = enum(u16) {
    /// Normal closure; the connection successfully completed.
    NormalClosure = 1000,
    /// The endpoint is going away (e.g., server shutting down).
    GoingAway = 1001,
    /// The endpoint is terminating due to a protocol error.
    ProtocolError = 1002,
    /// The endpoint received data it cannot accept (e.g., text when expecting binary).
    UnsupportedData = 1003,
    /// Reserved. No status code was provided.
    NoStatusReceived = 1005,
    /// Reserved. The connection was closed abnormally.
    AbnormalClosure = 1006,
    /// The endpoint received a message with inconsistent data (e.g., invalid UTF-8).
    InvalidFramePayloadData = 1007,
    /// The endpoint received a message that violates its policy.
    PolicyViolation = 1008,
    /// The message is too big to process.
    MessageTooBig = 1009,
    /// The client expected the server to negotiate an extension.
    MandatoryExtension = 1010,
    /// The server encountered an unexpected condition.
    InternalError = 1011,
    /// The connection was closed due to TLS handshake failure.
    TLSHandshake = 1015,

    pub fn toInt(self: CloseCode) u16 {
        return @intFromEnum(self);
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1881

/// A WebSocket connection.
///
/// WebSocket provides a bidirectional communication channel between a client
/// and your Worker. Use `WebSocketPair.new()` to create a connected pair of
/// WebSockets for handling upgrade requests.
///
/// ## Example
///
/// ```zig
/// fn handleWebSocket(ctx: *FetchContext) void {
///     const pair = WebSocketPair.new();
///     defer pair.free();
///
///     var server = pair.server();
///     defer server.free();
///
///     server.accept();
///     server.sendText("Hello from server!");
///
///     const client = pair.client();
///     defer client.free();
///
///     const response = Response.webSocket(&client);
///     ctx.send(&response);
/// }
/// ```
pub const WebSocket = struct {
    id: u32,

    pub fn init(ptr: u32) WebSocket {
        return WebSocket{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const WebSocket) void {
        jsFree(self.id);
    }

    // ========================================================================
    // Properties
    // ========================================================================

    /// Get the current ready state of the WebSocket.
    ///
    /// Returns one of: `Connecting`, `Open`, `Closing`, or `Closed`.
    ///
    /// ## Example
    ///
    /// ```zig
    /// if (ws.readyState() == .Open) {
    ///     ws.sendText("Connection is open!");
    /// }
    /// ```
    pub fn readyState(self: *const WebSocket) ReadyState {
        const state = getObjectValueNum(self.id, "readyState", u16);
        return ReadyState.fromInt(state);
    }

    /// Get the URL of the WebSocket connection.
    ///
    /// Returns the URL that was used to establish the connection.
    /// The caller must free the returned string.
    pub fn url(self: *const WebSocket) ?[]const u8 {
        const urlPtr = getObjectValue(self.id, "url");
        if (urlPtr <= DefaultValueSize) return null;
        return getStringFree(urlPtr);
    }

    /// Get the protocol selected by the server.
    ///
    /// Returns the subprotocol selected during the handshake, or null if none.
    pub fn protocol(self: *const WebSocket) ?[]const u8 {
        const protocolPtr = getObjectValue(self.id, "protocol");
        if (protocolPtr <= DefaultValueSize) return null;
        return getStringFree(protocolPtr);
    }

    /// Get the extensions negotiated with the server.
    ///
    /// Returns the extensions negotiated during the handshake.
    pub fn extensions(self: *const WebSocket) ?[]const u8 {
        const extPtr = getObjectValue(self.id, "extensions");
        if (extPtr <= DefaultValueSize) return null;
        return getStringFree(extPtr);
    }

    // ========================================================================
    // Methods
    // ========================================================================

    /// Accept the WebSocket connection.
    ///
    /// This must be called on the server-side WebSocket before sending any messages.
    /// It signals that the Worker is ready to receive messages.
    ///
    /// ## Example
    ///
    /// ```zig
    /// var server = pair.server();
    /// defer server.free();
    /// server.accept();
    /// ```
    pub fn accept(self: *const WebSocket) void {
        const func = Function.init(getObjectValue(self.id, "accept"));
        defer func.free();
        _ = func.call();
    }

    /// Send a text message over the WebSocket.
    ///
    /// ## Parameters
    ///
    /// - `message`: The UTF-8 text message to send.
    ///
    /// ## Example
    ///
    /// ```zig
    /// server.sendText("Hello, client!");
    /// server.sendText("{\"type\":\"ping\",\"timestamp\":123}");
    /// ```
    pub fn sendText(self: *const WebSocket, message: []const u8) void {
        const func = Function.init(getObjectValue(self.id, "send"));
        defer func.free();

        const str = String.new(message);
        defer str.free();

        _ = func.callArgsID(str.id);
    }

    /// Send a text message using a JavaScript String object.
    ///
    /// Use this when you already have a JavaScript String to avoid copying.
    pub fn sendString(self: *const WebSocket, message: *const String) void {
        const func = Function.init(getObjectValue(self.id, "send"));
        defer func.free();
        _ = func.callArgsID(message.id);
    }

    /// Send binary data over the WebSocket.
    ///
    /// ## Parameters
    ///
    /// - `data`: The binary data to send as a byte slice.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const data = [_]u8{ 0x00, 0x01, 0x02, 0x03 };
    /// server.sendBytes(&data);
    /// ```
    pub fn sendBytes(self: *const WebSocket, data: []const u8) void {
        const func = Function.init(getObjectValue(self.id, "send"));
        defer func.free();

        const ab = ArrayBuffer.new(data);
        defer ab.free();

        _ = func.callArgsID(ab.id);
    }

    /// Send an ArrayBuffer over the WebSocket.
    ///
    /// Use this when you already have an ArrayBuffer to avoid copying.
    pub fn sendArrayBuffer(self: *const WebSocket, buffer: *const ArrayBuffer) void {
        const func = Function.init(getObjectValue(self.id, "send"));
        defer func.free();
        _ = func.callArgsID(buffer.id);
    }

    /// Close the WebSocket connection.
    ///
    /// Initiates the WebSocket closing handshake. Optionally provide a close
    /// code and reason.
    ///
    /// ## Parameters
    ///
    /// - `code`: Optional close code (default: 1000 NormalClosure).
    /// - `reason`: Optional close reason (max 123 bytes).
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Normal close
    /// ws.close(null, null);
    ///
    /// // Close with code and reason
    /// ws.close(.NormalClosure, "Goodbye!");
    ///
    /// // Close with custom code
    /// ws.close(.GoingAway, "Server shutting down");
    /// ```
    pub fn close(self: *const WebSocket, code: ?CloseCode, reason: ?[]const u8) void {
        const func = Function.init(getObjectValue(self.id, "close"));
        defer func.free();

        const args = Array.new();
        defer args.free();

        if (code) |c| {
            args.pushNum(u16, c.toInt());
        } else {
            args.pushID(Undefined);
        }

        if (reason) |r| {
            const reasonStr = String.new(r);
            defer reasonStr.free();
            args.push(&reasonStr);
        }

        _ = func.callArgs(&args);
    }

    /// Close the WebSocket with a numeric code.
    ///
    /// Use this for custom close codes outside the `CloseCode` enum.
    pub fn closeWithCode(self: *const WebSocket, code: u16, reason: ?[]const u8) void {
        const func = Function.init(getObjectValue(self.id, "close"));
        defer func.free();

        const args = Array.new();
        defer args.free();

        args.pushNum(u16, code);

        if (reason) |r| {
            const reasonStr = String.new(r);
            defer reasonStr.free();
            args.push(&reasonStr);
        }

        _ = func.callArgs(&args);
    }

    // ========================================================================
    // Hibernation API (for Durable Objects)
    // ========================================================================

    /// Serialize attachment data into the WebSocket for hibernation.
    ///
    /// When using WebSocket hibernation with Durable Objects, you can attach
    /// arbitrary data to a WebSocket that will be preserved across hibernation.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const userData = Object.new();
    /// defer userData.free();
    /// userData.setText("userId", "user123");
    /// userData.setNum("connectedAt", u64, timestamp);
    ///
    /// ws.serializeAttachment(&userData);
    /// ```
    pub fn serializeAttachment(self: *const WebSocket, value: *const Object) void {
        const func = Function.init(getObjectValue(self.id, "serializeAttachment"));
        defer func.free();
        _ = func.callArgsID(value.id);
    }

    /// Deserialize attachment data from a hibernated WebSocket.
    ///
    /// Retrieves the data that was previously attached via `serializeAttachment`.
    /// Returns null if no attachment exists.
    ///
    /// ## Example
    ///
    /// ```zig
    /// if (ws.deserializeAttachment()) |attachment| {
    ///     defer attachment.free();
    ///     const userId = attachment.get("userId");
    ///     // Use the restored data...
    /// }
    /// ```
    pub fn deserializeAttachment(self: *const WebSocket) ?Object {
        const func = Function.init(getObjectValue(self.id, "deserializeAttachment"));
        defer func.free();
        const result = func.call();
        if (result <= DefaultValueSize) return null;
        return Object.init(result);
    }

    /// Get the CF-specific metadata for this WebSocket.
    ///
    /// Returns Cloudflare-specific information about the WebSocket connection.
    pub fn cf(self: *const WebSocket) ?Object {
        const cfPtr = getObjectValue(self.id, "cf");
        if (cfPtr <= DefaultValueSize) return null;
        return Object.init(cfPtr);
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1903

/// A pair of connected WebSockets.
///
/// `WebSocketPair` creates two WebSocket objects that are connected to each other:
/// - `client`: The WebSocket to return to the client in the Response.
/// - `server`: The WebSocket that the Worker uses to send/receive messages.
///
/// This is the standard pattern for handling WebSocket upgrade requests in
/// Cloudflare Workers.
///
/// ## Example
///
/// ```zig
/// fn handleUpgrade(ctx: *FetchContext) void {
///     // Create the pair
///     const pair = WebSocketPair.new();
///     defer pair.free();
///
///     // Get server WebSocket and accept the connection
///     var server = pair.server();
///     defer server.free();
///     server.accept();
///
///     // Send initial message
///     server.sendText("{\"type\":\"connected\"}");
///
///     // Get client WebSocket for the response
///     const client = pair.client();
///     defer client.free();
///
///     // Create and return the upgrade response
///     const response = Response.webSocket(&client);
///     defer response.free();
///     ctx.send(&response);
/// }
/// ```
///
/// ## Configuration
///
/// No special configuration is required. WebSocket upgrade requests are
/// automatically detected by Cloudflare.
pub const WebSocketPair = struct {
    id: u32,

    pub fn init(ptr: u32) WebSocketPair {
        return WebSocketPair{ .id = ptr };
    }

    /// Create a new WebSocket pair.
    ///
    /// Returns a `WebSocketPair` containing two connected WebSockets.
    /// Use `client()` to get the WebSocket to return in the Response,
    /// and `server()` to get the WebSocket for sending/receiving messages.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const pair = WebSocketPair.new();
    /// defer pair.free();
    ///
    /// var server = pair.server();
    /// defer server.free();
    /// server.accept();
    ///
    /// const client = pair.client();
    /// defer client.free();
    /// // Use client in Response.webSocket()
    /// ```
    pub fn new() WebSocketPair {
        const jsPtr = jsCreateClass(Classes.WebSocketPair.toInt(), Undefined);
        return WebSocketPair{ .id = jsPtr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const WebSocketPair) void {
        jsFree(self.id);
    }

    /// Get the client-side WebSocket.
    ///
    /// This WebSocket should be passed to `Response.webSocket()` and returned
    /// to the client. The client will use this end of the connection.
    ///
    /// Remember to call `free()` on the returned WebSocket.
    pub fn client(self: *const WebSocketPair) WebSocket {
        // WebSocketPair is an array with [client, server] or object with 0/1 keys
        const clientPtr = getObjectValue(self.id, "0");
        return WebSocket.init(clientPtr);
    }

    /// Get the server-side WebSocket.
    ///
    /// This WebSocket is used by the Worker to send and receive messages.
    /// You must call `accept()` on this WebSocket before sending messages.
    ///
    /// Remember to call `free()` on the returned WebSocket.
    pub fn server(self: *const WebSocketPair) WebSocket {
        // WebSocketPair is an array with [client, server] or object with 0/1 keys
        const serverPtr = getObjectValue(self.id, "1");
        return WebSocket.init(serverPtr);
    }
};

// ============================================================================
// WebSocket Connect (Outbound Connections)
// ============================================================================

/// Connect to an external WebSocket server.
///
/// Establishes an outbound WebSocket connection by sending an HTTP request
/// with the `Upgrade: websocket` header. The server must respond with a
/// 101 Switching Protocols response.
///
/// ## Parameters
///
/// - `url`: The WebSocket URL to connect to. Can use `ws://` or `wss://` scheme,
///          which will be converted to `http://` or `https://` respectively.
///
/// ## Returns
///
/// A connected `WebSocket` on success, or `null` if the connection failed.
///
/// ## Example
///
/// ```zig
/// const ws = WebSocket.connect("wss://echo.websocket.org") orelse {
///     ctx.throw(502, "Failed to connect to WebSocket server");
///     return;
/// };
/// defer ws.free();
///
/// ws.accept();
/// ws.sendText("Hello, server!");
/// ```
pub fn connect(url: []const u8) ?WebSocket {
    return connectWithProtocols(url, null);
}

/// Connect to an external WebSocket server with subprotocol negotiation.
///
/// ## Parameters
///
/// - `url`: The WebSocket URL to connect to.
/// - `protocols`: Optional array of subprotocols to negotiate.
///
/// ## Example
///
/// ```zig
/// const protocols = [_][]const u8{ "graphql-ws", "subscriptions-transport-ws" };
/// const ws = WebSocket.connectWithProtocols("wss://api.example.com/graphql", &protocols) orelse {
///     ctx.throw(502, "Failed to connect");
///     return;
/// };
/// defer ws.free();
/// ```
pub fn connectWithProtocols(url: []const u8, protocols: ?[]const []const u8) ?WebSocket {
    // Convert ws:// to http:// and wss:// to https://
    var httpUrl: []const u8 = url;
    var urlBuffer: [2048]u8 = undefined;

    if (std.mem.startsWith(u8, url, "ws://")) {
        const remaining = url[5..];
        const httpPrefix = "http://";
        @memcpy(urlBuffer[0..httpPrefix.len], httpPrefix);
        @memcpy(urlBuffer[httpPrefix.len .. httpPrefix.len + remaining.len], remaining);
        httpUrl = urlBuffer[0 .. httpPrefix.len + remaining.len];
    } else if (std.mem.startsWith(u8, url, "wss://")) {
        const remaining = url[6..];
        const httpsPrefix = "https://";
        @memcpy(urlBuffer[0..httpsPrefix.len], httpsPrefix);
        @memcpy(urlBuffer[httpsPrefix.len .. httpsPrefix.len + remaining.len], remaining);
        httpUrl = urlBuffer[0 .. httpsPrefix.len + remaining.len];
    }

    // Create headers with Upgrade: websocket
    const headers = Headers.new();
    defer headers.free();
    headers.setText("Upgrade", "websocket");

    // Add Sec-WebSocket-Protocol if protocols provided
    if (protocols) |protos| {
        if (protos.len > 0) {
            // Build comma-separated protocol string
            var protocolBuf: [1024]u8 = undefined;
            var pos: usize = 0;
            for (protos, 0..) |proto, i| {
                if (i > 0) {
                    protocolBuf[pos] = ',';
                    pos += 1;
                }
                @memcpy(protocolBuf[pos .. pos + proto.len], proto);
                pos += proto.len;
            }
            headers.setText("Sec-WebSocket-Protocol", protocolBuf[0..pos]);
        }
    }

    // Perform fetch with upgrade headers
    const response = fetch_api.fetch(.{ .text = httpUrl }, .{
        .requestInit = .{
            .headers = headers,
        },
    });
    defer response.free();

    // Get WebSocket from response
    return response.webSocket();
}

// ============================================================================
// WebSocket Events
// ============================================================================

/// Incoming WebSocket message type.
///
/// Used to distinguish between text and binary messages received
/// from a WebSocket connection.
pub const WebSocketIncomingMessage = union(enum) {
    /// A text message (UTF-8 string).
    text: []const u8,
    /// A binary message (raw bytes).
    binary: []const u8,
};

/// A WebSocket message event.
///
/// Represents a message received from a WebSocket connection.
/// Use `text()` or `bytes()` to access the message data.
///
/// ## Example
///
/// ```zig
/// if (event.text()) |message| {
///     // Handle text message
/// } else if (event.bytes()) |data| {
///     // Handle binary message
/// }
/// ```
pub const MessageEvent = struct {
    id: u32,

    pub fn init(ptr: u32) MessageEvent {
        return MessageEvent{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const MessageEvent) void {
        jsFree(self.id);
    }

    /// Get the message data as a text string.
    ///
    /// Returns null if the message is not a text message.
    pub fn text(self: *const MessageEvent) ?[]const u8 {
        const dataPtr = getObjectValue(self.id, "data");
        if (dataPtr <= DefaultValueSize) return null;
        // Try to get as string - returns null if it's not a string
        return getStringFree(dataPtr);
    }

    /// Get the message data as bytes.
    ///
    /// Returns null if the message data cannot be converted to bytes.
    pub fn bytes(self: *const MessageEvent) ?[]const u8 {
        const dataPtr = getObjectValue(self.id, "data");
        if (dataPtr <= DefaultValueSize) return null;
        return ArrayBuffer.init(dataPtr).bytes();
    }

    /// Get the raw data value.
    ///
    /// Returns the underlying JavaScript data object.
    pub fn data(self: *const MessageEvent) u32 {
        return getObjectValue(self.id, "data");
    }

    /// Get the origin of the message.
    pub fn origin(self: *const MessageEvent) ?[]const u8 {
        const originPtr = getObjectValue(self.id, "origin");
        if (originPtr <= DefaultValueSize) return null;
        return getStringFree(originPtr);
    }
};

/// A WebSocket close event.
///
/// Contains information about why a WebSocket connection was closed.
///
/// ## Example
///
/// ```zig
/// const closeCode = event.code();
/// const reason = event.reason();
/// const wasClean = event.wasClean();
/// ```
pub const CloseEvent = struct {
    id: u32,

    pub fn init(ptr: u32) CloseEvent {
        return CloseEvent{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const CloseEvent) void {
        jsFree(self.id);
    }

    /// Get the close code.
    ///
    /// Returns the WebSocket close code (e.g., 1000 for normal closure).
    pub fn code(self: *const CloseEvent) u16 {
        return getObjectValueNum(self.id, "code", u16);
    }

    /// Get the close reason.
    ///
    /// Returns the reason string provided by the closing endpoint, or null.
    pub fn reason(self: *const CloseEvent) ?[]const u8 {
        const reasonPtr = getObjectValue(self.id, "reason");
        if (reasonPtr <= DefaultValueSize) return null;
        return getStringFree(reasonPtr);
    }

    /// Check if the connection was closed cleanly.
    ///
    /// Returns true if the WebSocket connection was closed cleanly
    /// (i.e., with a proper closing handshake).
    pub fn wasClean(self: *const CloseEvent) bool {
        const result = getObjectValue(self.id, "wasClean");
        return result == True;
    }
};

/// A WebSocket error event.
///
/// Represents an error that occurred on a WebSocket connection.
pub const ErrorEvent = struct {
    id: u32,

    pub fn init(ptr: u32) ErrorEvent {
        return ErrorEvent{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const ErrorEvent) void {
        jsFree(self.id);
    }

    /// Get the error message.
    pub fn message(self: *const ErrorEvent) ?[]const u8 {
        const msgPtr = getObjectValue(self.id, "message");
        if (msgPtr <= DefaultValueSize) return null;
        return getStringFree(msgPtr);
    }

    /// Get the error type.
    pub fn errorType(self: *const ErrorEvent) ?[]const u8 {
        const typePtr = getObjectValue(self.id, "type");
        if (typePtr <= DefaultValueSize) return null;
        return getStringFree(typePtr);
    }
};

/// WebSocket event union.
///
/// Represents any event that can be received from a WebSocket connection.
pub const WebSocketEvent = union(enum) {
    /// A message was received.
    message: MessageEvent,
    /// The connection was closed.
    close: CloseEvent,
    /// An error occurred.
    @"error": ErrorEvent,
};

// ============================================================================
// Tests
// ============================================================================

test "ReadyState.fromInt maps standard values" {
    const testing = std.testing;

    try testing.expectEqual(ReadyState.Connecting, ReadyState.fromInt(0));
    try testing.expectEqual(ReadyState.Open, ReadyState.fromInt(1));
    try testing.expectEqual(ReadyState.Closing, ReadyState.fromInt(2));
    try testing.expectEqual(ReadyState.Closed, ReadyState.fromInt(3));
}

test "ReadyState.fromInt defaults to Closed for invalid values" {
    const testing = std.testing;

    try testing.expectEqual(ReadyState.Closed, ReadyState.fromInt(4));
    try testing.expectEqual(ReadyState.Closed, ReadyState.fromInt(100));
    try testing.expectEqual(ReadyState.Closed, ReadyState.fromInt(65535));
}

test "ReadyState enum integer values match WebSocket spec" {
    const testing = std.testing;

    try testing.expectEqual(@as(u16, 0), @intFromEnum(ReadyState.Connecting));
    try testing.expectEqual(@as(u16, 1), @intFromEnum(ReadyState.Open));
    try testing.expectEqual(@as(u16, 2), @intFromEnum(ReadyState.Closing));
    try testing.expectEqual(@as(u16, 3), @intFromEnum(ReadyState.Closed));
}

test "CloseCode.toInt returns correct values" {
    const testing = std.testing;

    try testing.expectEqual(@as(u16, 1000), CloseCode.NormalClosure.toInt());
    try testing.expectEqual(@as(u16, 1001), CloseCode.GoingAway.toInt());
    try testing.expectEqual(@as(u16, 1002), CloseCode.ProtocolError.toInt());
    try testing.expectEqual(@as(u16, 1003), CloseCode.UnsupportedData.toInt());
    try testing.expectEqual(@as(u16, 1005), CloseCode.NoStatusReceived.toInt());
    try testing.expectEqual(@as(u16, 1006), CloseCode.AbnormalClosure.toInt());
    try testing.expectEqual(@as(u16, 1007), CloseCode.InvalidFramePayloadData.toInt());
    try testing.expectEqual(@as(u16, 1008), CloseCode.PolicyViolation.toInt());
    try testing.expectEqual(@as(u16, 1009), CloseCode.MessageTooBig.toInt());
    try testing.expectEqual(@as(u16, 1010), CloseCode.MandatoryExtension.toInt());
    try testing.expectEqual(@as(u16, 1011), CloseCode.InternalError.toInt());
    try testing.expectEqual(@as(u16, 1015), CloseCode.TLSHandshake.toInt());
}

test "CloseCode enum values match RFC 6455" {
    const testing = std.testing;

    // Standard close codes from RFC 6455
    try testing.expectEqual(@as(u16, 1000), @intFromEnum(CloseCode.NormalClosure));
    try testing.expectEqual(@as(u16, 1011), @intFromEnum(CloseCode.InternalError));
    try testing.expectEqual(@as(u16, 1015), @intFromEnum(CloseCode.TLSHandshake));
}

test "WebSocket struct has expected fields" {
    const testing = std.testing;

    // Verify WebSocket struct has id field
    try testing.expect(@hasField(WebSocket, "id"));

    // Verify WebSocket has key methods (compile-time check)
    const ws_type = WebSocket;
    try testing.expect(@hasDecl(ws_type, "init"));
    try testing.expect(@hasDecl(ws_type, "free"));
    try testing.expect(@hasDecl(ws_type, "readyState"));
    try testing.expect(@hasDecl(ws_type, "accept"));
    try testing.expect(@hasDecl(ws_type, "sendText"));
    try testing.expect(@hasDecl(ws_type, "sendBytes"));
    try testing.expect(@hasDecl(ws_type, "close"));
    try testing.expect(@hasDecl(ws_type, "serializeAttachment"));
    try testing.expect(@hasDecl(ws_type, "deserializeAttachment"));
}

test "WebSocketPair struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(WebSocketPair, "id"));

    const pair_type = WebSocketPair;
    try testing.expect(@hasDecl(pair_type, "init"));
    try testing.expect(@hasDecl(pair_type, "new"));
    try testing.expect(@hasDecl(pair_type, "free"));
    try testing.expect(@hasDecl(pair_type, "client"));
    try testing.expect(@hasDecl(pair_type, "server"));
}

test "WebSocket.init creates struct with correct id" {
    const testing = std.testing;

    const ws = WebSocket.init(42);
    try testing.expectEqual(@as(u32, 42), ws.id);

    const ws2 = WebSocket.init(0);
    try testing.expectEqual(@as(u32, 0), ws2.id);
}

test "WebSocketPair.init creates struct with correct id" {
    const testing = std.testing;

    const pair = WebSocketPair.init(123);
    try testing.expectEqual(@as(u32, 123), pair.id);
}

test "WebSocketIncomingMessage union variants" {
    const testing = std.testing;

    // Check that all expected variants exist
    try testing.expect(@hasField(WebSocketIncomingMessage, "text"));
    try testing.expect(@hasField(WebSocketIncomingMessage, "binary"));

    // Create text variant
    const textMsg: WebSocketIncomingMessage = .{ .text = "hello" };
    try testing.expect(textMsg == .text);

    // Create binary variant
    const binaryMsg: WebSocketIncomingMessage = .{ .binary = "data" };
    try testing.expect(binaryMsg == .binary);
}

test "MessageEvent struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(MessageEvent, "id"));

    const event_type = MessageEvent;
    try testing.expect(@hasDecl(event_type, "init"));
    try testing.expect(@hasDecl(event_type, "free"));
    try testing.expect(@hasDecl(event_type, "text"));
    try testing.expect(@hasDecl(event_type, "bytes"));
    try testing.expect(@hasDecl(event_type, "data"));
    try testing.expect(@hasDecl(event_type, "origin"));
}

test "MessageEvent.init creates struct with correct id" {
    const testing = std.testing;

    const event = MessageEvent.init(42);
    try testing.expectEqual(@as(u32, 42), event.id);
}

test "CloseEvent struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(CloseEvent, "id"));

    const event_type = CloseEvent;
    try testing.expect(@hasDecl(event_type, "init"));
    try testing.expect(@hasDecl(event_type, "free"));
    try testing.expect(@hasDecl(event_type, "code"));
    try testing.expect(@hasDecl(event_type, "reason"));
    try testing.expect(@hasDecl(event_type, "wasClean"));
}

test "CloseEvent.init creates struct with correct id" {
    const testing = std.testing;

    const event = CloseEvent.init(100);
    try testing.expectEqual(@as(u32, 100), event.id);
}

test "ErrorEvent struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(ErrorEvent, "id"));

    const event_type = ErrorEvent;
    try testing.expect(@hasDecl(event_type, "init"));
    try testing.expect(@hasDecl(event_type, "free"));
    try testing.expect(@hasDecl(event_type, "message"));
    try testing.expect(@hasDecl(event_type, "errorType"));
}

test "ErrorEvent.init creates struct with correct id" {
    const testing = std.testing;

    const event = ErrorEvent.init(200);
    try testing.expectEqual(@as(u32, 200), event.id);
}

test "WebSocketEvent union variants" {
    const testing = std.testing;

    // Check that all expected variants exist
    try testing.expect(@hasField(WebSocketEvent, "message"));
    try testing.expect(@hasField(WebSocketEvent, "close"));
    try testing.expect(@hasField(WebSocketEvent, "error"));
}

test "connect and connectWithProtocols functions exist" {
    const testing = std.testing;

    // Verify the module has connect functions
    try testing.expect(@TypeOf(connect) == fn ([]const u8) ?WebSocket);
    try testing.expect(@TypeOf(connectWithProtocols) == fn ([]const u8, ?[]const []const u8) ?WebSocket);
}
