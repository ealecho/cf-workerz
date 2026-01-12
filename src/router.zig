//! Router - Built-in routing for cf-workerz
//!
//! A simple, zero-allocation router inspired by tokamak and workers-rs.
//! Supports path parameters (`:id`), wildcards (`*path`), and route groups.
//!
//! ## Quick Start
//!
//! ```zig
//! const workers = @import("cf-workerz");
//! const Route = workers.Router;
//! const FetchContext = workers.FetchContext;
//!
//! const routes: []const Route = &.{
//!     Route.get("/", handleRoot),
//!     Route.get("/users", listUsers),
//!     Route.get("/users/:id", getUser),
//!     Route.post("/users", createUser),
//!     Route.group("/api/v1", &.{
//!         Route.get("/health", health),
//!     }),
//! };
//!
//! fn handleRoot(ctx: *FetchContext) void {
//!     ctx.json(.{ .message = "Hello from cf-workerz!" }, 200);
//! }
//!
//! fn getUser(ctx: *FetchContext) void {
//!     const id = ctx.param("id") orelse {
//!         ctx.json(.{ .err = "Missing user ID" }, 400);
//!         return;
//!     };
//!     ctx.json(.{ .id = id }, 200);
//! }
//!
//! export fn handleFetch(ctx_id: u32) void {
//!     const ctx = FetchContext.init(ctx_id) catch return;
//!     Route.dispatch(routes, ctx);
//! }
//! ```
//!
//! ## Route Patterns
//!
//! - **Static routes**: `/users`, `/api/v1/health`
//! - **Path parameters**: `/users/:id`, `/posts/:postId/comments/:commentId`
//! - **Wildcards**: `/files/*path` (matches rest of path)
//! - **Route groups**: `Route.group("/api", &.{ ... })` for common prefixes
//!
//! ## Accessing Parameters
//!
//! Use `ctx.param("name")` (shorthand) or `ctx.params.get("name")` to access
//! captured path parameters. For wildcards, use `ctx.params.wildcard()`.

const std = @import("std");
const Method = @import("http/common.zig").Method;

/// Maximum number of path parameters supported per route.
/// Routes with more than 8 parameters will have excess parameters ignored.
pub const MAX_PARAMS = 8;

/// Path parameters extracted from the URL during routing.
///
/// When a route pattern contains named parameters (`:id`) or wildcards (`*path`),
/// the matched values are stored here and accessible via `get()`, `getIndex()`,
/// or `wildcard()`.
///
/// ## Example
///
/// ```zig
/// // Route pattern: "/users/:userId/posts/:postId"
/// // Request path:  "/users/42/posts/99"
///
/// fn handler(ctx: *FetchContext) void {
///     // Access by name
///     const user_id = ctx.params.get("userId");  // "42"
///     const post_id = ctx.params.get("postId");  // "99"
///
///     // Or use the shorthand
///     const id = ctx.param("userId");  // "42"
///
///     // Access by index (order of appearance in pattern)
///     const first = ctx.params.getIndex(0);  // "42"
///     const second = ctx.params.getIndex(1); // "99"
/// }
/// ```
pub const Params = struct {
    entries: [MAX_PARAMS]Entry = undefined,
    len: u8 = 0,

    /// A single captured path parameter with its name and value.
    ///
    /// - `name`: The parameter name from the pattern (e.g., `"id"` from `:id`)
    /// - `value`: The actual value matched from the request path
    pub const Entry = struct {
        name: []const u8,
        value: []const u8,
    };

    /// Get a parameter value by name.
    ///
    /// Returns the matched value for the given parameter name, or `null`
    /// if no parameter with that name exists.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Route: "/users/:id"
    /// // Path:  "/users/123"
    ///
    /// fn getUser(ctx: *FetchContext) void {
    ///     const id = ctx.params.get("id") orelse {
    ///         ctx.throw(400, "Missing id");
    ///         return;
    ///     };
    ///     // id = "123"
    /// }
    /// ```
    pub fn get(self: *const Params, name: []const u8) ?[]const u8 {
        for (self.entries[0..self.len]) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return entry.value;
            }
        }
        return null;
    }

    /// Get a parameter value by index (order of appearance in pattern).
    ///
    /// Returns `null` if the index is out of bounds.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Route: "/users/:userId/posts/:postId"
    /// // Path:  "/users/42/posts/99"
    ///
    /// fn handler(ctx: *FetchContext) void {
    ///     const user_id = ctx.params.getIndex(0);  // "42"
    ///     const post_id = ctx.params.getIndex(1);  // "99"
    ///     const missing = ctx.params.getIndex(2);  // null
    /// }
    /// ```
    pub fn getIndex(self: *const Params, index: usize) ?[]const u8 {
        if (index >= self.len) return null;
        return self.entries[index].value;
    }

    /// Get the wildcard match (everything captured by `*` or `*name`).
    ///
    /// Wildcards capture the rest of the path from that point forward.
    /// This is a convenience method equivalent to `get("*")` for unnamed
    /// wildcards or `get("name")` for named ones like `*name`.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Route: "/files/*"
    /// // Path:  "/files/documents/report.pdf"
    ///
    /// fn serveFile(ctx: *FetchContext) void {
    ///     const path = ctx.params.wildcard() orelse "index.html";
    ///     // path = "documents/report.pdf"
    /// }
    /// ```
    pub fn wildcard(self: *const Params) ?[]const u8 {
        return self.get("*");
    }
};

