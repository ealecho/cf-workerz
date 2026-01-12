//! Durable Objects API for Cloudflare Workers.
//!
//! Durable Objects provide a strongly consistent, globally distributed
//! coordination primitive. Each Durable Object is a single-threaded,
//! stateful JavaScript object that can be accessed from any Worker.
//!
//! ## Quick Start - Accessing a Durable Object
//!
//! ```zig
//! const workers = @import("cf-workerz");
//! const FetchContext = workers.FetchContext;
//!
//! fn handleRequest(ctx: *FetchContext) void {
//!     // Get the Durable Object namespace from environment
//!     const namespace = ctx.env.durableObject("MY_DO") orelse {
//!         ctx.throw(500, "Durable Object not configured");
//!         return;
//!     };
//!     defer namespace.free();
//!
//!     // Get an ID for the DO (by name or unique)
//!     const id = namespace.idFromName("my-object-name");
//!     defer id.free();
//!
//!     // Get a stub to communicate with the DO
//!     const stub = id.getStub();
//!     defer stub.free();
//!
//!     // Make a request to the DO
//!     const response = stub.fetch(.{ .text = "https://do/endpoint" }, null);
//!     defer response.free();
//!
//!     // Forward the response
//!     ctx.send(&response);
//! }
//! ```
//!
//! ## Configuration
//!
//! Add to your `wrangler.toml`:
//!
//! ```toml
//! [[durable_objects.bindings]]
//! name = "MY_DO"
//! class_name = "MyDurableObject"
//!
//! [[migrations]]
//! tag = "v1"
//! new_classes = ["MyDurableObject"]
//! ```

const std = @import("std");
const allocator = std.heap.page_allocator;
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const Null = common.Null;
const Undefined = common.Undefined;
const True = common.True;
const False = common.False;
const DefaultValueSize = common.DefaultValueSize;
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
const Request = @import("../bindings/request.zig").Request;
const RequestInfo = @import("../bindings/request.zig").RequestInfo;
const RequestInit = @import("../bindings/request.zig").RequestInit;
const Response = @import("../bindings/response.zig").Response;
const Headers = @import("../bindings/headers.zig").Headers;
const WebSocket = @import("webSocket.zig").WebSocket;

// ============================================================================
// DurableObjectId
// ============================================================================

