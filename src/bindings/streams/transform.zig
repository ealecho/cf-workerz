//! TransformStream bindings for the Web Streams API.
//!
//! TransformStream allows you to pipe data through a transformer that can
//! modify the data as it passes through.
//!
//! ## Example Usage
//!
//! ```zig
//! // Use TransformStream to pass data through
//! const transform = TransformStream.new();
//! defer transform.free();
//!
//! // Get the readable and writable sides
//! const readable = transform.readable();
//! const writable = transform.writable();
//!
//! // Write to writable, read from readable
//! const writer = writable.getWriter();
//! defer writer.free();
//! writer.write("hello");
//! writer.close();
//! ```
//!
//! For compression/decompression, use CompressionStream or DecompressionStream.

const common = @import("../common.zig");
const jsFree = common.jsFree;
const jsCreateClass = common.jsCreateClass;
const Classes = common.Classes;
const Undefined = common.Undefined;
const object = @import("../object.zig");
const getObjectValue = object.getObjectValue;
const ReadableStream = @import("readable.zig").ReadableStream;
const WritableStream = @import("writable.zig").WritableStream;

/// A transform stream with readable and writable sides.
///
/// This is a binding to the JavaScript TransformStream class.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/TransformStream
///
/// ## Example
///
/// ```zig
/// // Create an identity transform (pass-through)
/// const transform = TransformStream.new();
/// defer transform.free();
///
/// // Pipe through the transform
/// const output = input.pipeThrough(&transform, .{});
/// defer output.free();
/// ```
///
/// ## Use with pipeThrough
///
/// ```zig
/// // Chain with compression
/// const compression = CompressionStream.new(.gzip);
/// defer compression.free();
///
/// const compressed = readable.pipeThrough(&compression.transform(), .{});
/// ```
pub const TransformStream = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) TransformStream {
        return TransformStream{ .id = ptr };
    }

    /// Create a new identity TransformStream.
    ///
    /// An identity transform passes data through unchanged.
    /// For custom transformations, use the underlying JavaScript API.
    ///
    /// ## Example
    /// ```zig
    /// const transform = TransformStream.new();
    /// defer transform.free();
    /// ```
    pub fn new() TransformStream {
        return TransformStream{ .id = jsCreateClass(Classes.TransformStream.toInt(), Undefined) };
    }

    /// Free the TransformStream from the JavaScript heap.
    pub fn free(self: TransformStream) void {
        jsFree(self.id);
    }

    /// Get the readable side of the transform.
    ///
    /// Data written to the writable side appears here after transformation.
    /// Note: The returned stream shares the same JS object; only free the TransformStream.
    ///
    /// ## Example
    /// ```zig
    /// const output = transform.readable();
    /// // Read from output...
    /// ```
    pub fn readable(self: *const TransformStream) ReadableStream {
        return ReadableStream{ .id = getObjectValue(self.id, "readable") };
    }

    /// Get the writable side of the transform.
    ///
    /// Data written here will be transformed and available on the readable side.
    /// Note: The returned stream shares the same JS object; only free the TransformStream.
    ///
    /// ## Example
    /// ```zig
    /// const input = transform.writable();
    /// const writer = input.getWriter();
    /// defer writer.free();
    /// writer.write("data");
    /// writer.close();
    /// ```
    pub fn writable(self: *const TransformStream) WritableStream {
        return WritableStream{ .id = getObjectValue(self.id, "writable") };
    }
};
