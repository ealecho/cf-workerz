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
fn isStringType(comptime T: type) bool {
    return T == []const u8 or T == []u8 or
        (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .Slice and
            (@typeInfo(T).pointer.child == u8));
}

/// Check if a type is a pointer to an array of u8 (comptime string literal)
fn isComptimeString(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    const ptr_info = info.pointer;
    if (ptr_info.size != .One) return false;
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
    // Response Helpers
    // ========================================================================

    /// Send a JSON response with the given status code
    pub fn json(self: *FetchContext, body: []const u8, status: u16) void {
        const statusText = @as(StatusCode, @enumFromInt(status)).toString();

        const body_str = String.new(body);
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

    // ========================================================================
    // Tokamak-style Response Helpers (auto-detection)
    // ========================================================================

    /// Send a response with automatic type detection and 200 OK status:
    /// - void / empty struct: 204 No Content
    /// - []const u8 / string: text/plain response
    /// - error: auto-mapped to HTTP status with JSON error body
    /// - struct/other: JSON serialized
    ///
    /// Example:
    /// ```
    /// ctx.sendAuto(.{ .id = 1, .name = "Alice" });  // 200 JSON
    /// ctx.sendAuto("Hello");                         // 200 text
    /// ctx.sendAuto(error.NotFound);                  // 404 JSON error
    /// ctx.sendAuto({});                              // 204 No Content
    /// ```
    pub fn sendAuto(self: *FetchContext, value: anytype) void {
        self.sendAutoStatus(value, .Ok);
    }

    /// Send a response with automatic type detection and explicit status code.
    ///
    /// Example:
    /// ```
    /// ctx.sendAutoStatus(.{ .id = 1 }, .Created);   // 201 JSON
    /// ctx.sendAutoStatus("Created", .Created);      // 201 text
    /// ```
    pub fn sendAutoStatus(self: *FetchContext, value: anytype, status: StatusCode) void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        // Handle void type -> 204 No Content
        if (T == void) {
            self.noContent();
            return;
        }

        // Handle empty struct literal {} -> 204 No Content
        if (type_info == .@"struct" and type_info.@"struct".fields.len == 0) {
            self.noContent();
            return;
        }

        // Handle error types -> auto-map to HTTP status
        if (type_info == .error_set) {
            const error_status = getErrorStatus(value);
            const error_name = @errorName(value);
            self.sendJsonError(error_name, @intFromEnum(error_status));
            return;
        }

        // Handle error unions -> unwrap and recurse
        if (type_info == .error_union) {
            if (value) |v| {
                self.sendAutoStatus(v, status);
            } else |err| {
                self.sendAuto(err);
            }
            return;
        }

        // Handle string slices -> text response
        if (isStringType(T)) {
            self.text(value, @intFromEnum(status));
            return;
        }

        // Handle comptime string literals (*const [N]u8) -> text response
        if (isComptimeString(T)) {
            self.text(value, @intFromEnum(status));
            return;
        }

        // Handle everything else -> JSON serialize
        self.sendJsonValue(value, @intFromEnum(status));
    }

    /// Send a JSON error response: {"error": "message"}
    ///
    /// Example:
    /// ```
    /// ctx.sendJsonError("User not found", 404);
    /// ```
    pub fn sendJsonError(self: *FetchContext, message: []const u8, status: u16) void {
        self.sendJsonValue(.{ .@"error" = message }, status);
    }

    /// Serialize any Zig value to JSON and send as response.
    /// Uses a 4KB buffer for serialization.
    ///
    /// Example:
    /// ```
    /// const User = struct { id: u32, name: []const u8 };
    /// ctx.sendJsonValue(User{ .id = 1, .name = "Alice" }, 200);
    /// ctx.sendJsonValue(.{ .ok = true }, 200);  // anonymous struct
    /// ```
    pub fn sendJsonValue(self: *FetchContext, value: anytype, status: u16) void {
        const statusText = @as(StatusCode, @enumFromInt(status)).toString();

        // Use a 4KB buffer for JSON serialization
        var buf: [4096]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);

        std.json.stringify(value, .{}, fbs.writer()) catch {
            // If serialization fails, send an error response
            self.throw(500, "JSON serialization failed");
            return;
        };

        const json_bytes = fbs.getWritten();

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