/// A unique identifier for a Durable Object instance.
///
/// Durable Object IDs can be created from:
/// - A name (deterministic, same name = same ID)
/// - A unique ID (random, globally unique)
/// - A string representation (for restoring from storage)
///
/// ## Example
///
/// ```zig
/// // Create from name (deterministic)
/// const id = namespace.idFromName("user:123");
/// defer id.free();
///
/// // Get the stub to communicate
/// const stub = id.getStub();
/// defer stub.free();
/// ```
pub const DurableObjectId = struct {
    id: u32,

    pub fn init(ptr: u32) DurableObjectId {
        return DurableObjectId{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const DurableObjectId) void {
        jsFree(self.id);
    }

    /// Get a stub for communicating with this Durable Object.
    ///
    /// The stub provides a `fetch()` method to send requests to the DO.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const stub = id.getStub();
    /// defer stub.free();
    ///
    /// const response = stub.fetch(.{ .text = "https://do/action" }, null);
    /// defer response.free();
    /// ```
    pub fn getStub(self: *const DurableObjectId) DurableObjectStub {
        const func = Function.init(getObjectValue(self.id, "getStub"));
        defer func.free();
        return DurableObjectStub.init(func.call());
    }

    /// Get the string representation of this ID.
    ///
    /// The returned string is a hex-encoded unique identifier that can be
    /// stored and later used with `namespace.idFromString()` to recreate
    /// the same ID.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const idString = id.toString();
    /// // Store idString in KV, D1, etc.
    /// // Later: namespace.idFromString(idString)
    /// ```
    pub fn toString(self: *const DurableObjectId) []const u8 {
        const func = Function.init(getObjectValue(self.id, "toString"));
        defer func.free();
        const resultPtr = func.call();
        return getStringFree(resultPtr);
    }

    /// Get the name used to create this ID, if applicable.
    ///
    /// Returns the name if the ID was created with `idFromName()`,
    /// or null if it was created with `newUniqueId()`.
    pub fn name(self: *const DurableObjectId) ?[]const u8 {
        const namePtr = getObjectValue(self.id, "name");
        if (namePtr <= DefaultValueSize) return null;
        return getStringFree(namePtr);
    }

    /// Check if two Durable Object IDs are equal.
    pub fn equals(self: *const DurableObjectId, other: *const DurableObjectId) bool {
        const func = Function.init(getObjectValue(self.id, "equals"));
        defer func.free();
        const result = func.callArgsID(other.id);
        return result == True;
    }
};

// ============================================================================
// DurableObjectStub
// ============================================================================

/// A client stub for communicating with a Durable Object.
///
/// The stub provides methods to send requests to the Durable Object instance.
/// Requests are automatically routed to the correct data center where the
/// DO is located.
///
/// ## Example
///
/// ```zig
/// const stub = id.getStub();
/// defer stub.free();
///
/// // Simple GET request
/// const response = stub.fetch(.{ .text = "https://do/data" }, null);
/// defer response.free();
///
/// // POST request with body
/// const body = String.new("{\"action\":\"increment\"}");
/// defer body.free();
///
/// const headers = Headers.new();
/// defer headers.free();
/// headers.setText("Content-Type", "application/json");
///
/// const postResponse = stub.fetch(.{ .text = "https://do/counter" }, .{
///     .requestInit = .{
///         .method = .Post,
///         .body = .{ .string = &body },
///         .headers = headers,
///     },
/// });
/// defer postResponse.free();
/// ```
pub const DurableObjectStub = struct {
    id: u32,

    pub fn init(ptr: u32) DurableObjectStub {
        return DurableObjectStub{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const DurableObjectStub) void {
        jsFree(self.id);
    }

    /// Get the ID of the Durable Object this stub communicates with.
    pub fn getId(self: *const DurableObjectStub) DurableObjectId {
        return DurableObjectId.init(getObjectValue(self.id, "id"));
    }

    /// Get the name of the Durable Object, if it was created from a name.
    pub fn name(self: *const DurableObjectStub) ?[]const u8 {
        const namePtr = getObjectValue(self.id, "name");
        if (namePtr <= DefaultValueSize) return null;
        return getStringFree(namePtr);
    }

    /// Fetch options for Durable Object requests.
    pub const FetchOptions = union(enum) {
        requestInit: RequestInit,
        request: *const Request,
        none,
    };

    /// Send a request to the Durable Object.
    ///
    /// This method sends an HTTP request to the Durable Object's `fetch()`
    /// handler. The URL can be any valid URL - only the path and query string
    /// are typically used by the DO.
    ///
    /// ## Parameters
    ///
    /// - `info`: The URL or Request object.
    /// - `options`: Optional request options (method, headers, body, etc.).
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Simple GET
    /// const response = stub.fetch(.{ .text = "https://do/status" }, null);
    ///
    /// // POST with JSON body
    /// const body = String.new("{\"key\":\"value\"}");
    /// defer body.free();
    /// const response = stub.fetch(.{ .text = "https://do/update" }, .{
    ///     .requestInit = .{
    ///         .method = .Post,
    ///         .body = .{ .string = &body },
    ///     },
    /// });
    /// ```
    pub fn fetch(self: *const DurableObjectStub, info: RequestInfo, options: ?FetchOptions) Response {
        const func = AsyncFunction.init(getObjectValue(self.id, "fetch"));
        defer func.free();

        const args = Array.new();
        defer args.free();

        // Add URL or Request
        switch (info) {
            .text => |url| {
                const urlStr = String.new(url);
                defer urlStr.free();
                args.push(&urlStr);
            },
            .request => |req| {
                args.push(req);
            },
        }

        // Add options if provided
        if (options) |opts| {
            switch (opts) {
                .requestInit => |reqInit| {
                    const initObj = reqInit.toObject();
                    defer initObj.free();
                    args.push(&initObj);
                },
                .request => |req| {
                    args.push(req);
                },
                .none => {},
            }
        }

        return Response.init(func.callArgs(&args));
    }

    /// Send a simple GET request to the Durable Object.
    ///
    /// Convenience method for simple GET requests without options.
    pub fn get(self: *const DurableObjectStub, url: []const u8) Response {
        return self.fetch(.{ .text = url }, null);
    }
};

// ============================================================================
// DurableObjectNamespace
// ============================================================================

/// Options for creating a unique Durable Object ID.
pub const UniqueIdOptions = struct {
    /// Jurisdiction for data locality (e.g., "eu" for European Union).
    jurisdiction: ?[]const u8 = null,
};

/// A namespace containing Durable Object instances.
///
/// The namespace is obtained from the environment and provides methods to
/// create or retrieve Durable Object IDs.
///
/// ## Example
///
/// ```zig
/// const namespace = ctx.env.durableObject("MY_DO") orelse return;
/// defer namespace.free();
///
/// // Get by name (deterministic - same name = same DO)
/// const idByName = namespace.idFromName("room:lobby");
/// defer idByName.free();
///
/// // Create a new unique ID
/// const uniqueId = namespace.newUniqueId(.{});
/// defer uniqueId.free();
///
/// // Restore from stored string
/// const restoredId = namespace.idFromString(storedIdString);
/// defer restoredId.free();
/// ```
pub const DurableObjectNamespace = struct {
    id: u32,

    pub fn init(ptr: u32) DurableObjectNamespace {
        return DurableObjectNamespace{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const DurableObjectNamespace) void {
        jsFree(self.id);
    }

    /// Get a Durable Object ID from a name.
    ///
    /// The same name always produces the same ID. This is useful for
    /// scenarios where you need to access the same DO instance across
    /// multiple requests (e.g., chat rooms, user sessions).
    ///
    /// ## Parameters
    ///
    /// - `objName`: A string name for the Durable Object.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // All requests for "room:lobby" go to the same DO instance
    /// const id = namespace.idFromName("room:lobby");
    /// defer id.free();
    /// ```
    pub fn idFromName(self: *const DurableObjectNamespace, objName: []const u8) DurableObjectId {
        const func = Function.init(getObjectValue(self.id, "idFromName"));
        defer func.free();

        const nameStr = String.new(objName);
        defer nameStr.free();

        return DurableObjectId.init(func.callArgsID(nameStr.id));
    }

    /// Get a Durable Object ID from a hex string.
    ///
    /// Use this to restore an ID that was previously obtained via
    /// `DurableObjectId.toString()`.
    ///
    /// ## Parameters
    ///
    /// - `hexId`: A hex-encoded ID string.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Restore from stored ID
    /// const id = namespace.idFromString(storedIdString);
    /// defer id.free();
    /// ```
    pub fn idFromString(self: *const DurableObjectNamespace, hexId: []const u8) DurableObjectId {
        const func = Function.init(getObjectValue(self.id, "idFromString"));
        defer func.free();

        const idStr = String.new(hexId);
        defer idStr.free();

        return DurableObjectId.init(func.callArgsID(idStr.id));
    }

    /// Create a new unique Durable Object ID.
    ///
    /// Each call creates a new, globally unique ID. Use this when you need
    /// a new DO instance that isn't tied to a specific name.
    ///
    /// ## Parameters
    ///
    /// - `options`: Optional settings like jurisdiction for data locality.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Create a new unique DO
    /// const id = namespace.newUniqueId(.{});
    /// defer id.free();
    ///
    /// // Create in EU jurisdiction
    /// const euId = namespace.newUniqueId(.{ .jurisdiction = "eu" });
    /// defer euId.free();
    /// ```
    pub fn newUniqueId(self: *const DurableObjectNamespace, options: UniqueIdOptions) DurableObjectId {
        const func = Function.init(getObjectValue(self.id, "newUniqueId"));
        defer func.free();

        if (options.jurisdiction) |jurisdiction| {
            const opts = Object.new();
            defer opts.free();
            opts.setText("jurisdiction", jurisdiction);
            return DurableObjectId.init(func.callArgsID(opts.id));
        }

        return DurableObjectId.init(func.call());
    }

    /// Get a stub directly from a name.
    ///
    /// Convenience method that combines `idFromName()` and `getStub()`.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const stub = namespace.get("room:lobby");
    /// defer stub.free();
    /// const response = stub.fetch(.{ .text = "https://do/join" }, null);
    /// ```
    pub fn get(self: *const DurableObjectNamespace, objName: []const u8) DurableObjectStub {
        const objId = self.idFromName(objName);
        defer objId.free();
        return objId.getStub();
    }

    /// Get a stub directly from a name with a location hint.
    ///
    /// Location hints help optimize latency by suggesting where the DO should run.
    /// This combines `idFromName()` and `getStubWithLocationHint()`.
    ///
    /// ## Parameters
    ///
    /// - `objName`: The name for the Durable Object.
    /// - `locationHint`: A hint for where to run the DO (e.g., "wnam", "enam", "weur").
    ///
    /// ## Example
    ///
    /// ```zig
    /// const stub = namespace.getWithLocationHint("room:lobby", "wnam");
    /// defer stub.free();
    /// ```
    pub fn getWithLocationHint(self: *const DurableObjectNamespace, objName: []const u8, locationHint: []const u8) DurableObjectStub {
        const objId = self.idFromName(objName);
        defer objId.free();
        return self.getStubForId(&objId, locationHint);
    }

    /// Get a stub for an ID with a location hint.
    ///
    /// ## Parameters
    ///
    /// - `objId`: The Durable Object ID.
    /// - `locationHint`: A hint for where to run the DO (e.g., "wnam", "enam", "weur").
    pub fn getStubForId(self: *const DurableObjectNamespace, objId: *const DurableObjectId, locationHint: []const u8) DurableObjectStub {
        const func = Function.init(getObjectValue(self.id, "get"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.pushID(objId.id);

        const opts = Object.new();
        defer opts.free();
        opts.setText("locationHint", locationHint);
        args.push(&opts);

        return DurableObjectStub.init(func.callArgs(&args));
    }
};

// ============================================================================
// DurableObjectState
// ============================================================================

/// State object passed to a Durable Object's constructor and methods.
///
/// Provides access to the DO's storage, ID, and other utilities.
/// This is primarily used when implementing a Durable Object class.
///
/// ## Example (DO Implementation Pattern)
///
/// ```zig
/// // Note: Durable Object class implementation requires TypeScript runtime support
/// // This shows the Zig-side API for interacting with state
///
/// fn handleDoFetch(state: *DurableObjectState, request: *Request) Response {
///     const storage = state.storage();
///     defer storage.free();
///
///     // Get persisted data
///     if (storage.getText("counter")) |value| {
///         // Use the value...
///     }
///
///     // Store data
///     storage.putText("counter", "42");
/// }
/// ```
pub const DurableObjectState = struct {
    id: u32,

    pub fn init(ptr: u32) DurableObjectState {
        return DurableObjectState{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const DurableObjectState) void {
        jsFree(self.id);
    }

    /// Get the ID of this Durable Object.
    pub fn getId(self: *const DurableObjectState) DurableObjectId {
        return DurableObjectId.init(getObjectValue(self.id, "id"));
    }

    /// Get the storage interface for this Durable Object.
    ///
    /// Storage provides persistent key-value storage that survives
    /// between requests and hibernation.
    pub fn storage(self: *const DurableObjectState) DurableObjectStorage {
        return DurableObjectStorage.init(getObjectValue(self.id, "storage"));
    }

    /// Block the DO from being evicted while the returned promise is pending.
    ///
    /// Use this to ensure background work completes before the DO hibernates.
    pub fn blockConcurrencyWhile(self: *const DurableObjectState, callback: *const Function) void {
        const func = Function.init(getObjectValue(self.id, "blockConcurrencyWhile"));
        defer func.free();
        _ = func.callArgsID(callback.id);
    }

    /// Accept a WebSocket connection for hibernation.
    ///
    /// When using WebSocket hibernation, call this instead of `ws.accept()`.
    /// The WebSocket will be automatically managed across hibernation cycles.
    ///
    /// ## Parameters
    ///
    /// - `ws`: The server-side WebSocket to accept.
    /// - `tags`: Optional array of string tags for the WebSocket.
    pub fn acceptWebSocket(self: *const DurableObjectState, ws: *const WebSocket, tags: ?[]const []const u8) void {
        const func = Function.init(getObjectValue(self.id, "acceptWebSocket"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(ws);

        if (tags) |t| {
            const tagsArr = Array.new();
            defer tagsArr.free();
            for (t) |tag| {
                const tagStr = String.new(tag);
                defer tagStr.free();
                tagsArr.push(&tagStr);
            }

            const opts = Object.new();
            defer opts.free();
            opts.setArray("tags", &tagsArr);
            args.push(&opts);
        }

        _ = func.callArgs(&args);
    }

    /// Get all WebSockets accepted by this DO, optionally filtered by tag.
    pub fn getWebSockets(self: *const DurableObjectState, tag: ?[]const u8) WebSocketIterator {
        const func = Function.init(getObjectValue(self.id, "getWebSockets"));
        defer func.free();

        var result: u32 = 0;
        if (tag) |t| {
            const tagStr = String.new(t);
            defer tagStr.free();
            result = func.callArgsID(tagStr.id);
        } else {
            result = func.call();
        }

        return WebSocketIterator.init(result);
    }

    /// Set an alarm to wake this DO at a specific time.
    ///
    /// The alarm will trigger the DO's `alarm()` handler at the specified time.
    ///
    /// ## Parameters
    ///
    /// - `scheduledTime`: Unix timestamp in milliseconds.
    pub fn setAlarm(self: *const DurableObjectState, scheduledTime: u64) void {
        const storage_ = self.storage();
        defer storage_.free();
        storage_.setAlarm(scheduledTime);
    }

    /// Get the currently scheduled alarm time.
    pub fn getAlarm(self: *const DurableObjectState) ?u64 {
        const storage_ = self.storage();
        defer storage_.free();
        return storage_.getAlarm();
    }

    /// Delete any scheduled alarm.
    pub fn deleteAlarm(self: *const DurableObjectState) void {
        const storage_ = self.storage();
        defer storage_.free();
        storage_.deleteAlarm();
    }

    /// Schedule a background task to run after the response is sent.
    ///
    /// Use this to extend the lifetime of the DO beyond the current request
    /// without blocking the response. The promise will be awaited before the
    /// DO is evicted.
    ///
    /// ## Parameters
    ///
    /// - `promise`: A JavaScript Promise to wait for.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Schedule background cleanup
    /// state.waitUntil(&cleanupPromise);
    /// ```
    pub fn waitUntil(self: *const DurableObjectState, promise: u32) void {
        const func = Function.init(getObjectValue(self.id, "waitUntil"));
        defer func.free();
        _ = func.callArgsID(promise);
    }

    /// Get the tags associated with a hibernating WebSocket.
    ///
    /// Returns the tags that were set when the WebSocket was accepted
    /// via `acceptWebSocket` with tags.
    ///
    /// ## Parameters
    ///
    /// - `ws`: The WebSocket to get tags for.
    ///
    /// ## Returns
    ///
    /// An array containing the string tags.
    pub fn getTags(self: *const DurableObjectState, ws: *const WebSocket) Array {
        const func = Function.init(getObjectValue(self.id, "getTags"));
        defer func.free();
        return Array.init(func.callArgsID(ws.id));
    }

    /// Set an automatic response for WebSocket pings.
    ///
    /// When a WebSocket receives a message matching the request pattern,
    /// it will automatically respond with the configured response without
    /// waking the DO from hibernation.
    ///
    /// ## Parameters
    ///
    /// - `requestResponse`: A WebSocketRequestResponsePair object.
    pub fn setWebSocketAutoResponse(self: *const DurableObjectState, requestResponse: *const Object) void {
        const func = Function.init(getObjectValue(self.id, "setWebSocketAutoResponse"));
        defer func.free();
        _ = func.callArgsID(requestResponse.id);
    }

    /// Get the current WebSocket auto-response configuration.
    ///
    /// Returns the WebSocketRequestResponsePair if one is set, or null.
    pub fn getWebSocketAutoResponse(self: *const DurableObjectState) ?Object {
        const func = Function.init(getObjectValue(self.id, "getWebSocketAutoResponse"));
        defer func.free();
        const result = func.call();
        if (result <= DefaultValueSize) return null;
        return Object.init(result);
    }

    /// Clear the WebSocket auto-response configuration.
    pub fn unsetWebSocketAutoResponse(self: *const DurableObjectState) void {
        const func = Function.init(getObjectValue(self.id, "setWebSocketAutoResponse"));
        defer func.free();
        _ = func.callArgsID(Null);
    }
};

/// Iterator over WebSockets in a Durable Object.
pub const WebSocketIterator = struct {
    arr: Array,
    pos: u32 = 0,
    len: u32,

    pub fn init(ptr: u32) WebSocketIterator {
        const arr = Array.init(ptr);
        return WebSocketIterator{
            .arr = arr,
            .len = arr.length(),
        };
    }

    pub fn free(self: *const WebSocketIterator) void {
        self.arr.free();
    }

    pub fn next(self: *WebSocketIterator) ?WebSocket {
        if (self.pos >= self.len) return null;
        const ws = WebSocket.init(self.arr.get(self.pos));
        self.pos += 1;
        return ws;
    }

    pub fn count(self: *const WebSocketIterator) u32 {
        return self.len;
    }
};

// ============================================================================
// DurableObjectStorage
// ============================================================================

/// Options for storage list operations.
pub const StorageListOptions = struct {
    /// Start listing from this key (exclusive).
    start: ?[]const u8 = null,
    /// Start listing at this key (inclusive).
    startAfter: ?[]const u8 = null,
    /// Stop listing at this key (exclusive).
    end: ?[]const u8 = null,
    /// Only list keys with this prefix.
    prefix: ?[]const u8 = null,
    /// List in reverse order.
    reverse: bool = false,
    /// Maximum number of keys to return.
    limit: ?u32 = null,

    pub fn toObject(self: *const StorageListOptions) Object {
        const obj = Object.new();

        if (self.start) |s| obj.setText("start", s);
        if (self.startAfter) |s| obj.setText("startAfter", s);
        if (self.end) |e| obj.setText("end", e);
        if (self.prefix) |p| obj.setText("prefix", p);
        if (self.reverse) obj.setBool("reverse", true);
        if (self.limit) |l| obj.setNum("limit", u32, l);

        return obj;
    }
};

/// Options for getAlarm operations.
///
/// ## Example
///
/// ```zig
/// const alarm = storage.getAlarmWithOptions(.{ .allowConcurrency = true });
/// ```
pub const GetAlarmOptions = struct {
    /// If true, allow concurrent alarm operations.
    allowConcurrency: bool = false,

    pub fn toObject(self: *const GetAlarmOptions) Object {
        const obj = Object.new();
        if (self.allowConcurrency) obj.setBool("allowConcurrency", true);
        return obj;
    }
};

/// Options for setAlarm and deleteAlarm operations.
///
/// ## Example
///
/// ```zig
/// storage.setAlarmWithOptions(scheduledTime, .{
///     .allowConcurrency = true,
///     .allowUnconfirmed = true,
/// });
/// ```
pub const SetAlarmOptions = struct {
    /// If true, allow concurrent alarm operations.
    allowConcurrency: bool = false,
    /// If true, allow setting alarm without waiting for confirmation.
    allowUnconfirmed: bool = false,

    pub fn toObject(self: *const SetAlarmOptions) Object {
        const obj = Object.new();
        if (self.allowConcurrency) obj.setBool("allowConcurrency", true);
        if (self.allowUnconfirmed) obj.setBool("allowUnconfirmed", true);
        return obj;
    }
};

/// Helper for specifying alarm times.
///
/// `ScheduledTime` provides a convenient way to specify when an alarm should trigger,
/// either as an absolute timestamp or as an offset from the current time.
///
/// ## Example
///
/// ```zig
/// // Set alarm for 1 hour from now
/// const oneHourMs: i64 = 60 * 60 * 1000;
/// storage.setAlarm(ScheduledTime.fromOffsetMs(oneHourMs).toTimestamp());
///
/// // Or with absolute timestamp
/// storage.setAlarm(ScheduledTime.fromTimestamp(1704067200000).toTimestamp());
/// ```
pub const ScheduledTime = union(enum) {
    /// Absolute timestamp in milliseconds since Unix epoch.
    timestamp: u64,
    /// Offset in milliseconds from the current time.
    offset: i64,

    /// Create a ScheduledTime from an absolute timestamp (milliseconds since epoch).
    pub fn fromTimestamp(ts: u64) ScheduledTime {
        return .{ .timestamp = ts };
    }

    /// Create a ScheduledTime from an offset in milliseconds from now.
    pub fn fromOffsetMs(offset_ms: i64) ScheduledTime {
        return .{ .offset = offset_ms };
    }

    /// Create a ScheduledTime from an offset in seconds from now.
    pub fn fromOffsetSecs(offset_secs: i64) ScheduledTime {
        return .{ .offset = offset_secs * 1000 };
    }

    /// Create a ScheduledTime from an offset in minutes from now.
    pub fn fromOffsetMins(offset_mins: i64) ScheduledTime {
        return .{ .offset = offset_mins * 60 * 1000 };
    }

    /// Create a ScheduledTime from an offset in hours from now.
    pub fn fromOffsetHours(offset_hours: i64) ScheduledTime {
        return .{ .offset = offset_hours * 60 * 60 * 1000 };
    }

    /// Convert to an absolute timestamp in milliseconds.
    ///
    /// For timestamp values, returns the value directly.
    /// For offset values, adds the offset to the current time.
    ///
    /// Note: This requires the JavaScript Date.now() to get the current time.
    pub fn toTimestamp(self: ScheduledTime) u64 {
        return switch (self) {
            .timestamp => |ts| ts,
            .offset => |offset| {
                // Get current time from JavaScript Date.now()
                const now = getCurrentTimeMs();
                if (offset < 0) {
                    const abs_offset: u64 = @intCast(-offset);
                    return if (now > abs_offset) now - abs_offset else 0;
                } else {
                    return now + @as(u64, @intCast(offset));
                }
            },
        };
    }
};

/// Get the current time in milliseconds since epoch.
/// Uses JavaScript's Date.now().
fn getCurrentTimeMs() u64 {
    const dateClass = common.jsGetClass(common.Classes.Date.toInt());
    const nowFunc = Function.init(getObjectValue(dateClass, "now"));
    defer nowFunc.free();
    const result = nowFunc.call();
    return @intFromFloat(common.jsHeapGetNum(result));
}

/// Persistent storage for a Durable Object.
///
/// Provides transactional key-value storage that persists across requests
/// and hibernation cycles. All operations are strongly consistent.
///
/// ## Example
///
/// ```zig
/// const storage = state.storage();
/// defer storage.free();
///
/// // Read
/// if (storage.getText("counter")) |value| {
///     const count = std.fmt.parseInt(i32, value, 10) catch 0;
///     // Use count...
/// }
///
/// // Write
/// storage.putText("counter", "42");
///
/// // Delete
/// storage.delete("old-key");
///
/// // List
/// var entries = storage.list(.{ .prefix = "user:" });
/// defer entries.free();
/// while (entries.next()) |entry| {
///     defer entry.free();
///     // Process entry...
/// }
/// ```
pub const DurableObjectStorage = struct {
    id: u32,

    pub fn init(ptr: u32) DurableObjectStorage {
        return DurableObjectStorage{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const DurableObjectStorage) void {
        jsFree(self.id);
    }

    // ========================================================================
    // Get Operations
    // ========================================================================

    /// Get a value as a text string.
    ///
    /// Returns null if the key doesn't exist.
    pub fn getText(self: *const DurableObjectStorage, key: []const u8) ?[]const u8 {
        const func = AsyncFunction.init(getObjectValue(self.id, "get"));
        defer func.free();

        const keyStr = String.new(key);
        defer keyStr.free();

        const result = func.callArgsID(keyStr.id);
        if (result <= DefaultValueSize) return null;
        return getStringFree(result);
    }

    /// Get a value as a JavaScript Object.
    ///
    /// Returns null if the key doesn't exist.
    pub fn getObject(self: *const DurableObjectStorage, key: []const u8) ?Object {
        const func = AsyncFunction.init(getObjectValue(self.id, "get"));
        defer func.free();

        const keyStr = String.new(key);
        defer keyStr.free();

        const result = func.callArgsID(keyStr.id);
        if (result <= DefaultValueSize) return null;
        return Object.init(result);
    }

    /// Get a value and parse it as JSON into a Zig struct.
    ///
    /// Returns null if the key doesn't exist or parsing fails.
    pub fn getJSON(self: *const DurableObjectStorage, comptime T: type, key: []const u8) ?T {
        const text = self.getText(key) orelse return null;
        defer allocator.free(text);

        const parsed = std.json.parseFromSlice(T, allocator, text, .{
            .ignore_unknown_fields = true,
        }) catch return null;
        defer parsed.deinit();
        return parsed.value;
    }

    /// Get multiple values at once.
    ///
    /// Returns a Map of key-value pairs.
    pub fn getMultiple(self: *const DurableObjectStorage, keys: []const []const u8) Object {
        const func = AsyncFunction.init(getObjectValue(self.id, "get"));
        defer func.free();

        const keysArr = Array.new();
        defer keysArr.free();

        for (keys) |key| {
            const keyStr = String.new(key);
            defer keyStr.free();
            keysArr.push(&keyStr);
        }

        return Object.init(func.callArgsID(keysArr.id));
    }

    // ========================================================================
    // Put Operations
    // ========================================================================

    /// Store a text value.
    pub fn putText(self: *const DurableObjectStorage, key: []const u8, value: []const u8) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "put"));
        defer func.free();

        const args = Array.new();
        defer args.free();

        const keyStr = String.new(key);
        defer keyStr.free();
        args.push(&keyStr);

        const valStr = String.new(value);
        defer valStr.free();
        args.push(&valStr);

        _ = func.callArgs(&args);
    }

    /// Store an object value.
    pub fn putObject(self: *const DurableObjectStorage, key: []const u8, value: *const Object) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "put"));
        defer func.free();

        const args = Array.new();
        defer args.free();

        const keyStr = String.new(key);
        defer keyStr.free();
        args.push(&keyStr);
        args.push(value);

        _ = func.callArgs(&args);
    }

    /// Store a number value.
    pub fn putNum(self: *const DurableObjectStorage, key: []const u8, comptime T: type, value: T) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "put"));
        defer func.free();

        const args = Array.new();
        defer args.free();

        const keyStr = String.new(key);
        defer keyStr.free();
        args.push(&keyStr);
        args.pushNum(T, value);

        _ = func.callArgs(&args);
    }

    /// Store binary data.
    pub fn putBytes(self: *const DurableObjectStorage, key: []const u8, data: []const u8) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "put"));
        defer func.free();

        const args = Array.new();
        defer args.free();

        const keyStr = String.new(key);
        defer keyStr.free();
        args.push(&keyStr);

        const ab = ArrayBuffer.new(data);
        defer ab.free();
        args.push(&ab);

        _ = func.callArgs(&args);
    }

    /// Store multiple key-value pairs at once.
    ///
    /// The entries object should be a Map-like structure.
    pub fn putMultiple(self: *const DurableObjectStorage, entries: *const Object) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "put"));
        defer func.free();
        _ = func.callArgsID(entries.id);
    }

    // ========================================================================
    // Delete Operations
    // ========================================================================

    /// Delete a single key.
    ///
    /// Returns true if the key existed, false otherwise.
    pub fn delete(self: *const DurableObjectStorage, key: []const u8) bool {
        const func = AsyncFunction.init(getObjectValue(self.id, "delete"));
        defer func.free();

        const keyStr = String.new(key);
        defer keyStr.free();

        const result = func.callArgsID(keyStr.id);
        return result == True;
    }

    /// Delete multiple keys at once.
    ///
    /// Returns the number of keys that were deleted.
    pub fn deleteMultiple(self: *const DurableObjectStorage, keys: []const []const u8) u32 {
        const func = AsyncFunction.init(getObjectValue(self.id, "delete"));
        defer func.free();

        const keysArr = Array.new();
        defer keysArr.free();

        for (keys) |key| {
            const keyStr = String.new(key);
            defer keyStr.free();
            keysArr.push(&keyStr);
        }

        const result = func.callArgsID(keysArr.id);
        if (result <= DefaultValueSize) return 0;
        return @intFromFloat(common.jsHeapGetNum(result));
    }

    /// Delete all keys in storage.
    pub fn deleteAll(self: *const DurableObjectStorage) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "deleteAll"));
        defer func.free();
        _ = func.call();
    }

    // ========================================================================
    // List Operations
    // ========================================================================

    /// List keys in storage.
    ///
    /// Returns a Map of key-value pairs matching the criteria.
    pub fn list(self: *const DurableObjectStorage, options: StorageListOptions) StorageListResult {
        const func = AsyncFunction.init(getObjectValue(self.id, "list"));
        defer func.free();

        const opts = options.toObject();
        defer opts.free();

        return StorageListResult.init(func.callArgsID(opts.id));
    }

    // ========================================================================
    // Alarm Operations
    // ========================================================================

    /// Get the currently scheduled alarm time.
    ///
    /// Returns the Unix timestamp in milliseconds, or null if no alarm is set.
    pub fn getAlarm(self: *const DurableObjectStorage) ?u64 {
        const func = AsyncFunction.init(getObjectValue(self.id, "getAlarm"));
        defer func.free();

        const result = func.call();
        if (result <= DefaultValueSize) return null;
        return @intFromFloat(common.jsHeapGetNum(result));
    }

    /// Set an alarm to trigger at a specific time.
    ///
    /// The alarm will invoke the DO's `alarm()` handler.
    ///
    /// ## Parameters
    ///
    /// - `scheduledTime`: Unix timestamp in milliseconds.
    pub fn setAlarm(self: *const DurableObjectStorage, scheduledTime: u64) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "setAlarm"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.pushNum(u64, scheduledTime);

        _ = func.callArgs(&args);
    }

    /// Delete any scheduled alarm.
    pub fn deleteAlarm(self: *const DurableObjectStorage) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "deleteAlarm"));
        defer func.free();
        _ = func.call();
    }

    /// Get the currently scheduled alarm time with options.
    ///
    /// Returns the Unix timestamp in milliseconds, or null if no alarm is set.
    ///
    /// ## Parameters
    ///
    /// - `options`: Options for the operation (e.g., allowConcurrency).
    pub fn getAlarmWithOptions(self: *const DurableObjectStorage, options: GetAlarmOptions) ?u64 {
        const func = AsyncFunction.init(getObjectValue(self.id, "getAlarm"));
        defer func.free();

        const opts = options.toObject();
        defer opts.free();

        const result = func.callArgsID(opts.id);
        if (result <= DefaultValueSize) return null;
        return @intFromFloat(common.jsHeapGetNum(result));
    }

    /// Set an alarm with options.
    ///
    /// ## Parameters
    ///
    /// - `scheduledTime`: Unix timestamp in milliseconds.
    /// - `options`: Options for the operation (e.g., allowConcurrency, allowUnconfirmed).
    pub fn setAlarmWithOptions(self: *const DurableObjectStorage, scheduledTime: u64, options: SetAlarmOptions) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "setAlarm"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.pushNum(u64, scheduledTime);

        const opts = options.toObject();
        defer opts.free();
        args.push(&opts);

        _ = func.callArgs(&args);
    }

    /// Delete any scheduled alarm with options.
    ///
    /// ## Parameters
    ///
    /// - `options`: Options for the operation (e.g., allowConcurrency, allowUnconfirmed).
    pub fn deleteAlarmWithOptions(self: *const DurableObjectStorage, options: SetAlarmOptions) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "deleteAlarm"));
        defer func.free();

        const opts = options.toObject();
        defer opts.free();

        _ = func.callArgsID(opts.id);
    }

    // ========================================================================
    // Transaction
    // ========================================================================

    /// Execute a transactional operation.
    ///
    /// All storage operations within the callback are executed atomically.
    /// Note: Due to WASM limitations, the callback should complete synchronously.
    pub fn transaction(self: *const DurableObjectStorage, callback: *const Function) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "transaction"));
        defer func.free();
        _ = func.callArgsID(callback.id);
    }

    /// Synchronize storage to ensure all writes are persisted.
    pub fn sync(self: *const DurableObjectStorage) void {
        const func = AsyncFunction.init(getObjectValue(self.id, "sync"));
        defer func.free();
        _ = func.call();
    }

    // ========================================================================
    // SQL Storage
    // ========================================================================

    /// Get access to SQLite-backed storage.
    ///
    /// Durable Objects can use SQLite for relational data storage.
    /// This provides SQL query capabilities in addition to key-value storage.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const sqlStorage = storage.sql();
    /// defer sqlStorage.free();
    ///
    /// var cursor = sqlStorage.exec("SELECT * FROM users WHERE id = ?", .{userId});
    /// defer cursor.free();
    ///
    /// if (cursor.one()) |row| {
    ///     defer row.free();
    ///     // Use row data
    /// }
    /// ```
    pub fn sql(self: *const DurableObjectStorage) SqlStorage {
        return SqlStorage.init(getObjectValue(self.id, "sql"));
    }
};

