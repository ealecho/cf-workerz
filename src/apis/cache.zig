//! Cloudflare Cache API for edge caching.
//!
//! The Cache API allows you to store and retrieve responses at the edge,
//! reducing latency and origin server load. It follows the Web Cache API
//! specification with Cloudflare-specific extensions.
//!
//! ## Quick Start
//!
//! ```zig
//! fn handleRequest(ctx: *FetchContext) void {
//!     const cache = workers.Cache.new(.{ .none = {} });
//!     defer cache.free();
//!
//!     const url = "https://cache.local/my-key";
//!
//!     // Try to get from cache
//!     if (cache.match(.{ .text = url }, .{})) |cached| {
//!         defer cached.free();
//!         const body = cached.text();
//!         ctx.text(body orelse "", 200);
//!         return;
//!     }
//!
//!     // Generate response and cache it
//!     const data = generateExpensiveData();
//!
//!     const req = workers.Request.new(.{ .text = url }, .{ .none = {} });
//!     defer req.free();
//!
//!     const headers = workers.Headers.new();
//!     defer headers.free();
//!     headers.setText("Cache-Control", "public, max-age=3600");
//!
//!     const body = workers.String.new(data);
//!     defer body.free();
//!
//!     const response = workers.Response.new(
//!         .{ .string = &body },
//!         .{ .status = 200, .statusText = "OK", .headers = &headers },
//!     );
//!     defer response.free();
//!
//!     cache.put(.{ .request = &req }, &response);
//!     ctx.text(data, 200);
//! }
//! ```

const common = @import("../bindings/common.zig");
const Undefined = common.Undefined;
const True = common.True;
const toJSBool = common.toJSBool;
const jsFree = common.jsFree;
const String = @import("../bindings/string.zig").String;
const Request = @import("../bindings/request.zig").Request;
const RequestInfo = @import("../bindings/request.zig").RequestInfo;
const Response = @import("../bindings/response.zig").Response;
const AsyncFunction = @import("../bindings/function.zig").AsyncFunction;
const Array = @import("../bindings/array.zig").Array;
const Object = @import("../bindings/object.zig").Object;
const getObjectValue = @import("../bindings/object.zig").getObjectValue;

/// External JS function to get cache - synchronous call, JS handles async
pub extern fn jsCacheGet(keyPtr: u32) u32;

/// Options for identifying a cache entry.
///
/// Use `text` for a URL string, `string` for a pre-allocated String,
/// or `none` for default cache behavior.
pub const CacheOptions = union(enum) {
    text: []const u8,
    string: *const String,
    none,

    pub fn toID(self: *const CacheOptions) u32 {
        switch (self.*) {
            .text => |t| return String.new(t).id,
            .string => |s| return s.id,
            .none => return Undefined,
        }
    }

    pub fn free(self: *const CacheOptions, id: u32) void {
        switch (self.*) {
            .text => jsFree(id),
            else => {},
        }
    }
};

/// Options for cache query operations.
///
/// ## Fields
///
/// - `ignoreMethod`: If true, matches cache entries regardless of HTTP method.
///   By default, only GET requests are matched.
pub const CacheQueryOptions = struct {
    ignoreMethod: ?bool = null,

    pub fn toObject(self: *const CacheQueryOptions) Object {
        const obj = Object.new();
        if (self.ignoreMethod != null) obj.setID("ignoreMethod", toJSBool(self.ignoreMethod.?));
        return obj;
    }
};

