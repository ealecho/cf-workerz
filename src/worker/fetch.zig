const std = @import("std");
const allocator = std.heap.page_allocator;
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const jsResolve = common.jsResolve;
const ExecutionContext = @import("../bindings/executionContext.zig").ExecutionContext;
const Env = @import("../bindings/env.zig").Env;
const Request = @import("../bindings/request.zig").Request;
const Response = @import("../bindings/response.zig").Response;
const Headers = @import("../bindings/headers.zig").Headers;
const StatusCode = @import("../http/common.zig").StatusCode;
const Method = @import("../http/common.zig").Method;
const String = @import("../bindings/string.zig").String;
const getStringFree = @import("../bindings/string.zig").getStringFree;
const getObjectValue = @import("../bindings/object.zig").getObjectValue;
const router = @import("../router.zig");
const JsonBody = @import("json.zig").JsonBody;

/// Common HTTP errors that map to status codes
/// Use these with ctx.sendAuto(error.NotFound) for automatic status mapping
pub const HttpError = error{
    BadRequest,
    Unauthorized,
    PaymentRequired,
    Forbidden,
    NotFound,
    MethodNotAllowed,
    Conflict,
    Gone,
    UnprocessableEntity,
    TooManyRequests,
    InternalServerError,
    NotImplemented,
    BadGateway,
    ServiceUnavailable,
};

/// Map any error to an HTTP status code
pub fn getErrorStatus(err: anyerror) StatusCode {
    return switch (err) {
        error.BadRequest => .BadRequest,
        error.Unauthorized => .Unauthorized,
        error.PaymentRequired => .PaymentRequired,
        error.Forbidden => .Forbidden,
        error.NotFound => .NotFound,
        error.MethodNotAllowed => .MethodNotAllowed,
        error.Conflict => .Conflict,
        error.Gone => .Gone,
        error.UnprocessableEntity => .UnprocessableEntity,
        error.TooManyRequests => .TooManyRequests,
        error.NotImplemented => .NotImplemented,
        error.BadGateway => .BadGateway,
        error.ServiceUnavailable => .ServiceUnavailable,
        else => .InternalServerError,
    };
}

/// Check if a type is a string type (comptime or runtime)
pub fn isStringType(comptime T: type) bool {
    return T == []const u8 or T == []u8 or
        (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice and
            (@typeInfo(T).pointer.child == u8));
}

/// Check if a type is a pointer to an array of u8 (comptime string literal)
pub fn isComptimeString(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    const ptr_info = info.pointer;
    if (ptr_info.size != .one) return false;
    const child_info = @typeInfo(ptr_info.child);
    if (child_info != .array) return false;
    return child_info.array.child == u8;
}

/// Handler function type - synchronous since Zig 0.11+ removed async
/// The JS runtime handles async operations via Promises
pub const HandlerFn = *const fn (ctx: *FetchContext) void;

pub const Route = struct {
    path: []const u8,
    method: ?Method = null,
    handle: HandlerFn,
};