/// SQLite storage interface for Durable Objects.
///
/// Provides SQL query capabilities for Durable Objects with SQLite-backed storage.
/// This is an alternative to the key-value storage API for relational data.
///
/// ## Example
///
/// ```zig
/// const sqlStorage = storage.sql();
/// defer sqlStorage.free();
///
/// // Execute a query
/// var cursor = sqlStorage.exec("SELECT name, email FROM users WHERE active = ?", .{true});
/// defer cursor.free();
///
/// // Iterate over results
/// while (cursor.next()) |row| {
///     defer row.free();
///     const name = row.getText("name");
///     const email = row.getText("email");
///     // Process row...
/// }
/// ```
pub const SqlStorage = struct {
    id: u32,

    pub fn init(ptr: u32) SqlStorage {
        return SqlStorage{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const SqlStorage) void {
        jsFree(self.id);
    }

    /// Execute a SQL query and return a cursor for iterating results.
    ///
    /// Use tagged template literal style: the query string with `?` placeholders,
    /// and arguments will be bound positionally.
    ///
    /// ## Parameters
    ///
    /// - `query`: SQL query string with `?` placeholders for parameters.
    ///
    /// ## Returns
    ///
    /// A `SqlCursor` for iterating over the result rows.
    pub fn exec(self: *const SqlStorage, query: []const u8) SqlCursor {
        const func = Function.init(getObjectValue(self.id, "exec"));
        defer func.free();

        const queryStr = String.new(query);
        defer queryStr.free();

        return SqlCursor.init(func.callArgsID(queryStr.id));
    }

    /// Execute a SQL query with bound parameters.
    ///
    /// ## Parameters
    ///
    /// - `query`: SQL query string with `?` placeholders.
    /// - `params`: Array of parameter values to bind.
    pub fn execWithParams(self: *const SqlStorage, query: []const u8, params: *const Array) SqlCursor {
        const func = Function.init(getObjectValue(self.id, "exec"));
        defer func.free();

        const args = Array.new();
        defer args.free();

        const queryStr = String.new(query);
        defer queryStr.free();
        args.push(&queryStr);

        // Add each param
        args.pushID(params.id);

        return SqlCursor.init(func.callArgs(&args));
    }

    /// Get the database size in bytes.
    pub fn databaseSize(self: *const SqlStorage) u64 {
        const sizePtr = getObjectValue(self.id, "databaseSize");
        if (sizePtr <= DefaultValueSize) return 0;
        return @intFromFloat(common.jsHeapGetNum(sizePtr));
    }
};

/// Cursor for iterating over SQL query results.
///
/// The cursor provides methods to iterate row-by-row or retrieve all results at once.
pub const SqlCursor = struct {
    id: u32,
    iterator: ?Object = null,

    pub fn init(ptr: u32) SqlCursor {
        return SqlCursor{ .id = ptr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *SqlCursor) void {
        if (self.iterator) |iter| {
            iter.free();
        }
        jsFree(self.id);
    }

    /// Get the next row from the cursor.
    ///
    /// Returns null when there are no more rows.
    pub fn next(self: *SqlCursor) ?Object {
        // The cursor itself is iterable, so we call next() on the iterator
        if (self.iterator == null) {
            // Get the iterator
            const iterFunc = Function.init(getObjectValue(self.id, "raw"));
            defer iterFunc.free();
            self.iterator = Object.init(iterFunc.call());
        }

        if (self.iterator) |iter| {
            const nextFunc = Function.init(getObjectValue(iter.id, "next"));
            defer nextFunc.free();
            const result = Object.init(nextFunc.call());
            defer result.free();

            // Check if done
            const done = getObjectValue(result.id, "done");
            if (done == True) return null;

            // Return the value
            const valuePtr = getObjectValue(result.id, "value");
            if (valuePtr <= DefaultValueSize) return null;
            return Object.init(valuePtr);
        }

        return null;
    }

    /// Get the first row only.
    ///
    /// Useful for queries that should return exactly one row.
    pub fn one(self: *const SqlCursor) ?Object {
        const func = Function.init(getObjectValue(self.id, "one"));
        defer func.free();
        const result = func.call();
        if (result <= DefaultValueSize) return null;
        return Object.init(result);
    }

    /// Convert all results to an array.
    ///
    /// Be careful with large result sets as this loads all rows into memory.
    pub fn toArray(self: *const SqlCursor) Array {
        const func = Function.init(getObjectValue(self.id, "toArray"));
        defer func.free();
        return Array.init(func.call());
    }

    /// Get the column names from the result.
    pub fn columnNames(self: *const SqlCursor) Array {
        return Array.init(getObjectValue(self.id, "columnNames"));
    }

    /// Get the number of rows changed by the query.
    ///
    /// For INSERT, UPDATE, DELETE queries.
    pub fn rowsWritten(self: *const SqlCursor) u64 {
        const ptr = getObjectValue(self.id, "rowsWritten");
        if (ptr <= DefaultValueSize) return 0;
        return @intFromFloat(common.jsHeapGetNum(ptr));
    }

    /// Get the number of rows read by the query.
    pub fn rowsRead(self: *const SqlCursor) u64 {
        const ptr = getObjectValue(self.id, "rowsRead");
        if (ptr <= DefaultValueSize) return 0;
        return @intFromFloat(common.jsHeapGetNum(ptr));
    }
};

/// Result from a storage list operation.
pub const StorageListResult = struct {
    id: u32,

    pub fn init(ptr: u32) StorageListResult {
        return StorageListResult{ .id = ptr };
    }

    pub fn free(self: *const StorageListResult) void {
        jsFree(self.id);
    }

    /// Get entries from the Map result.
    pub fn entries(self: *const StorageListResult) Object.ListEntries {
        return Object.init(self.id).entries();
    }

    /// Get the number of entries.
    pub fn size(self: *const StorageListResult) u32 {
        return getObjectValueNum(self.id, "size", u32);
    }
};

// ============================================================================
// Legacy DurableObject (for backwards compatibility)
// ============================================================================

/// Legacy stub struct for backwards compatibility.
/// Use DurableObjectNamespace, DurableObjectId, etc. for new code.
pub const DurableObject = struct {
    id: u32,

    pub fn init(ptr: u32) DurableObject {
        return DurableObject{ .id = ptr };
    }

    pub fn free(self: *const DurableObject) void {
        jsFree(self.id);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "DurableObjectId struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(DurableObjectId, "id"));

    const id_type = DurableObjectId;
    try testing.expect(@hasDecl(id_type, "init"));
    try testing.expect(@hasDecl(id_type, "free"));
    try testing.expect(@hasDecl(id_type, "getStub"));
    try testing.expect(@hasDecl(id_type, "toString"));
    try testing.expect(@hasDecl(id_type, "name"));
    try testing.expect(@hasDecl(id_type, "equals"));
}

test "DurableObjectId.init creates struct with correct id" {
    const testing = std.testing;

    const doId = DurableObjectId.init(42);
    try testing.expectEqual(@as(u32, 42), doId.id);

    const doId2 = DurableObjectId.init(0);
    try testing.expectEqual(@as(u32, 0), doId2.id);
}

test "DurableObjectStub struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(DurableObjectStub, "id"));

    const stub_type = DurableObjectStub;
    try testing.expect(@hasDecl(stub_type, "init"));
    try testing.expect(@hasDecl(stub_type, "free"));
    try testing.expect(@hasDecl(stub_type, "getId"));
    try testing.expect(@hasDecl(stub_type, "name"));
    try testing.expect(@hasDecl(stub_type, "fetch"));
    try testing.expect(@hasDecl(stub_type, "get"));
    try testing.expect(@hasDecl(stub_type, "FetchOptions"));
}

test "DurableObjectStub.init creates struct with correct id" {
    const testing = std.testing;

    const stub = DurableObjectStub.init(123);
    try testing.expectEqual(@as(u32, 123), stub.id);
}

test "DurableObjectNamespace struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(DurableObjectNamespace, "id"));

    const ns_type = DurableObjectNamespace;
    try testing.expect(@hasDecl(ns_type, "init"));
    try testing.expect(@hasDecl(ns_type, "free"));
    try testing.expect(@hasDecl(ns_type, "idFromName"));
    try testing.expect(@hasDecl(ns_type, "idFromString"));
    try testing.expect(@hasDecl(ns_type, "newUniqueId"));
    try testing.expect(@hasDecl(ns_type, "get"));
}

test "DurableObjectNamespace.init creates struct with correct id" {
    const testing = std.testing;

    const ns = DurableObjectNamespace.init(456);
    try testing.expectEqual(@as(u32, 456), ns.id);
}

test "UniqueIdOptions default values" {
    const testing = std.testing;

    const opts = UniqueIdOptions{};
    try testing.expectEqual(@as(?[]const u8, null), opts.jurisdiction);
}

test "UniqueIdOptions with jurisdiction" {
    const testing = std.testing;

    const opts = UniqueIdOptions{ .jurisdiction = "eu" };
    try testing.expect(opts.jurisdiction != null);
    try testing.expectEqualStrings("eu", opts.jurisdiction.?);
}

test "DurableObjectState struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(DurableObjectState, "id"));

    const state_type = DurableObjectState;
    try testing.expect(@hasDecl(state_type, "init"));
    try testing.expect(@hasDecl(state_type, "free"));
    try testing.expect(@hasDecl(state_type, "getId"));
    try testing.expect(@hasDecl(state_type, "storage"));
    try testing.expect(@hasDecl(state_type, "acceptWebSocket"));
    try testing.expect(@hasDecl(state_type, "getWebSockets"));
    try testing.expect(@hasDecl(state_type, "setAlarm"));
    try testing.expect(@hasDecl(state_type, "getAlarm"));
    try testing.expect(@hasDecl(state_type, "deleteAlarm"));
    try testing.expect(@hasDecl(state_type, "blockConcurrencyWhile"));
}

