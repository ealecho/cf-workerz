// Router - Built-in routing for workers-zig
//
// A simple, zero-allocation router inspired by tokamak and workers-rs.
// Supports path parameters (:id), wildcards (*path), and route groups.
//
// Example usage:
//   const workers = @import("workers-zig");
//   const Route = workers.Router;
//
//   const routes: []const Route = &.{
//       Route.get("/", handleRoot),
//       Route.get("/users", handleListUsers),
//       Route.get("/users/:id", handleGetUser),
//       Route.post("/users", handleCreateUser),
//       Route.group("/api", &.{
//           Route.get("/health", handleHealth),
//       }),
//   };
//
//   fn handleGetUser(ctx: *workers.FetchContext) void {
//       const id = ctx.params.get("id") orelse {
//           ctx.throw(400, "Missing user ID");
//           return;
//       };
//       // Use id...
//   }
//
//   export fn handleFetch(ctx_id: u32) void {
//       var ctx = workers.FetchContext.init(ctx_id) catch return;
//       Route.dispatch(&routes, ctx);
//   }

const std = @import("std");
const Method = @import("http/common.zig").Method;

/// Maximum number of path parameters supported
pub const MAX_PARAMS = 8;

/// Path parameters extracted from the URL
pub const Params = struct {
    entries: [MAX_PARAMS]Entry = undefined,
    len: u8 = 0,

    pub const Entry = struct {
        name: []const u8, // Parameter name (e.g., "id" from ":id")
        value: []const u8, // Matched value from the path
    };

    /// Get parameter value by name
    pub fn get(self: *const Params, name: []const u8) ?[]const u8 {
        for (self.entries[0..self.len]) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return entry.value;
            }
        }
        return null;
    }

    /// Get parameter value by index
    pub fn getIndex(self: *const Params, index: usize) ?[]const u8 {
        if (index >= self.len) return null;
        return self.entries[index].value;
    }

    /// Get the wildcard match (everything after *)
    pub fn wildcard(self: *const Params) ?[]const u8 {
        return self.get("*");
    }
};

/// Forward declaration for FetchContext to avoid circular imports
const FetchContext = @import("worker/fetch.zig").FetchContext;

/// Handler function type for routes
pub const HandlerFn = *const fn (ctx: *FetchContext) void;

/// Route definition with pattern matching
pub const Route = struct {
    method: ?Method = null, // null = any method
    pattern: []const u8 = "/",
    handler: ?HandlerFn = null,
    children: []const Route = &.{}, // For group()
    prefix: ?[]const u8 = null, // For group()

    // ========================================================================
    // Static Route Constructors
    // ========================================================================

    /// Create a GET route
    pub fn get(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Get, .pattern = pattern, .handler = handler };
    }

    /// Create a POST route
    pub fn post(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Post, .pattern = pattern, .handler = handler };
    }

    /// Create a PUT route
    pub fn put(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Put, .pattern = pattern, .handler = handler };
    }

    /// Create a DELETE route
    pub fn delete(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Delete, .pattern = pattern, .handler = handler };
    }

    /// Create a PATCH route
    pub fn patch(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Patch, .pattern = pattern, .handler = handler };
    }

    /// Create a HEAD route
    pub fn head(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Head, .pattern = pattern, .handler = handler };
    }

    /// Create an OPTIONS route
    pub fn options(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Options, .pattern = pattern, .handler = handler };
    }

    /// Create a route that matches any HTTP method
    pub fn all(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = null, .pattern = pattern, .handler = handler };
    }

    /// Create a route group with a common prefix
    /// Child routes will have the prefix stripped before matching
    pub fn group(prefix: []const u8, children: []const Route) Route {
        return .{ .prefix = prefix, .children = children };
    }

    // ========================================================================
    // Dispatch
    // ========================================================================

    /// Dispatch a request to the matching route
    /// Tries each route in order until one matches
    pub fn dispatch(routes: []const Route, ctx: *FetchContext) void {
        const path = ctx.path;
        const method = ctx.req.method();

        dispatchInternal(routes, ctx, path, method);
    }

    fn dispatchInternal(routes: []const Route, ctx: *FetchContext, path: []const u8, method: Method) void {
        for (routes) |route| {
            // Handle group routes with prefix
            if (route.prefix) |prefix| {
                if (std.mem.startsWith(u8, path, prefix)) {
                    // Strip prefix and dispatch to children
                    const sub_path = if (path.len > prefix.len) path[prefix.len..] else "/";
                    // Ensure sub_path starts with /
                    const normalized_path = if (sub_path.len == 0 or sub_path[0] != '/') blk: {
                        break :blk "/";
                    } else sub_path;

                    dispatchInternal(route.children, ctx, normalized_path, method);
                    if (ctx.responded) return;
                }
                continue;
            }

            // Check method if specified
            if (route.method) |m| {
                if (m != method) continue;
            }

            // Match path pattern
            if (matchPath(route.pattern, path)) |params| {
                // Set params on context and call handler
                ctx.params = params;
                if (route.handler) |handler| {
                    handler(ctx);
                    return;
                }
            }
        }

        // No match found - return 404
        ctx.throw(404, "Not Found");
    }
};

