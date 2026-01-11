/// Service Bindings API
///
/// Service Bindings allow one Worker to call another Worker directly
/// without going through a public URL. This provides:
/// - Lower latency (no network round-trip through the Internet)
/// - Authentication (no need for API keys between Workers)
/// - Private communication (target Worker doesn't need a public route)
///
/// Configuration in wrangler.toml:
/// ```toml
/// services = [
///   { binding = "AUTH_SERVICE", service = "auth-worker" },
///   { binding = "DATA_SERVICE", service = "data-worker" }
/// ]
/// ```
///
/// Usage:
/// ```zig
/// const auth = ctx.env.service("AUTH_SERVICE") orelse {
///     ctx.throw(500, "Auth service not configured");
///     return;
/// };
/// defer auth.free();
///
/// // Create a request to send to the service
/// const req = Request.new(.{ .text = "https://internal/validate" }, .{ .none = {} });
/// defer req.free();
///
/// // Call the service - this invokes the target Worker's fetch handler
/// const response = auth.fetch(.{ .request = &req }, null);
/// defer response.free();
/// ```
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const Undefined = common.Undefined;
const DefaultValueSize = common.DefaultValueSize;
const Object = @import("../bindings/object.zig").Object;
const getObjectValue = @import("../bindings/object.zig").getObjectValue;
const Array = @import("../bindings/array.zig").Array;
const String = @import("../bindings/string.zig").String;
const AsyncFunction = @import("../bindings/function.zig").AsyncFunction;
const Request = @import("../bindings/request.zig").Request;
const RequestInfo = @import("../bindings/request.zig").RequestInfo;
const RequestOptions = @import("../bindings/request.zig").RequestOptions;
const Response = @import("../bindings/response.zig").Response;

/// Fetcher represents a Service Binding to another Worker.
///
/// A Fetcher is obtained from the environment via `env.service("BINDING_NAME")`
/// and allows calling the target Worker's fetch handler.
///
/// The Fetcher interface is a subset of the Cloudflare Workers Service Bindings API:
/// https://developers.cloudflare.com/workers/runtime-apis/bindings/service-bindings/
pub const Fetcher = struct {
    id: u32,

    /// Initialize a Fetcher from a heap pointer
    pub fn init(ptr: u32) Fetcher {
        return Fetcher{ .id = ptr };
    }

    /// Free the Fetcher object from the JS heap
    pub fn free(self: *const Fetcher) void {
        jsFree(self.id);
    }

    /// Call the target Worker's fetch handler with a Request.
    ///
    /// This is equivalent to calling `binding.fetch(request)` in JavaScript.
    /// The request is forwarded to the target Worker's fetch handler, and
    /// the response is returned.
    ///
    /// Parameters:
    /// - request: The request to send (URL string or Request object)
    /// - requestInit: Optional request options (method, headers, body, etc.)
    ///
    /// Returns:
    /// - Response from the target Worker
    ///
    /// Example:
    /// ```zig
    /// const service = ctx.env.service("BACKEND") orelse return;
    /// defer service.free();
    ///
    /// // Simple GET request
    /// const res = service.fetch(.{ .text = "https://internal/api/data" }, null);
    /// defer res.free();
    ///
    /// // POST request with body
    /// const body = String.new("{\"action\":\"update\"}");
    /// defer body.free();
    /// const headers = Headers.new();
    /// defer headers.free();
    /// headers.setText("Content-Type", "application/json");
    ///
    /// const res2 = service.fetch(
    ///     .{ .text = "https://internal/api/update" },
    ///     .{ .method = .POST, .body = .{ .string = &body }, .headers = &headers }
    /// );
    /// defer res2.free();
    /// ```
    pub fn fetch(self: *const Fetcher, request: RequestInfo, requestInit: ?RequestOptions) Response {
        // Get the fetch method from the service binding object
        const fetchFnPtr = getObjectValue(self.id, "fetch");
        if (fetchFnPtr <= DefaultValueSize) {
            // fetch method not found - this shouldn't happen for valid service bindings
            String.new("Service binding does not have a fetch method").throw();
            return Response.init(Undefined);
        }

        const fetchFn = AsyncFunction.init(fetchFnPtr);
        defer fetchFn.free();

        // Build arguments array: [request, requestInit?]
        const args = Array.new();
        defer args.free();

        // Convert request to ID and add to args
        const reqID = request.toID();
        args.pushID(reqID);
        // Note: request.free(reqID) is called by caller, not here

        // Add request init if provided
        if (requestInit) |reqInit| {
            const initID = reqInit.toID();
            args.pushID(initID);
            reqInit.free(initID);
        }

        // Call binding.fetch(request, init?) - this is async on JS side
        // The JSPI/Asyncify runtime handles the Promise resolution
        const responsePtr = fetchFn.callArgsID(args.id);

        return Response.init(responsePtr);
    }

    /// Convenience method to perform a GET request to the service
    pub fn get(self: *const Fetcher, url: []const u8) Response {
        return self.fetch(.{ .text = url }, null);
    }

    /// Convenience method to perform a POST request with a JSON body
    pub fn postJson(self: *const Fetcher, url: []const u8, json: []const u8) Response {
        const body = String.new(json);
        defer body.free();

        return self.fetch(.{ .text = url }, .{
            .method = .POST,
            .body = .{ .string = &body },
            // Note: headers would need to be set for Content-Type
            // For now, the target worker should handle any content type
        });
    }
};