test "DurableObjectState.init creates struct with correct id" {
    const testing = std.testing;

    const state = DurableObjectState.init(789);
    try testing.expectEqual(@as(u32, 789), state.id);
}

test "DurableObjectStorage struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(DurableObjectStorage, "id"));

    const storage_type = DurableObjectStorage;
    // Get operations
    try testing.expect(@hasDecl(storage_type, "getText"));
    try testing.expect(@hasDecl(storage_type, "getObject"));
    try testing.expect(@hasDecl(storage_type, "getJSON"));
    try testing.expect(@hasDecl(storage_type, "getMultiple"));
    // Put operations
    try testing.expect(@hasDecl(storage_type, "putText"));
    try testing.expect(@hasDecl(storage_type, "putObject"));
    try testing.expect(@hasDecl(storage_type, "putNum"));
    try testing.expect(@hasDecl(storage_type, "putBytes"));
    try testing.expect(@hasDecl(storage_type, "putMultiple"));
    // Delete operations
    try testing.expect(@hasDecl(storage_type, "delete"));
    try testing.expect(@hasDecl(storage_type, "deleteMultiple"));
    try testing.expect(@hasDecl(storage_type, "deleteAll"));
    // List operations
    try testing.expect(@hasDecl(storage_type, "list"));
    // Alarm operations
    try testing.expect(@hasDecl(storage_type, "getAlarm"));
    try testing.expect(@hasDecl(storage_type, "setAlarm"));
    try testing.expect(@hasDecl(storage_type, "deleteAlarm"));
    // Transaction
    try testing.expect(@hasDecl(storage_type, "transaction"));
    try testing.expect(@hasDecl(storage_type, "sync"));
}

