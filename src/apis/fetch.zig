const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const Request = @import("../bindings/request.zig").Request;
const RequestInfo = @import("../bindings/request.zig").RequestInfo;
const RequestOptions = @import("../bindings/request.zig").RequestOptions;
const Response = @import("../bindings/response.zig").Response;
const Array = @import("../bindings/array.zig").Array;

/// External JS function for fetch - called synchronously, JS runtime handles async
pub extern fn jsFetch(urlPtr: u32, initPtr: u32) u32;

/// Perform a fetch request synchronously from Zig's perspective.
/// The JS runtime handles the async Promise resolution.
///
/// Note: Since Zig 0.11+ removed async/await, this function calls the JS
/// fetch synchronously. The actual network request is still async on the
/// JS side - this just returns immediately with a Response handle that
/// will be populated when the Promise resolves.
// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1972
pub fn fetch(request: RequestInfo, requestInit: ?RequestOptions) Response {
    // url
    const urlID = request.toID();
    defer request.free(urlID);
    // req init
    const reqInit = requestInit orelse RequestOptions{ .none = {} };
    const reqInitID = reqInit.toID();
    defer reqInit.free(reqInitID);
    // fetch
    return Response.init(jsFetch(urlID, reqInitID));
}