pub const FetchContext = struct {
    id: u32,
    req: Request,
    env: Env,
    exeContext: ExecutionContext,
    path: []const u8,
    params: router.Params = .{}, // Route parameters (populated by Router)
    responded: bool = false, // Track if response was sent (for router)

    pub fn init(id: u32) !*FetchContext {
        const ctx = try allocator.create(FetchContext);
        errdefer allocator.destroy(ctx);

        ctx.* = .{
            .id = id,
            .req = Request.init(getObjectValue(id, "req")),
            .env = Env.init(getObjectValue(id, "env")),
            .exeContext = ExecutionContext.init(getObjectValue(id, "ctx")),
            .path = getStringFree(getObjectValue(id, "path")),
        };

        return ctx;
    }

    pub fn deinit(self: *FetchContext) void {
        self.req.free();
        self.env.free();
        self.exeContext.free();
        jsFree(self.id);
        allocator.destroy(self);
    }

    pub fn throw(self: *FetchContext, status: u16, msg: []const u8) void {
        const statusText = @as(StatusCode, @enumFromInt(status)).toString();

        // body
        const body = String.new(msg);
        defer body.free();
        // response
        const res = Response.new(.{ .string = &body }, .{ .status = status, .statusText = statusText });
        defer res.free();

        self.send(&res);
    }

    pub fn send(self: *FetchContext, res: *const Response) void {
        self.responded = true;
        defer self.deinit();
        // call the resolver.
        jsResolve(self.id, res.id);
    }

    // ========================================================================
    // Request Helpers
    // ========================================================================

    /// Parse the request body as JSON and return a JsonBody helper.
    /// Returns null if the body is missing, empty, or invalid JSON.
    ///
    /// Example:
    /// ```
    /// var json = ctx.bodyJson() orelse {
    ///     ctx.json(.{ .@"error" = "Invalid JSON body" }, 400);
    ///     return;
    /// };
    /// defer json.deinit();
    ///
    /// const title = json.getString("title") orelse {
    ///     ctx.json(.{ .@"error" = "Title is required" }, 400);
    ///     return;
    /// };
    /// const description = json.getStringOr("description", "");
    /// ```
    pub fn bodyJson(self: *FetchContext) ?JsonBody {
        const body = self.req.text() orelse return null;
        return JsonBody.parse(allocator, body);
    }

    /// Shorthand for ctx.params.get(name).
    /// Equivalent to Hono's c.req.param("name").
    ///
    /// Example:
    /// ```
    /// const id = ctx.param("id") orelse {
    ///     ctx.json(.{ .@"error" = "Missing id parameter" }, 400);
    ///     return;
    /// };
    /// ```
    pub fn param(self: *FetchContext, name: []const u8) ?[]const u8 {
        return self.params.get(name);
    }

    // ========================================================================
    // Response Helpers
    // ========================================================================

    /// Send a JSON response with the given status code.
    /// Accepts any type and auto-serializes:
    /// - []const u8 / string literal: treated as raw JSON string (backward compatible)
    /// - struct: serialized to JSON
    /// - error: serialized as {"error": "ErrorName"}
    ///
    /// Example:
    /// ```
    /// ctx.json(.{ .id = 1, .name = "Alice" }, 200);  // struct -> JSON
    /// ctx.json(user, 201);                            // named struct -> JSON
    /// ctx.json("{\"raw\":true}", 200);                // raw JSON string
    /// ctx.json(error.NotFound, 404);                  // -> {"error": "NotFound"}
    /// ```
    pub fn json(self: *FetchContext, value: anytype, status: u16) void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);
        const statusText = @as(StatusCode, @enumFromInt(status)).toString();

        // Determine the JSON body bytes
        var buf: [4096]u8 = undefined;
        const json_bytes: []const u8 = blk: {
            // Handle raw string slices ([]const u8, []u8) - treat as raw JSON
            if (comptime isStringType(T)) {
                break :blk value;
            }

            // Handle comptime string literals (*const [N]u8) - treat as raw JSON
            if (comptime isComptimeString(T)) {
                break :blk value;
            }

            // Handle error types -> {"error": "ErrorName"}
            if (type_info == .error_set) {
                const error_name = @errorName(value);
                var writer: std.Io.Writer = .fixed(&buf);
                std.json.Stringify.value(.{ .@"error" = error_name }, .{}, &writer) catch {
                    self.throw(500, "JSON serialization failed");
                    return;
                };
                break :blk buf[0..writer.end];
            }

            // Handle everything else (structs, arrays, etc.) -> JSON serialize
            var writer: std.Io.Writer = .fixed(&buf);
            std.json.Stringify.value(value, .{}, &writer) catch {
                self.throw(500, "JSON serialization failed");
                return;
            };
            break :blk buf[0..writer.end];
        };

        const body_str = String.new(json_bytes);
        defer body_str.free();

        const headers = Headers.new();
        defer headers.free();
        headers.setText("Content-Type", "application/json");
        headers.setText("Access-Control-Allow-Origin", "*");

        const res = Response.new(
            .{ .string = &body_str },
            .{ .status = status, .statusText = statusText, .headers = &headers },
        );
        defer res.free();

        self.send(&res);
    }

    /// Send a plain text response with the given status code
    pub fn text(self: *FetchContext, body: []const u8, status: u16) void {
        const statusText = @as(StatusCode, @enumFromInt(status)).toString();

        const body_str = String.new(body);
        defer body_str.free();

        const headers = Headers.new();
        defer headers.free();
        headers.setText("Content-Type", "text/plain; charset=utf-8");

        const res = Response.new(
            .{ .string = &body_str },
            .{ .status = status, .statusText = statusText, .headers = &headers },
        );
        defer res.free();

        self.send(&res);
    }

    /// Send an HTML response with the given status code
    pub fn html(self: *FetchContext, body: []const u8, status: u16) void {
        const statusText = @as(StatusCode, @enumFromInt(status)).toString();

        const body_str = String.new(body);
        defer body_str.free();

        const headers = Headers.new();
        defer headers.free();
        headers.setText("Content-Type", "text/html; charset=utf-8");

        const res = Response.new(
            .{ .string = &body_str },
            .{ .status = status, .statusText = statusText, .headers = &headers },
        );
        defer res.free();

        self.send(&res);
    }

    /// Send a redirect response (302 by default)
    pub fn redirect(self: *FetchContext, url: []const u8, status: u16) void {
        const actual_status = if (status == 0) @as(u16, 302) else status;
        const statusText = @as(StatusCode, @enumFromInt(actual_status)).toString();

        const headers = Headers.new();
        defer headers.free();
        headers.setText("Location", url);

        const res = Response.new(
            .{ .none = {} },
            .{ .status = actual_status, .statusText = statusText, .headers = &headers },
        );
        defer res.free();

        self.send(&res);
    }

    /// Send a 204 No Content response
    pub fn noContent(self: *FetchContext) void {
        const res = Response.new(
            .{ .none = {} },
            .{ .status = 204, .statusText = "No Content" },
        );
        defer res.free();

        self.send(&res);
    }
};