test "DurableObjectStorage.init creates struct with correct id" {
    const testing = std.testing;

    const storage = DurableObjectStorage.init(999);
    try testing.expectEqual(@as(u32, 999), storage.id);
}

test "StorageListOptions default values" {
    const testing = std.testing;

    const opts = StorageListOptions{};
    try testing.expectEqual(@as(?[]const u8, null), opts.start);
    try testing.expectEqual(@as(?[]const u8, null), opts.startAfter);
    try testing.expectEqual(@as(?[]const u8, null), opts.end);
    try testing.expectEqual(@as(?[]const u8, null), opts.prefix);
    try testing.expectEqual(false, opts.reverse);
    try testing.expectEqual(@as(?u32, null), opts.limit);
}

test "StorageListOptions with custom values" {
    const testing = std.testing;

    const opts = StorageListOptions{
        .prefix = "user:",
        .limit = 100,
        .reverse = true,
    };
    try testing.expectEqualStrings("user:", opts.prefix.?);
    try testing.expectEqual(@as(u32, 100), opts.limit.?);
    try testing.expectEqual(true, opts.reverse);
}

test "StorageListResult struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(StorageListResult, "id"));

    const result_type = StorageListResult;
    try testing.expect(@hasDecl(result_type, "init"));
    try testing.expect(@hasDecl(result_type, "free"));
    try testing.expect(@hasDecl(result_type, "entries"));
    try testing.expect(@hasDecl(result_type, "size"));
}

