const common = @import("common.zig");
const jsCreateClass = common.jsCreateClass;
const jsFree = common.jsFree;
const jsSize = common.jsSize;
const Classes = common.Classes;
const Undefined = common.Undefined;
const String = @import("string.zig").String;

pub extern fn jsArrayPush(arrID: u32, args: u32) void;
pub extern fn jsArrayPushNum(arrID: u32, value: f64) void;
pub extern fn jsArrayGet(arrID: u32, pos: u32) u32;
pub extern fn jsArrayGetNum(arrID: u32, pos: u32) f64;

pub fn arrayPushNum(arr: *const Array, comptime T: type, num: T) void {
    var fValue: f64 = 0;
    switch (@typeInfo(T)) {
        .int => {
            fValue = @floatFromInt(num);
        },
        .float => {
            fValue = @floatCast(num);
        },
        else => String.new("Can't cast f64 to " ++ @typeName(T)).throw(),
    }
    jsArrayPushNum(arr.id, fValue);
}

pub const Array = struct {
    id: u32,

    pub fn init(ptr: u32) Array {
        return Array{ .id = ptr };
    }

    pub fn new() Array {
        return Array{ .id = jsCreateClass(Classes.Array.toInt(), Undefined) };
    }

    pub fn free(self: *const Array) void {
        jsFree(self.id);
    }

    pub fn push(self: *const Array, jsValue: anytype) void {
        jsArrayPush(self.id, jsValue.id);
    }

    pub fn pushNum(self: *const Array, comptime T: type, num: T) void {
        arrayPushNum(self, T, num);
    }

    pub fn pushID(self: *const Array, jsPtr: u32) void {
        jsArrayPush(self.id, jsPtr);
    }

    pub fn pushText(self: *const Array, str: []const u8) void {
        const jsStr = String.new(str);
        defer jsStr.free();
        jsArrayPush(self.id, jsStr.id);
    }

    pub fn get(self: *const Array, pos: u32) u32 {
        return jsArrayGet(self.id, pos);
    }

    pub fn getNum(self: *const Array, pos: u32, comptime T: type) T {
        const num = jsArrayGetNum(self.id, pos);
        switch (@typeInfo(T)) {
            .int => {
                const result: T = @intFromFloat(num);
                return result;
            },
            .float => {
                const result: T = @floatCast(num);
                return result;
            },
            else => {
                String.new("Can't cast f64 to " ++ @typeName(T)).throw();
                return @as(T, 0);
            },
        }
    }

    pub fn getType(self: *const Array, comptime T: type, pos: u32) T {
        const id = jsArrayGet(self.id, pos);
        return T.init(id);
    }

    pub fn length(self: *const Array) u32 {
        return jsSize(self.id);
    }
};

// External function for getting bytes from JS heap objects
pub extern fn jsToBytes(ptr: u32) u32;

/// Uint8Array binding for working with binary data.
///
/// This is a binding to the JavaScript Uint8Array class.
/// See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Uint8Array
///
/// ## Example
///
/// ```zig
/// const arr = Uint8Array.init(jsPtr);
/// defer arr.free();
///
/// const data = arr.bytes();
/// // use data bytes
/// ```
pub const Uint8Array = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) Uint8Array {
        return Uint8Array{ .id = ptr };
    }

    /// Create a new Uint8Array from a byte slice.
    ///
    /// ## Example
    /// ```zig
    /// const data = [_]u8{ 0x48, 0x65, 0x6c, 0x6c, 0x6f };
    /// const arr = Uint8Array.new(&data);
    /// defer arr.free();
    /// ```
    pub fn new(data: []const u8) Uint8Array {
        // Create ArrayBuffer first, then Uint8Array from it
        const bufId = jsToBuffer(@intFromPtr(data.ptr), data.len);
        const args = Array.new();
        defer args.free();
        args.pushID(bufId);
        defer jsFree(bufId);
        return Uint8Array{ .id = jsCreateClass(Classes.Uint8Array.toInt(), args.id) };
    }

    /// Free the Uint8Array from the JavaScript heap.
    pub fn free(self: *const Uint8Array) void {
        jsFree(self.id);
    }

    /// Get the bytes from this Uint8Array.
    ///
    /// Returns a slice pointing to the data copied into WASM linear memory.
    pub fn bytes(self: *const Uint8Array) []const u8 {
        const len = jsSize(self.id);
        if (len == 0) {
            return "";
        }
        // jsToBytes copies the bytes to WASM memory and returns the pointer
        const ptr = jsToBytes(self.id);
        if (ptr == 0) {
            return "";
        }
        return @as([*]const u8, @ptrFromInt(ptr))[0..len];
    }

    /// Get the length of this Uint8Array.
    pub fn length(self: *const Uint8Array) u32 {
        return jsSize(self.id);
    }
};

// External function for creating ArrayBuffer from WASM memory
pub extern fn jsToBuffer(ptr: u32, len: usize) u32;