/// Forward declaration for FetchContext to avoid circular imports.
const FetchContext = @import("worker/fetch.zig").FetchContext;

/// Handler function type for routes.
///
/// All route handlers receive a mutable pointer to the `FetchContext`,
/// which provides access to the request, parameters, environment bindings,
/// and response methods.
pub const HandlerFn = *const fn (ctx: *FetchContext) void;

/// Middleware function type.
///
/// Middleware functions are called before or after route handlers.
/// They receive the context and can modify it, send a response, or let
/// processing continue.
///
/// Return `true` to continue processing, `false` to stop the chain.
///
/// ## Example
///
/// ```zig
/// fn authMiddleware(ctx: *FetchContext) bool {
///     const token = ctx.header("Authorization") orelse {
///         ctx.json(.{ .err = "Unauthorized" }, 401);
///         return false; // Stop processing
///     };
///     // Validate token...
///     return true; // Continue to next middleware/handler
/// }
///
/// fn logMiddleware(ctx: *FetchContext) bool {
///     // Log request details (can't stop the chain)
///     _ = ctx;
///     return true;
/// }
/// ```
pub const MiddlewareFn = *const fn (ctx: *FetchContext) bool;

/// Maximum number of middleware functions per chain.
pub const MAX_MIDDLEWARE = 8;

/// Middleware chain for before/after hooks.
///
/// Use with `Route.dispatchWithMiddleware()` to add global middleware
/// that runs before every route handler (e.g., auth, logging, CORS).
///
/// ## Example
///
/// ```zig
/// const middleware = Middleware{
///     .before = &.{ corsMiddleware, authMiddleware, logMiddleware },
///     .after = &.{ responseLogger },
/// };
///
/// export fn handleFetch(ctx_id: u32) void {
///     const ctx = FetchContext.init(ctx_id) catch return;
///     Route.dispatchWithMiddleware(routes, ctx, middleware);
/// }
/// ```
pub const Middleware = struct {
    /// Middleware to run before the route handler.
    /// If any returns false, the chain stops and no handler runs.
    before: []const MiddlewareFn = &.{},

    /// Middleware to run after the route handler completes successfully.
    /// Only runs if the handler didn't throw/return early.
    after: []const MiddlewareFn = &.{},

    /// Run all "before" middleware.
    /// Returns true if all passed, false if any stopped the chain.
    pub fn runBefore(self: *const Middleware, ctx: *FetchContext) bool {
        for (self.before) |middleware| {
            if (!middleware(ctx)) {
                return false;
            }
            if (ctx.responded) {
                return false;
            }
        }
        return true;
    }

    /// Run all "after" middleware.
    pub fn runAfter(self: *const Middleware, ctx: *FetchContext) void {
        for (self.after) |middleware| {
            _ = middleware(ctx);
            if (ctx.responded) {
                return;
            }
        }
    }
};