test "WebSocketIterator struct has expected fields" {
    const testing = std.testing;

    try testing.expect(@hasField(WebSocketIterator, "arr"));
    try testing.expect(@hasField(WebSocketIterator, "pos"));
    try testing.expect(@hasField(WebSocketIterator, "len"));

    const iter_type = WebSocketIterator;
    try testing.expect(@hasDecl(iter_type, "init"));
    try testing.expect(@hasDecl(iter_type, "free"));
    try testing.expect(@hasDecl(iter_type, "next"));
    try testing.expect(@hasDecl(iter_type, "count"));
}

test "DurableObject legacy struct compatibility" {
    const testing = std.testing;

    try testing.expect(@hasField(DurableObject, "id"));
    try testing.expect(@hasDecl(DurableObject, "init"));
    try testing.expect(@hasDecl(DurableObject, "free"));

    const obj = DurableObject.init(555);
    try testing.expectEqual(@as(u32, 555), obj.id);
}

test "DurableObjectStub.FetchOptions union variants" {
    const testing = std.testing;

    // Verify the union has expected tags
    const FetchOptions = DurableObjectStub.FetchOptions;

    // Check that all expected variants exist
    const none_opt: FetchOptions = .none;
    try testing.expect(none_opt == .none);

    // RequestInit variant exists (can't fully construct without runtime)
    try testing.expect(@hasField(FetchOptions, "requestInit"));
    try testing.expect(@hasField(FetchOptions, "request"));
    try testing.expect(@hasField(FetchOptions, "none"));
}