// pub const Router = struct {
//   routes: []const Route,

//   pub fn init (comptime handles: anytype) !*Router {
//     var router = try allocator.create(Router);
//     errdefer allocator.destroy(router);

//     comptime var routes: []const Route = &[_]Route{};
//     inline for (handles) |handler| {
//       switch (@TypeOf(handler)) {
//         Route => {
//           routes = (routes ++ &[_]Route{handler});
//         },
//         else => |f_type| String.new("unsupported handler type " ++ @typeName(f_type)).throw(),
//       }
//     }

//     router.* = .{ .routes = routes };

//     return router;
//   }

//   pub fn deinit (self: *const Router) void {
//     allocator.free(self);
//   }

//   pub fn handleRequest (self: *const Router, ctx: *FetchContext) void {
//     for (self.routes) |route| {
//       if (std.mem.eql(u8, route.path, ctx.path)) {
//         return route.handle(ctx);
//       }
//     }

//     ctx.throw(500, "Route does not exist.");
//   }
// };

pub fn createRoute(method: ?Method, path: []const u8, handler: HandlerFn) Route {
    return Route{
        .path = path,
        .method = method,
        .handle = handler,
    };
}

pub fn all(path: []const u8, handler: HandlerFn) Route {
    return createRoute(null, path, handler);
}

pub fn get(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Get, path, handler);
}

pub fn head(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Head, path, handler);
}

pub fn post(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Post, path, handler);
}

pub fn put(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Put, path, handler);
}

pub fn delete(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Delete, path, handler);
}

pub fn connect(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Connect, path, handler);
}

pub fn options(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Options, path, handler);
}

pub fn trace(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Trace, path, handler);
}

pub fn patch(path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.Patch, path, handler);
}

pub fn custom(method: []const u8, path: []const u8, handler: HandlerFn) Route {
    return createRoute(Method.fromString(method), path, handler);
}

// ============================================================================
// Unit Tests
// ============================================================================

test "getErrorStatus maps common HTTP errors correctly" {
    const testing = std.testing;

    // Client errors (4xx)
    try testing.expectEqual(StatusCode.BadRequest, getErrorStatus(error.BadRequest));
    try testing.expectEqual(StatusCode.Unauthorized, getErrorStatus(error.Unauthorized));
    try testing.expectEqual(StatusCode.PaymentRequired, getErrorStatus(error.PaymentRequired));
    try testing.expectEqual(StatusCode.Forbidden, getErrorStatus(error.Forbidden));
    try testing.expectEqual(StatusCode.NotFound, getErrorStatus(error.NotFound));
    try testing.expectEqual(StatusCode.MethodNotAllowed, getErrorStatus(error.MethodNotAllowed));
    try testing.expectEqual(StatusCode.Conflict, getErrorStatus(error.Conflict));
    try testing.expectEqual(StatusCode.Gone, getErrorStatus(error.Gone));
    try testing.expectEqual(StatusCode.UnprocessableEntity, getErrorStatus(error.UnprocessableEntity));
    try testing.expectEqual(StatusCode.TooManyRequests, getErrorStatus(error.TooManyRequests));

    // Server errors (5xx)
    try testing.expectEqual(StatusCode.InternalServerError, getErrorStatus(error.InternalServerError));
    try testing.expectEqual(StatusCode.NotImplemented, getErrorStatus(error.NotImplemented));
    try testing.expectEqual(StatusCode.BadGateway, getErrorStatus(error.BadGateway));
    try testing.expectEqual(StatusCode.ServiceUnavailable, getErrorStatus(error.ServiceUnavailable));
}

