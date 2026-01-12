//! ReadableStream bindings for the Web Streams API.
//!
//! ReadableStream represents a readable stream of byte data.
//!
//! ## Example Usage
//!
//! ```zig
//! // Pipe a readable stream to a writable stream
//! const readable = response.body();
//! defer readable.free();
//!
//! const writable = getWritableDestination();
//! defer writable.free();
//!
//! readable.pipeTo(&writable, .{});
//!
//! // Or use pipeThrough for transformation
//! const transform = CompressionStream.new(.gzip);
//! defer transform.free();
//!
//! const compressed = readable.pipeThrough(&transform, .{});
//! defer compressed.free();
//! ```

const common = @import("../common.zig");
const jsFree = common.jsFree;
const jsCreateClass = common.jsCreateClass;
const Classes = common.Classes;
const toJSBool = common.toJSBool;
const Undefined = common.Undefined;
const True = common.True;
const object = @import("../object.zig");
const Object = object.Object;
const getObjectValue = object.getObjectValue;
const AsyncFunction = @import("../function.zig").AsyncFunction;
const Function = @import("../function.zig").Function;
const WritableStream = @import("writable.zig").WritableStream;
const TransformStream = @import("transform.zig").TransformStream;
const Array = @import("../array.zig").Array;
const String = @import("../string.zig").String;
const Uint8Array = @import("../array.zig").Uint8Array;

/// Result from reading a chunk from a ReadableStreamDefaultReader.
///
/// When `done` is true, the stream is exhausted and `value` will be null.
/// When `done` is false, `value` contains the chunk data.
pub const ReadResult = struct {
    /// The chunk data, or null if the stream is done.
    value: ?[]const u8,
    /// True if the stream has been fully read.
    done: bool,
};

/// A reader for a ReadableStream that allows reading chunks.
///
/// Obtained via `ReadableStream.getReader()`. While a reader is active,
/// the stream is locked and cannot be read by other consumers.
///
/// ## Example
///
/// ```zig
/// const stream = response.body();
/// defer stream.free();
///
/// const reader = stream.getReader();
/// defer reader.free();
///
/// while (true) {
///     const result = reader.read();
///     if (result.done) break;
///     if (result.value) |chunk| {
///         // process chunk
///     }
/// }
/// ```
pub const ReadableStreamDefaultReader = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) ReadableStreamDefaultReader {
        return ReadableStreamDefaultReader{ .id = ptr };
    }

    /// Free the reader from the JavaScript heap.
    ///
    /// Note: This does NOT release the lock on the stream.
    /// Call `releaseLock()` first if you want to unlock the stream.
    pub fn free(self: ReadableStreamDefaultReader) void {
        jsFree(self.id);
    }

    /// Read the next chunk from the stream.
    ///
    /// Returns a ReadResult with:
    /// - `done`: true if the stream is exhausted
    /// - `value`: the chunk data (null if done)
    ///
    /// ## Example
    /// ```zig
    /// const result = reader.read();
    /// if (!result.done) {
    ///     if (result.value) |chunk| {
    ///         // process chunk bytes
    ///     }
    /// }
    /// ```
    pub fn read(self: *const ReadableStreamDefaultReader) ReadResult {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "read") };
        defer func.free();

        const resultPtr = func.call();
        if (resultPtr <= common.DefaultValueSize) {
            return ReadResult{ .value = null, .done = true };
        }
        defer jsFree(resultPtr);

        // Result is { done: boolean, value: Uint8Array | undefined }
        const donePtr = getObjectValue(resultPtr, "done");
        const done = donePtr == True;

        if (done) {
            return ReadResult{ .value = null, .done = true };
        }

        const valuePtr = getObjectValue(resultPtr, "value");
        if (valuePtr <= common.DefaultValueSize) {
            return ReadResult{ .value = null, .done = false };
        }

        // Value is a Uint8Array
        const arr = Uint8Array.init(valuePtr);
        defer arr.free();
        const bytes = arr.bytes();

        return ReadResult{ .value = bytes, .done = false };
    }

    /// Cancel the stream with an optional reason.
    ///
    /// This signals that the consumer is no longer interested in the stream.
    pub fn cancel(self: *const ReadableStreamDefaultReader) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "cancel") };
        defer func.free();
        _ = func.call();
    }

    /// Cancel the stream with a reason.
    pub fn cancelWithReason(self: *const ReadableStreamDefaultReader, reason: []const u8) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "cancel") };
        defer func.free();
        const reasonStr = String.new(reason);
        defer reasonStr.free();
        _ = func.callArgs(&reasonStr);
    }

    /// Release the lock on the stream.
    ///
    /// After calling this, the reader can no longer be used to read,
    /// but the stream can be acquired by another reader.
    pub fn releaseLock(self: *const ReadableStreamDefaultReader) void {
        const func = Function.init(getObjectValue(self.id, "releaseLock"));
        defer func.free();
        _ = func.call();
    }

    /// Returns a promise that resolves when the stream closes.
    ///
    /// Note: In the current implementation, this blocks until closed.
    pub fn closed(self: *const ReadableStreamDefaultReader) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "closed") };
        defer func.free();
        _ = func.call();
    }
};

