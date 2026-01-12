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
};