test "getErrorStatus returns 500 for unknown errors" {
    const testing = std.testing;

    // Unknown errors should map to 500 Internal Server Error
    try testing.expectEqual(StatusCode.InternalServerError, getErrorStatus(error.OutOfMemory));
    try testing.expectEqual(StatusCode.InternalServerError, getErrorStatus(error.Overflow));
}

test "isStringType detects string slices" {
    const testing = std.testing;

    // Should return true for string types
    try testing.expect(isStringType([]const u8));
    try testing.expect(isStringType([]u8));

    // Should return false for non-string types
    try testing.expect(!isStringType(u8));
    try testing.expect(!isStringType(u32));
    try testing.expect(!isStringType(bool));
    try testing.expect(!isStringType([]const u32));
    try testing.expect(!isStringType(struct { x: u32 }));
}

test "isComptimeString detects string literals" {
    const testing = std.testing;

    // Should return true for comptime string literal types
    try testing.expect(isComptimeString(*const [5]u8)); // "hello"
    try testing.expect(isComptimeString(*const [0]u8)); // ""
    try testing.expect(isComptimeString(*const [13]u8)); // "Hello, World!"

    // Should return false for other types
    try testing.expect(!isComptimeString([]const u8));
    try testing.expect(!isComptimeString([]u8));
    try testing.expect(!isComptimeString(u8));
    try testing.expect(!isComptimeString(*u8));
    try testing.expect(!isComptimeString(*const u8));
}

test "StatusCode integer values" {
    const testing = std.testing;

    // Verify StatusCode enum values match HTTP status codes
    try testing.expectEqual(@as(u16, 200), @intFromEnum(StatusCode.Ok));
    try testing.expectEqual(@as(u16, 201), @intFromEnum(StatusCode.Created));
    try testing.expectEqual(@as(u16, 204), @intFromEnum(StatusCode.NoContent));
    try testing.expectEqual(@as(u16, 400), @intFromEnum(StatusCode.BadRequest));
    try testing.expectEqual(@as(u16, 401), @intFromEnum(StatusCode.Unauthorized));
    try testing.expectEqual(@as(u16, 403), @intFromEnum(StatusCode.Forbidden));
    try testing.expectEqual(@as(u16, 404), @intFromEnum(StatusCode.NotFound));
    try testing.expectEqual(@as(u16, 500), @intFromEnum(StatusCode.InternalServerError));
}

test "JSON serialization with std.json.Stringify" {
    const testing = std.testing;

    // Test struct serialization
    const User = struct { id: u32, name: []const u8 };
    const user = User{ .id = 1, .name = "Alice" };

    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try std.json.Stringify.value(user, .{}, &writer);
    const result = buf[0..writer.end];

    try testing.expectEqualStrings("{\"id\":1,\"name\":\"Alice\"}", result);
}

test "JSON serialization with anonymous struct" {
    const testing = std.testing;

    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try std.json.Stringify.value(.{ .ok = true, .count = 42 }, .{}, &writer);
    const result = buf[0..writer.end];

    try testing.expectEqualStrings("{\"ok\":true,\"count\":42}", result);
}

test "JSON serialization for error response" {
    const testing = std.testing;

    const error_name = @errorName(error.NotFound);

    var buf: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);

    try std.json.Stringify.value(.{ .@"error" = error_name }, .{}, &writer);
    const result = buf[0..writer.end];

    try testing.expectEqualStrings("{\"error\":\"NotFound\"}", result);
}

// Import json tests
test {
    _ = @import("json.zig");
}