/// Options for ReadableStream.pipeTo().
///
/// See: https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream/pipeTo
pub const PipeToOptions = struct {
    /// If true, the destination won't be closed when the source closes.
    preventClose: ?bool = null,
    /// If true, the destination won't be aborted when the source errors.
    preventAbort: ?bool = null,
    /// If true, the source won't be canceled when the destination errors.
    preventCancel: ?bool = null,

    pub fn toObject(self: *const PipeToOptions) Object {
        const obj = Object.new();
        if (self.preventClose) |v| {
            obj.setID("preventClose", toJSBool(v));
        }
        if (self.preventAbort) |v| {
            obj.setID("preventAbort", toJSBool(v));
        }
        if (self.preventCancel) |v| {
            obj.setID("preventCancel", toJSBool(v));
        }
        return obj;
    }
};

/// Options for ReadableStream.pipeThrough().
pub const PipeThroughOptions = struct {
    /// If true, the writable side won't be closed when the readable closes.
    preventClose: ?bool = null,
    /// If true, the writable side won't be aborted when the readable errors.
    preventAbort: ?bool = null,
    /// If true, the readable side won't be canceled when the writable errors.
    preventCancel: ?bool = null,

    pub fn toObject(self: *const PipeThroughOptions) Object {
        const obj = Object.new();
        if (self.preventClose) |v| {
            obj.setID("preventClose", toJSBool(v));
        }
        if (self.preventAbort) |v| {
            obj.setID("preventAbort", toJSBool(v));
        }
        if (self.preventCancel) |v| {
            obj.setID("preventCancel", toJSBool(v));
        }
        return obj;
    }
};