// ============================================================================
// Path Matching
// ============================================================================

/// Match a pattern against a path, extracting parameters
/// Returns Params if matched, null otherwise
///
/// Pattern syntax:
///   - Static segments: /users, /api/v1
///   - Named parameters: :id, :name (matches until next /)
///   - Wildcards: *path (matches rest of path, must be last segment)
///
/// Examples:
///   "/users/:id" matches "/users/123" -> params.get("id") = "123"
///   "/files/*path" matches "/files/a/b/c" -> params.get("*") = "a/b/c"
pub fn matchPath(pattern: []const u8, path: []const u8) ?Params {
    var params = Params{};

    // Handle exact root match
    if (std.mem.eql(u8, pattern, "/") and std.mem.eql(u8, path, "/")) {
        return params;
    }

    var pattern_iter = std.mem.tokenizeScalar(u8, pattern, '/');
    var path_iter = std.mem.tokenizeScalar(u8, path, '/');

    while (true) {
        const pat_segment = pattern_iter.next();
        const path_segment = path_iter.next();

        // Both exhausted - match!
        if (pat_segment == null and path_segment == null) {
            return params;
        }

        // Pattern exhausted but path has more segments - no match
        // (unless pattern ended with wildcard, handled below)
        if (pat_segment == null and path_segment != null) {
            return null;
        }

        // Path exhausted but pattern has more segments - no match
        // (unless it's an optional wildcard)
        if (pat_segment != null and path_segment == null) {
            const pat = pat_segment.?;
            // Wildcard can match empty rest
            if (pat.len > 0 and pat[0] == '*') {
                const name = if (pat.len > 1) pat[1..] else "*";
                if (params.len < MAX_PARAMS) {
                    params.entries[params.len] = .{ .name = name, .value = "" };
                    params.len += 1;
                }
                return params;
            }
            return null;
        }

        const pat = pat_segment.?;
        const seg = path_segment.?;

        // Wildcard - match rest of path
        if (pat.len > 0 and pat[0] == '*') {
            const name = if (pat.len > 1) pat[1..] else "*";
            // Collect remaining path
            var rest_start: usize = 0;
            // Find where this segment starts in the original path
            const seg_ptr = @intFromPtr(seg.ptr);
            const path_ptr = @intFromPtr(path.ptr);
            if (seg_ptr >= path_ptr and seg_ptr < path_ptr + path.len) {
                rest_start = seg_ptr - path_ptr;
            }
            const rest = path[rest_start..];

            if (params.len < MAX_PARAMS) {
                params.entries[params.len] = .{ .name = name, .value = rest };
                params.len += 1;
            }
            return params;
        }

        // Named parameter - match any segment
        if (pat.len > 0 and pat[0] == ':') {
            const name = pat[1..];
            if (params.len < MAX_PARAMS) {
                params.entries[params.len] = .{ .name = name, .value = seg };
                params.len += 1;
            }
            continue;
        }

        // Static segment - must match exactly
        if (!std.mem.eql(u8, pat, seg)) {
            return null;
        }
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

test "Params.get returns correct value" {
    var params = Params{};
    params.entries[0] = .{ .name = "id", .value = "123" };
    params.entries[1] = .{ .name = "name", .value = "alice" };
    params.len = 2;

    try std.testing.expectEqualStrings("123", params.get("id").?);
    try std.testing.expectEqualStrings("alice", params.get("name").?);
    try std.testing.expect(params.get("missing") == null);
}

test "Params.getIndex returns correct value" {
    var params = Params{};
    params.entries[0] = .{ .name = "id", .value = "123" };
    params.entries[1] = .{ .name = "name", .value = "alice" };
    params.len = 2;

    try std.testing.expectEqualStrings("123", params.getIndex(0).?);
    try std.testing.expectEqualStrings("alice", params.getIndex(1).?);
    try std.testing.expect(params.getIndex(2) == null);
}

test "matchPath: exact root match" {
    const result = matchPath("/", "/");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u8, 0), result.?.len);
}