test "GetAlarmOptions default values" {
    const testing = std.testing;

    const opts = GetAlarmOptions{};
    try testing.expectEqual(false, opts.allowConcurrency);
}

test "GetAlarmOptions with allowConcurrency" {
    const testing = std.testing;

    const opts = GetAlarmOptions{ .allowConcurrency = true };
    try testing.expectEqual(true, opts.allowConcurrency);
}

test "SetAlarmOptions default values" {
    const testing = std.testing;

    const opts = SetAlarmOptions{};
    try testing.expectEqual(false, opts.allowConcurrency);
    try testing.expectEqual(false, opts.allowUnconfirmed);
}

test "SetAlarmOptions with all options" {
    const testing = std.testing;

    const opts = SetAlarmOptions{
        .allowConcurrency = true,
        .allowUnconfirmed = true,
    };
    try testing.expectEqual(true, opts.allowConcurrency);
    try testing.expectEqual(true, opts.allowUnconfirmed);
}

test "ScheduledTime.fromTimestamp creates timestamp variant" {
    const testing = std.testing;

    const st = ScheduledTime.fromTimestamp(1704067200000);
    try testing.expect(st == .timestamp);
    try testing.expectEqual(@as(u64, 1704067200000), st.timestamp);
}

test "ScheduledTime.fromOffsetMs creates offset variant" {
    const testing = std.testing;

    const st = ScheduledTime.fromOffsetMs(3600000);
    try testing.expect(st == .offset);
    try testing.expectEqual(@as(i64, 3600000), st.offset);
}