/// A readable stream of byte data.
///
/// This is a binding to the JavaScript ReadableStream class.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream
///
/// ## Example
///
/// ```zig
/// // Get body from response
/// const body = response.body();
/// defer body.free();
///
/// // Check if locked
/// if (body.locked()) {
///     // stream is being read
/// }
///
/// // Pipe to a destination
/// body.pipeTo(&writable, .{});
/// ```
pub const ReadableStream = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) ReadableStream {
        return ReadableStream{ .id = ptr };
    }

    /// Create a new ReadableStream.
    ///
    /// Note: Creating streams with custom sources is not yet supported.
    /// Use this for wrapping existing stream objects.
    pub fn new() ReadableStream {
        return ReadableStream{ .id = jsCreateClass(Classes.ReadableStream.toInt(), Undefined) };
    }

    /// Free the ReadableStream from the JavaScript heap.
    pub fn free(self: ReadableStream) void {
        jsFree(self.id);
    }

    /// Returns true if the stream is locked to a reader.
    ///
    /// A stream becomes locked when a reader is acquired via getReader()
    /// or when piping to a destination.
    pub fn locked(self: *const ReadableStream) bool {
        const jsPtr = getObjectValue(self.id, "locked");
        return jsPtr == True;
    }

    /// Cancel the stream.
    ///
    /// This signals that the consumer is no longer interested in the stream,
    /// allowing the underlying source to release resources.
    pub fn cancel(self: *const ReadableStream) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "cancel") };
        defer func.free();
        _ = func.call();
    }

    /// Cancel the stream with a reason.
    pub fn cancelWithReason(self: *const ReadableStream, reason: []const u8) void {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "cancel") };
        defer func.free();
        const reasonStr = String.new(reason);
        defer reasonStr.free();
        _ = func.callArgs(&reasonStr);
    }

    /// Pipe the readable stream to a writable stream.
    ///
    /// This reads from the source and writes to the destination until
    /// the source is exhausted, then closes the destination.
    ///
    /// ## Example
    /// ```zig
    /// readable.pipeTo(&writable, .{});
    ///
    /// // With options
    /// readable.pipeTo(&writable, .{ .preventClose = true });
    /// ```
    pub fn pipeTo(self: *const ReadableStream, destination: *const WritableStream, options: PipeToOptions) void {
        const optObj = options.toObject();
        defer optObj.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "pipeTo") };
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.pushID(destination.id);
        args.push(&optObj);

        _ = func.callArgs(&args);
    }

    /// Pipe the readable stream through a transform stream.
    ///
    /// Returns the readable side of the transform, allowing chained transformations.
    ///
    /// ## Example
    /// ```zig
    /// // Compress a stream
    /// const compression = CompressionStream.new(.gzip);
    /// defer compression.free();
    ///
    /// const compressed = readable.pipeThrough(&compression.transform(), .{});
    /// defer compressed.free();
    /// ```
    pub fn pipeThrough(self: *const ReadableStream, transform: *const TransformStream, options: PipeThroughOptions) ReadableStream {
        const optObj = options.toObject();
        defer optObj.free();
        const func = Function.init(getObjectValue(self.id, "pipeThrough"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.pushID(transform.id);
        args.push(&optObj);

        const result = func.callArgs(&args);
        return ReadableStream.init(result);
    }

    /// Tee (split) the stream into two independent branches.
    ///
    /// Both branches will receive the same data.
    /// The original stream becomes locked.
    ///
    /// ## Example
    /// ```zig
    /// const branches = readable.tee();
    /// defer branches[0].free();
    /// defer branches[1].free();
    ///
    /// // Use branches[0] and branches[1] independently
    /// ```
    pub fn tee(self: *const ReadableStream) [2]ReadableStream {
        const func = Function.init(getObjectValue(self.id, "tee"));
        defer func.free();
        const result = func.call();
        const arr = Array.init(result);
        defer arr.free();

        return .{
            ReadableStream.init(arr.get(0)),
            ReadableStream.init(arr.get(1)),
        };
    }

    /// Get a reader to read the stream chunk by chunk.
    ///
    /// The stream becomes locked while the reader is active.
    /// Call `releaseLock()` on the reader to unlock the stream.
    ///
    /// ## Example
    /// ```zig
    /// const reader = stream.getReader();
    /// defer reader.free();
    ///
    /// while (true) {
    ///     const result = reader.read();
    ///     if (result.done) break;
    ///     if (result.value) |chunk| {
    ///         // process chunk
    ///     }
    /// }
    /// ```
    pub fn getReader(self: *const ReadableStream) ReadableStreamDefaultReader {
        const func = Function.init(getObjectValue(self.id, "getReader"));
        defer func.free();
        const result = func.call();
        return ReadableStreamDefaultReader.init(result);
    }

    /// Read the entire stream as a string.
    ///
    /// This is a convenience method that reads all chunks and concatenates them.
    /// The stream will be fully consumed after calling this method.
    ///
    /// ## Example
    /// ```zig
    /// const body = response.body();
    /// defer body.free();
    ///
    /// const text = body.text();
    /// // use text
    /// ```
    pub fn text(self: *const ReadableStream) ?[]const u8 {
        // Use Response to consume the stream as text
        // This is the standard way in the Workers runtime
        const responseClass = common.jsGetClass(Classes.Response.toInt());
        defer jsFree(responseClass);

        // Create a Response with this stream as body
        const args = Array.new();
        defer args.free();
        args.pushID(self.id);

        const responseId = jsCreateClass(Classes.Response.toInt(), args.id);
        defer jsFree(responseId);

        // Call response.text()
        const textFunc = AsyncFunction{ .id = getObjectValue(responseId, "text") };
        defer textFunc.free();
        const result = textFunc.call();

        if (result <= common.DefaultValueSize) {
            return null;
        }

        const str = String.init(result);
        defer str.free();
        return str.value();
    }

    /// Read the entire stream as bytes.
    ///
    /// This is a convenience method that reads all chunks and concatenates them.
    /// The stream will be fully consumed after calling this method.
    ///
    /// ## Example
    /// ```zig
    /// const body = response.body();
    /// defer body.free();
    ///
    /// const data = body.bytes();
    /// // use data
    /// ```
    pub fn bytes(self: *const ReadableStream) ?[]const u8 {
        // Use Response to consume the stream as bytes
        const args = Array.new();
        defer args.free();
        args.pushID(self.id);

        const responseId = jsCreateClass(Classes.Response.toInt(), args.id);
        defer jsFree(responseId);

        // Call response.arrayBuffer()
        const abFunc = AsyncFunction{ .id = getObjectValue(responseId, "arrayBuffer") };
        defer abFunc.free();
        const result = abFunc.call();

        if (result <= common.DefaultValueSize) {
            return null;
        }

        // Convert ArrayBuffer to Uint8Array to get bytes
        const uint8Args = Array.new();
        defer uint8Args.free();
        uint8Args.pushID(result);
        defer jsFree(result);

        const uint8ArrayId = jsCreateClass(Classes.Uint8Array.toInt(), uint8Args.id);
        const arr = Uint8Array.init(uint8ArrayId);
        defer arr.free();

        return arr.bytes();
    }
};
