//! WritableStream bindings for the Web Streams API.
//!
//! WritableStream represents a writable destination for streaming data.
//!
//! ## Example Usage
//!
//! ```zig
//! // Get a writer and write data
//! const stream = WritableStream.new();
//! defer stream.free();
//!
//! const writer = stream.getWriter();
//! defer writer.free();
//!
//! writer.write("Hello, ");
//! writer.write("World!");
//! writer.close();
//! ```

const common = @import("../common.zig");
const jsFree = common.jsFree;
const jsCreateClass = common.jsCreateClass;
const Classes = common.Classes;
const Undefined = common.Undefined;
const True = common.True;
const object = @import("../object.zig");
const Object = object.Object;
const getObjectValue = object.getObjectValue;
const AsyncFunction = @import("../function.zig").AsyncFunction;
const Function = @import("../function.zig").Function;
const String = @import("../string.zig").String;
const Array = @import("../array.zig").Array;

/// A writer for a WritableStream.
///
/// Acquired via `WritableStream.getWriter()`.
/// The writer locks the stream, preventing other writers.
///
/// ## Example
/// ```zig
/// const writer = stream.getWriter();
/// defer writer.free();
///
/// writer.write("chunk 1");
/// writer.write("chunk 2");
/// writer.close();
/// ```
pub const WritableStreamDefaultWriter = struct {
    id: u32,

    pub fn init(ptr: u32) WritableStreamDefaultWriter {
        return WritableStreamDefaultWriter{ .id = ptr };
    }

    /// Free the writer and release the lock on the stream.
    pub fn free(self: *const WritableStreamDefaultWriter) void {
        jsFree(self.id);
    }

    /// Write a chunk of data to the stream.
    ///
    /// ## Example
    /// ```zig
    /// writer.write("Hello, World!");
    /// ```
    pub fn write(self: *const WritableStreamDefaultWriter, chunk: []const u8) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "write") };
        defer func.free();
        const chunkStr = String.new(chunk);
        defer chunkStr.free();
        _ = func.callArgs(&chunkStr);
    }

    /// Write bytes to the stream.
    pub fn writeBytes(self: *const WritableStreamDefaultWriter, bytes: []const u8) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "write") };
        defer func.free();
        const buffer = common.jsToBuffer(@intFromPtr(bytes.ptr), @intCast(bytes.len));
        defer jsFree(buffer);
        const jsValue = common.JSValue.init(buffer);
        _ = func.callArgs(&jsValue);
    }

    /// Close the writer and the underlying stream.
    pub fn close(self: *const WritableStreamDefaultWriter) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "close") };
        defer func.free();
        _ = func.call();
    }

    /// Abort the writer with a reason.
    pub fn abort(self: *const WritableStreamDefaultWriter, reason: []const u8) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "abort") };
        defer func.free();
        const reasonStr = String.new(reason);
        defer reasonStr.free();
        _ = func.callArgs(&reasonStr);
    }

    /// Release the lock on the stream without closing it.
    ///
    /// This allows another writer to be acquired.
    pub fn releaseLock(self: *const WritableStreamDefaultWriter) void {
        const func = Function.init(getObjectValue(self.id, "releaseLock"));
        defer func.free();
        _ = func.call();
    }

    /// Get the desired size to fill the stream's internal queue.
    ///
    /// Returns null if the stream is errored or closed.
    pub fn desiredSize(self: *const WritableStreamDefaultWriter) ?i64 {
        const ptr = getObjectValue(self.id, "desiredSize");
        if (ptr <= common.DefaultValueSize) {
            return null;
        }
        return common.getNum(ptr, i64);
    }

    /// Returns true when the stream is ready to accept more data.
    pub fn ready(self: *const WritableStreamDefaultWriter) bool {
        const ptr = getObjectValue(self.id, "ready");
        return ptr != Undefined;
    }

    /// Returns true when the stream is closed.
    pub fn closed(self: *const WritableStreamDefaultWriter) bool {
        const ptr = getObjectValue(self.id, "closed");
        return ptr != Undefined;
    }
};

/// A writable stream for streaming data.
///
/// This is a binding to the JavaScript WritableStream class.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/WritableStream
///
/// ## Example
///
/// ```zig
/// const stream = WritableStream.new();
/// defer stream.free();
///
/// // Check if locked
/// if (!stream.locked()) {
///     const writer = stream.getWriter();
///     defer writer.free();
///     writer.write("data");
///     writer.close();
/// }
/// ```
pub const WritableStream = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) WritableStream {
        return WritableStream{ .id = ptr };
    }

    /// Create a new WritableStream.
    ///
    /// Note: Creating streams with custom sinks is not yet supported.
    pub fn new() WritableStream {
        return WritableStream{ .id = jsCreateClass(Classes.WritableStream.toInt(), Undefined) };
    }

    /// Free the WritableStream from the JavaScript heap.
    pub fn free(self: WritableStream) void {
        jsFree(self.id);
    }

    /// Returns true if the stream is locked to a writer.
    pub fn locked(self: *const WritableStream) bool {
        const jsPtr = getObjectValue(self.id, "locked");
        return jsPtr == True;
    }

    /// Abort the stream.
    ///
    /// This signals that the producer can no longer write and releases resources.
    pub fn abort(self: *const WritableStream) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "abort") };
        defer func.free();
        _ = func.call();
    }

    /// Abort the stream with a reason.
    pub fn abortWithReason(self: *const WritableStream, reason: []const u8) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "abort") };
        defer func.free();
        const reasonStr = String.new(reason);
        defer reasonStr.free();
        _ = func.callArgs(&reasonStr);
    }

    /// Close the stream.
    ///
    /// This signals that no more data will be written.
    pub fn close(self: *const WritableStream) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "close") };
        defer func.free();
        _ = func.call();
    }

    /// Get a writer for the stream.
    ///
    /// This locks the stream - only one writer can be active at a time.
    /// The caller must free the returned writer.
    ///
    /// ## Example
    /// ```zig
    /// const writer = stream.getWriter();
    /// defer writer.free();
    ///
    /// writer.write("Hello!");
    /// writer.close();
    /// ```
    pub fn getWriter(self: *const WritableStream) WritableStreamDefaultWriter {
        const func = Function.init(getObjectValue(self.id, "getWriter"));
        defer func.free();
        const result = func.call();
        return WritableStreamDefaultWriter.init(result);
    }
};
