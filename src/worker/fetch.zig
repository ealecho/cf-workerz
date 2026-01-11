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