/// A route definition with pattern matching support.
///
/// Routes can be created using the static constructors (`get`, `post`, etc.)
/// and dispatched using `dispatch()`. Supports path parameters, wildcards,
/// and route groups for organizing related routes under a common prefix.
///
/// ## Example
///
/// ```zig
/// const routes: []const Route = &.{
///     // Basic routes
///     Route.get("/", handleRoot),
///     Route.post("/users", createUser),
///
///     // Path parameters
///     Route.get("/users/:id", getUser),
///     Route.put("/users/:id", updateUser),
///     Route.delete("/users/:id", deleteUser),
///
///     // Wildcards (matches rest of path)
///     Route.get("/files/*path", serveFile),
///
///     // Route groups with common prefix
///     Route.group("/api/v1", &.{
///         Route.get("/health", health),
///         Route.get("/metrics", metrics),
///     }),
///
///     // Match any HTTP method
///     Route.all("/webhook", handleWebhook),
/// };
/// ```
pub const Route = struct {
    method: ?Method = null, // null = any method
    pattern: []const u8 = "/",
    handler: ?HandlerFn = null,
    children: []const Route = &.{}, // For group()
    prefix: ?[]const u8 = null, // For group()

    // ========================================================================
    // Static Route Constructors
    // ========================================================================

    /// Create a GET route.
    ///
    /// GET requests are typically used for retrieving resources without
    /// side effects.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.get("/", handleRoot),
    ///     Route.get("/users", listUsers),
    ///     Route.get("/users/:id", getUser),
    /// };
    ///
    /// fn getUser(ctx: *FetchContext) void {
    ///     const id = ctx.param("id") orelse {
    ///         ctx.json(.{ .err = "Missing id" }, 400);
    ///         return;
    ///     };
    ///     ctx.json(.{ .id = id, .name = "Alice" }, 200);
    /// }
    /// ```
    pub fn get(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Get, .pattern = pattern, .handler = handler };
    }

    /// Create a POST route.
    ///
    /// POST requests are typically used for creating new resources.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.post("/users", createUser),
    /// };
    ///
    /// fn createUser(ctx: *FetchContext) void {
    ///     var json = ctx.bodyJson() orelse {
    ///         ctx.json(.{ .err = "Invalid JSON" }, 400);
    ///         return;
    ///     };
    ///     defer json.deinit();
    ///
    ///     const name = json.getString("name") orelse {
    ///         ctx.json(.{ .err = "Name required" }, 400);
    ///         return;
    ///     };
    ///     ctx.json(.{ .created = true, .name = name }, 201);
    /// }
    /// ```
    pub fn post(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Post, .pattern = pattern, .handler = handler };
    }

    /// Create a PUT route.
    ///
    /// PUT requests are typically used for replacing/updating entire resources.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.put("/users/:id", updateUser),
    /// };
    ///
    /// fn updateUser(ctx: *FetchContext) void {
    ///     const id = ctx.param("id") orelse return;
    ///     var json = ctx.bodyJson() orelse return;
    ///     defer json.deinit();
    ///     // Update user...
    ///     ctx.json(.{ .updated = true, .id = id }, 200);
    /// }
    /// ```
    pub fn put(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Put, .pattern = pattern, .handler = handler };
    }

    /// Create a DELETE route.
    ///
    /// DELETE requests are used for removing resources.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.delete("/users/:id", deleteUser),
    /// };
    ///
    /// fn deleteUser(ctx: *FetchContext) void {
    ///     const id = ctx.param("id") orelse return;
    ///     // Delete user from database...
    ///     ctx.noContent(); // 204 No Content
    /// }
    /// ```
    pub fn delete(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Delete, .pattern = pattern, .handler = handler };
    }

    /// Create a PATCH route.
    ///
    /// PATCH requests are used for partial updates to resources.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.patch("/users/:id", patchUser),
    /// };
    ///
    /// fn patchUser(ctx: *FetchContext) void {
    ///     const id = ctx.param("id") orelse return;
    ///     var json = ctx.bodyJson() orelse return;
    ///     defer json.deinit();
    ///     // Partially update user fields...
    ///     ctx.json(.{ .patched = true, .id = id }, 200);
    /// }
    /// ```
    pub fn patch(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Patch, .pattern = pattern, .handler = handler };
    }

    /// Create a HEAD route.
    ///
    /// HEAD requests are like GET but return only headers, not the body.
    /// Useful for checking if a resource exists or getting metadata.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.head("/files/:name", checkFile),
    /// };
    ///
    /// fn checkFile(ctx: *FetchContext) void {
    ///     const name = ctx.param("name") orelse return;
    ///     // Check if file exists, set headers...
    ///     ctx.noContent();
    /// }
    /// ```
    pub fn head(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Head, .pattern = pattern, .handler = handler };
    }

    /// Create an OPTIONS route.
    ///
    /// OPTIONS requests are used for CORS preflight checks and discovering
    /// allowed methods on a resource.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.options("/api/*", handleCors),
    /// };
    ///
    /// fn handleCors(ctx: *FetchContext) void {
    ///     // Set CORS headers via JavaScript bindings...
    ///     ctx.noContent();
    /// }
    /// ```
    pub fn options(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = .Options, .pattern = pattern, .handler = handler };
    }

    /// Create a route that matches any HTTP method.
    ///
    /// Useful for webhooks, catch-all handlers, or when the same logic
    /// applies regardless of the HTTP method.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.all("/webhook", handleWebhook),
    ///     Route.all("/proxy/*path", proxyRequest),
    /// };
    ///
    /// fn handleWebhook(ctx: *FetchContext) void {
    ///     // Handle webhook regardless of GET, POST, etc.
    ///     ctx.json(.{ .received = true }, 200);
    /// }
    /// ```
    pub fn all(pattern: []const u8, handler: HandlerFn) Route {
        return .{ .method = null, .pattern = pattern, .handler = handler };
    }

    /// Create a route group with a common prefix.
    ///
    /// All child routes will have the prefix automatically prepended.
    /// Groups can be nested for deep hierarchies like `/api/v1/users/:id`.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.get("/", handleRoot),
    ///
    ///     // All routes under /api/v1
    ///     Route.group("/api/v1", &.{
    ///         Route.get("/health", health),
    ///         Route.get("/users", listUsers),
    ///         Route.post("/users", createUser),
    ///
    ///         // Nested group: /api/v1/admin/...
    ///         Route.group("/admin", &.{
    ///             Route.get("/stats", adminStats),
    ///         }),
    ///     }),
    /// };
    ///
    /// // Matches:
    /// // - GET /api/v1/health
    /// // - GET /api/v1/users
    /// // - POST /api/v1/users
    /// // - GET /api/v1/admin/stats
    /// ```
    pub fn group(prefix: []const u8, children: []const Route) Route {
        return .{ .prefix = prefix, .children = children };
    }

    // ========================================================================
    // Dispatch
    // ========================================================================

    /// Dispatch a request to the matching route.
    ///
    /// Iterates through routes in order until one matches. If no route matches,
    /// automatically returns a 404 "Not Found" response. Routes are matched by:
    ///
    /// 1. HTTP method (if specified)
    /// 2. Path pattern (static segments, parameters, wildcards)
    ///
    /// **Important**: Routes are checked in order, so place more specific routes
    /// before catch-all patterns.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const routes: []const Route = &.{
    ///     Route.get("/users/:id", getUser),  // Specific route first
    ///     Route.get("/users", listUsers),
    ///     Route.all("/*", notFound),          // Catch-all last
    /// };
    ///
    /// export fn handleFetch(ctx_id: u32) void {
    ///     const ctx = FetchContext.init(ctx_id) catch return;
    ///     Route.dispatch(routes, ctx);
    /// }
    /// ```
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

    /// Dispatch a request with middleware support.
    ///
    /// Runs "before" middleware, then the route handler, then "after" middleware.
    /// If any "before" middleware returns false, the chain stops.
    ///
    /// ## Example
    ///
    /// ```zig
    /// fn corsMiddleware(ctx: *FetchContext) bool {
    ///     // Set CORS headers (would need low-level Response access)
    ///     _ = ctx;
    ///     return true;
    /// }
    ///
    /// fn authMiddleware(ctx: *FetchContext) bool {
    ///     const token = ctx.header("Authorization") orelse {
    ///         ctx.json(.{ .err = "Unauthorized" }, 401);
    ///         return false;
    ///     };
    ///     _ = token;
    ///     return true;
    /// }
    ///
    /// const middleware = Middleware{
    ///     .before = &.{ corsMiddleware, authMiddleware },
    /// };
    ///
    /// export fn handleFetch(ctx_id: u32) void {
    ///     const ctx = FetchContext.init(ctx_id) catch return;
    ///     Route.dispatchWithMiddleware(routes, ctx, middleware);
    /// }
    /// ```
    pub fn dispatchWithMiddleware(routes: []const Route, ctx: *FetchContext, middleware: Middleware) void {
        // Run "before" middleware
        if (!middleware.runBefore(ctx)) {
            return; // Middleware stopped the chain (or sent a response)
        }

        // Dispatch to route handler
        const path = ctx.path;
        const method = ctx.req.method();
        dispatchInternalWithMiddleware(routes, ctx, path, method, middleware);
    }

    fn dispatchInternalWithMiddleware(routes: []const Route, ctx: *FetchContext, path: []const u8, method: Method, middleware: Middleware) void {
        for (routes) |route| {
            // Handle group routes with prefix
            if (route.prefix) |prefix| {
                if (std.mem.startsWith(u8, path, prefix)) {
                    const sub_path = if (path.len > prefix.len) path[prefix.len..] else "/";
                    const normalized_path = if (sub_path.len == 0 or sub_path[0] != '/') blk: {
                        break :blk "/";
                    } else sub_path;

                    dispatchInternalWithMiddleware(route.children, ctx, normalized_path, method, middleware);
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
                ctx.params = params;
                if (route.handler) |handler| {
                    handler(ctx);

                    // Run "after" middleware if handler didn't respond
                    // (or even if it did, for logging purposes)
                    if (!ctx.responded) {
                        middleware.runAfter(ctx);
                    }
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

/// Match a route pattern against a request path, extracting parameters.
///
/// This is the core matching function used internally by `Route.dispatch()`.
/// You typically don't need to call this directly, but it's exported for
/// testing and advanced use cases.
///
/// Returns a `Params` struct with extracted parameters if the pattern matches,
/// or `null` if there's no match.
///
/// ## Pattern Syntax
///
/// | Syntax | Description | Example |
/// |--------|-------------|---------|
/// | `/path` | Static segment | `/users`, `/api/v1` |
/// | `:name` | Named parameter | `:id`, `:userId` |
/// | `*` | Unnamed wildcard | `/files/*` |
/// | `*name` | Named wildcard | `/static/*filepath` |
///
/// ## Matching Rules
///
/// - **Static segments** must match exactly
/// - **Named parameters** (`:id`) match any single path segment (up to the next `/`)
/// - **Wildcards** (`*` or `*name`) match the rest of the path and must be the last segment
/// - The root pattern `/` only matches the exact path `/`
///
/// ## Examples
///
/// ```zig
/// // Static matching
/// matchPath("/users", "/users")           // matches, params.len = 0
/// matchPath("/users", "/posts")           // null (no match)
///
/// // Named parameters
/// matchPath("/users/:id", "/users/123")   // matches, params.get("id") = "123"
/// matchPath("/users/:id", "/users")       // null (missing segment)
///
/// // Multiple parameters
/// matchPath("/users/:userId/posts/:postId", "/users/42/posts/99")
/// // matches, params.get("userId") = "42", params.get("postId") = "99"
///
/// // Wildcards
/// matchPath("/files/*path", "/files/a/b/c")  // matches, params.get("path") = "a/b/c"
/// matchPath("/files/*", "/files/readme.txt") // matches, params.wildcard() = "readme.txt"
/// matchPath("/api/*", "/api")                // matches, wildcard = "" (empty)
/// ```
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