test "matchPath: root pattern does not match non-root" {
    try std.testing.expect(matchPath("/", "/foo") == null);
    try std.testing.expect(matchPath("/", "/foo/bar") == null);
}

test "matchPath: static segments" {
    try std.testing.expect(matchPath("/users", "/users") != null);
    try std.testing.expect(matchPath("/users", "/posts") == null);
    try std.testing.expect(matchPath("/api/v1/users", "/api/v1/users") != null);
    try std.testing.expect(matchPath("/api/v1/users", "/api/v2/users") == null);
}

test "matchPath: static does not match longer path" {
    try std.testing.expect(matchPath("/users", "/users/123") == null);
}

test "matchPath: single parameter" {
    const result = matchPath("/users/:id", "/users/123");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("123", result.?.get("id").?);
}

test "matchPath: multiple parameters" {
    const result = matchPath("/users/:userId/posts/:postId", "/users/42/posts/99");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("42", result.?.get("userId").?);
    try std.testing.expectEqualStrings("99", result.?.get("postId").?);
}

test "matchPath: parameter with static segments" {
    const result = matchPath("/api/users/:id/profile", "/api/users/abc/profile");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("abc", result.?.get("id").?);
}

test "matchPath: wildcard matches rest" {
    const result = matchPath("/files/*path", "/files/a/b/c");
    try std.testing.expect(result != null);
    const wildcard_value = result.?.get("path").?;
    try std.testing.expectEqualStrings("a/b/c", wildcard_value);
}

test "matchPath: wildcard matches single segment" {
    const result = matchPath("/files/*", "/files/readme.txt");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("readme.txt", result.?.wildcard().?);
}

test "matchPath: wildcard matches empty" {
    const result = matchPath("/api/*", "/api");
    // Pattern /api/* with path /api - wildcard matches empty
    try std.testing.expect(result != null);
}

test "matchPath: named wildcard" {
    const result = matchPath("/static/*filepath", "/static/css/style.css");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("css/style.css", result.?.get("filepath").?);
}

test "matchPath: pattern longer than path" {
    try std.testing.expect(matchPath("/users/:id/posts", "/users/123") == null);
}

test "matchPath: path longer than pattern (no wildcard)" {
    try std.testing.expect(matchPath("/users/:id", "/users/123/extra") == null);
}

test "Route.get creates correct route" {
    const handler = struct {
        fn h(_: *FetchContext) void {}
    }.h;
    const route = Route.get("/test", handler);

    try std.testing.expectEqual(Method.Get, route.method.?);
    try std.testing.expectEqualStrings("/test", route.pattern);
    try std.testing.expect(route.handler != null);
}

test "Route.group creates correct route" {
    const handler = struct {
        fn h(_: *FetchContext) void {}
    }.h;
    const children: []const Route = &.{
        Route.get("/health", handler),
    };
    const route = Route.group("/api", children);

    try std.testing.expectEqualStrings("/api", route.prefix.?);
    try std.testing.expectEqual(@as(usize, 1), route.children.len);
}
