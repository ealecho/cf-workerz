const std = @import("std");
const common = @import("common.zig");
const Undefined = common.Undefined;
const Array = @import("array.zig").Array;
const String = @import("string.zig").String;

pub extern fn jsFnCall(fnPtr: u32, argsPtr: u32) u32;

// NOTE: Zig async/await was removed in Zig 0.11+
// The jsAsyncFnCall mechanism relied on suspend/resume which no longer exists.
// For now, AsyncFunction calls synchronously invoke the JS function.
// The JS runtime should handle promise resolution via callbacks or
// the Workers runtime's built-in async context.
pub extern fn jsAsyncFnCall(funcPtr: u32, argsPtr: u32) u32;

// Old suspend-based implementation (removed in Zig 0.11+):
// pub extern fn jsAsyncFnCall(frame: *anyopaque, funcPtr: u32, argsPtr: u32, resPtr: *u32) void;
// pub fn jsAsync(funcPtr: u32, argsPtr: u32) u32 {
//   var res: u32 = 0;
//   suspend {
//     jsAsyncFnCall(@frame(), funcPtr, argsPtr, &res);
//   }
//   return res;
// }

pub const Function = struct {
    id: u32,

    pub fn init(ptr: u32) Function {
        return Function{ .id = ptr };
    }

    pub fn free(self: *const Function) void {
        common.jsFree(self.id);
    }

    pub fn call(self: *const Function) u32 {
        return jsFnCall(self.id, Undefined);
    }

    pub fn callArgs(self: *const Function, args: anytype) u32 {
        return jsFnCall(self.id, args.id);
    }

    pub fn callArgsID(self: *const Function, id: u32) u32 {
        return jsFnCall(self.id, id);
    }
};

// NOTE: AsyncFunction in Zig 0.11+ works differently than before.
// Since Zig async was removed, we now call JS async functions synchronously
// and rely on the Workers runtime to handle the Promise resolution.
// The JS glue code needs to be updated to handle this pattern.
// TODO: Implement proper Promise-based async via JS interop callbacks.
pub const AsyncFunction = struct {
    id: u32,

    pub fn init(ptr: u32) AsyncFunction {
        return AsyncFunction{ .id = ptr };
    }

    pub fn free(self: *const AsyncFunction) void {
        common.jsFree(self.id);
    }

    // Synchronous call - JS runtime handles async via its own mechanisms
    pub fn call(self: *const AsyncFunction) u32 {
        return jsAsyncFnCall(self.id, Undefined);
    }

    pub fn callArgs(self: *const AsyncFunction, args: anytype) u32 {
        return jsAsyncFnCall(self.id, args.id);
    }

    pub fn callArgsID(self: *const AsyncFunction, id: u32) u32 {
        return jsAsyncFnCall(self.id, id);
    }
};