/// Cloudflare Cache storage interface.
///
/// Provides methods to store, retrieve, and delete cached responses.
/// Use `Cache.new()` to get a cache instance.
///
/// ## Example
///
/// ```zig
/// const cache = workers.Cache.new(.{ .none = {} });
/// defer cache.free();
///
/// // Check cache
/// if (cache.match(.{ .text = "https://cache.local/key" }, .{})) |response| {
///     defer response.free();
///     // Use cached response
/// }
///
/// // Store in cache
/// cache.put(.{ .request = &req }, &response);
///
/// // Delete from cache
/// _ = cache.delete(.{ .text = "https://cache.local/key" }, .{});
/// ```
pub const Cache = struct {
    id: u32,

    pub fn init(ptr: u32) Cache {
        return Cache{ .id = ptr };
    }

    /// Create a new Cache instance.
    ///
    /// Use `.{ .none = {} }` for the default cache, or provide a
    /// cache name as a string for a named cache.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Default cache
    /// const cache = Cache.new(.{ .none = {} });
    /// defer cache.free();
    ///
    /// // Named cache
    /// const named = Cache.new(.{ .text = "my-cache" });
    /// defer named.free();
    /// ```
    pub fn new(options: CacheOptions) Cache {
        const optsPtr = options.toID();
        defer options.free(optsPtr);
        return Cache{ .id = jsCacheGet(optsPtr) };
    }

    pub fn free(self: *const Cache) void {
        jsFree(self.id);
    }

    /// Store a response in the cache.
    ///
    /// The response will be cached according to its `Cache-Control` headers.
    /// You must set appropriate cache headers on the response.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const headers = workers.Headers.new();
    /// defer headers.free();
    /// headers.setText("Cache-Control", "public, max-age=3600");
    ///
    /// const body = workers.String.new("{\"cached\":true}");
    /// defer body.free();
    ///
    /// const response = workers.Response.new(
    ///     .{ .string = &body },
    ///     .{ .status = 200, .statusText = "OK", .headers = &headers },
    /// );
    /// defer response.free();
    ///
    /// cache.put(.{ .request = &req }, &response);
    /// ```
    pub fn put(self: *const Cache, req: RequestInfo, res: *const Response) void {
        // prep arguments
        const reqID = req.toID();
        defer req.free(reqID);
        const arr = Array.new();
        defer arr.free();
        arr.pushID(reqID);
        arr.push(res);
        // build async function
        const func = AsyncFunction{ .id = getObjectValue(self.id, "put") };
        defer func.free();
        // call async function
        _ = func.callArgsID(arr.id);
    }

    /// Retrieve a cached response.
    ///
    /// Returns the cached `Response` if found, or `null` if not in cache.
    ///
    /// ## Example
    ///
    /// ```zig
    /// if (cache.match(.{ .text = "https://cache.local/key" }, .{})) |response| {
    ///     defer response.free();
    ///     const body = response.text();
    ///     ctx.text(body orelse "", 200);
    ///     return;
    /// }
    /// // Cache miss - generate fresh response
    /// ```
    pub fn match(self: *const Cache, req: RequestInfo, options: CacheQueryOptions) ?Response {
        // prep arguments
        const reqID = req.toID();
        defer req.free(reqID);
        const opts = options.toObject();
        defer opts.free();
        const arr = Array.new();
        defer arr.free();
        arr.pushID(reqID);
        arr.push(&opts);
        // build async function
        const func = AsyncFunction{ .id = getObjectValue(self.id, "match") };
        defer func.free();
        // call async function
        const result = func.callArgsID(arr.id);
        if (result == Undefined) return null;
        return Response{ .id = result };
    }

    /// Delete a cached response.
    ///
    /// Returns `true` if the entry was deleted, `false` if it wasn't found.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const deleted = cache.delete(.{ .text = "https://cache.local/key" }, .{});
    /// if (deleted) {
    ///     ctx.json(.{ .message = "Cache entry deleted" }, 200);
    /// } else {
    ///     ctx.json(.{ .message = "Not in cache" }, 404);
    /// }
    /// ```
    pub fn delete(self: *const Cache, req: RequestInfo, options: CacheQueryOptions) bool {
        // prep arguments
        const reqID = req.toID();
        defer req.free(reqID);
        const opts = options.toObject();
        defer opts.free();
        const arr = Array.new();
        defer arr.free();
        arr.pushID(reqID);
        arr.push(&opts);
        // build async function
        const func = AsyncFunction{ .id = getObjectValue(self.id, "delete") };
        defer func.free();
        // call async function
        const result = func.callArgsID(arr.id);
        return result == True;
    }
};