test "ScheduledTime.fromOffsetSecs converts to milliseconds" {
    const testing = std.testing;

    const st = ScheduledTime.fromOffsetSecs(60);
    try testing.expect(st == .offset);
    try testing.expectEqual(@as(i64, 60000), st.offset);
}

test "ScheduledTime.fromOffsetMins converts to milliseconds" {
    const testing = std.testing;

    const st = ScheduledTime.fromOffsetMins(5);
    try testing.expect(st == .offset);
    try testing.expectEqual(@as(i64, 300000), st.offset);
}

test "ScheduledTime.fromOffsetHours converts to milliseconds" {
    const testing = std.testing;

    const st = ScheduledTime.fromOffsetHours(1);
    try testing.expect(st == .offset);
    try testing.expectEqual(@as(i64, 3600000), st.offset);
}

test "ScheduledTime.toTimestamp for timestamp returns value directly" {
    const testing = std.testing;

    const st = ScheduledTime.fromTimestamp(1704067200000);
    try testing.expectEqual(@as(u64, 1704067200000), st.toTimestamp());
}

test "DurableObjectNamespace has location hint methods" {
    const testing = std.testing;

    const ns_type = DurableObjectNamespace;
    try testing.expect(@hasDecl(ns_type, "getWithLocationHint"));
    try testing.expect(@hasDecl(ns_type, "getStubForId"));
}

test "DurableObjectState has new methods" {
    const testing = std.testing;

    const state_type = DurableObjectState;
    try testing.expect(@hasDecl(state_type, "waitUntil"));
    try testing.expect(@hasDecl(state_type, "getTags"));
    try testing.expect(@hasDecl(state_type, "setWebSocketAutoResponse"));
    try testing.expect(@hasDecl(state_type, "getWebSocketAutoResponse"));
    try testing.expect(@hasDecl(state_type, "unsetWebSocketAutoResponse"));
}

test "DurableObjectStorage has alarm options methods" {
    const testing = std.testing;

    const storage_type = DurableObjectStorage;
    try testing.expect(@hasDecl(storage_type, "getAlarmWithOptions"));
    try testing.expect(@hasDecl(storage_type, "setAlarmWithOptions"));
    try testing.expect(@hasDecl(storage_type, "deleteAlarmWithOptions"));
    try testing.expect(@hasDecl(storage_type, "sql"));
}

test "SqlStorage struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(SqlStorage, "id"));

    const sql_type = SqlStorage;
    try testing.expect(@hasDecl(sql_type, "init"));
    try testing.expect(@hasDecl(sql_type, "free"));
    try testing.expect(@hasDecl(sql_type, "exec"));
    try testing.expect(@hasDecl(sql_type, "execWithParams"));
    try testing.expect(@hasDecl(sql_type, "databaseSize"));
}

test "SqlStorage.init creates struct with correct id" {
    const testing = std.testing;

    const sql = SqlStorage.init(999);
    try testing.expectEqual(@as(u32, 999), sql.id);
}

test "SqlCursor struct has expected fields and methods" {
    const testing = std.testing;

    try testing.expect(@hasField(SqlCursor, "id"));
    try testing.expect(@hasField(SqlCursor, "iterator"));

    const cursor_type = SqlCursor;
    try testing.expect(@hasDecl(cursor_type, "init"));
    try testing.expect(@hasDecl(cursor_type, "free"));
    try testing.expect(@hasDecl(cursor_type, "next"));
    try testing.expect(@hasDecl(cursor_type, "one"));
    try testing.expect(@hasDecl(cursor_type, "toArray"));
    try testing.expect(@hasDecl(cursor_type, "columnNames"));
    try testing.expect(@hasDecl(cursor_type, "rowsWritten"));
    try testing.expect(@hasDecl(cursor_type, "rowsRead"));
}

test "SqlCursor.init creates struct with correct id" {
    const testing = std.testing;

    const cursor = SqlCursor.init(888);
    try testing.expectEqual(@as(u32, 888), cursor.id);
    try testing.expectEqual(@as(?Object, null), cursor.iterator);
}
