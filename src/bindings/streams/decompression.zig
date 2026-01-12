//! DecompressionStream bindings for the Compression Streams API.
//!
//! DecompressionStream decompresses data using a specified algorithm (gzip, deflate, deflate-raw).
//!
//! ## Example Usage
//!
//! ```zig
//! // Create a gzip decompression stream
//! const decompression = DecompressionStream.new(.gzip);
//! defer decompression.free();
//!
//! // Pipe compressed data through the decompressor
//! const decompressed = compressedStream.pipeThrough(&decompression.asTransform(), .{});
//! defer decompressed.free();
//!
//! // Read decompressed data
//! const text = decompressed.text();
//! ```

const common = @import("../common.zig");
const jsFree = common.jsFree;
const jsCreateClass = common.jsCreateClass;
const Classes = common.Classes;
const String = @import("../string.zig").String;
const object = @import("../object.zig");
const getObjectValue = object.getObjectValue;
const ReadableStream = @import("readable.zig").ReadableStream;
const WritableStream = @import("writable.zig").WritableStream;
const TransformStream = @import("transform.zig").TransformStream;
const CompressionFormat = @import("compression.zig").CompressionFormat;

/// A stream that decompresses data using the specified algorithm.
///
/// DecompressionStream is a TransformStream that decompresses data written to its
/// writable side and provides decompressed data on its readable side.
///
/// See: https://developer.mozilla.org/en-US/docs/Web/API/DecompressionStream
///
/// ## Example
///
/// ```zig
/// // Decompress gzip-compressed response
/// const decompression = DecompressionStream.new(.gzip);
/// defer decompression.free();
///
/// const decompressed = compressedBody.pipeThrough(&decompression.asTransform(), .{});
/// defer decompressed.free();
///
/// const text = decompressed.text();
/// ```
///
/// ## Supported Algorithms
///
/// - `.gzip` - gzip decompression
/// - `.deflate` - deflate with zlib wrapper
/// - `.@"deflate-raw"` - raw deflate without wrapper
///
/// ## Note
/// The decompression format must match the compression format used.
/// Attempting to decompress data with the wrong format will result in an error.
pub const DecompressionStream = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) DecompressionStream {
        return DecompressionStream{ .id = ptr };
    }

    /// Create a new DecompressionStream with the specified algorithm.
    ///
    /// ## Parameters
    /// - `format`: The decompression algorithm to use (must match compression format)
    ///
    /// ## Example
    /// ```zig
    /// const gzip = DecompressionStream.new(.gzip);
    /// defer gzip.free();
    ///
    /// const deflate = DecompressionStream.new(.deflate);
    /// defer deflate.free();
    /// ```
    pub fn new(format: CompressionFormat) DecompressionStream {
        const formatStr = String.new(format.toString());
        defer formatStr.free();
        return DecompressionStream{ .id = jsCreateClass(Classes.DecompressionStream.toInt(), formatStr.id) };
    }

    /// Free the DecompressionStream from the JavaScript heap.
    pub fn free(self: DecompressionStream) void {
        jsFree(self.id);
    }

    /// Get the readable side of the decompression stream.
    ///
    /// Decompressed data is available on this stream.
    ///
    /// ## Example
    /// ```zig
    /// const output = decompression.readable();
    /// const text = output.text();
    /// ```
    pub fn readable(self: *const DecompressionStream) ReadableStream {
        return ReadableStream{ .id = getObjectValue(self.id, "readable") };
    }

    /// Get the writable side of the decompression stream.
    ///
    /// Write compressed data to this stream.
    ///
    /// ## Example
    /// ```zig
    /// const input = decompression.writable();
    /// const writer = input.getWriter();
    /// defer writer.free();
    /// writer.writeBytes(compressedData);
    /// writer.close();
    /// ```
    pub fn writable(self: *const DecompressionStream) WritableStream {
        return WritableStream{ .id = getObjectValue(self.id, "writable") };
    }

    /// Get this DecompressionStream as a TransformStream for use with pipeThrough.
    ///
    /// This allows using the decompression stream with ReadableStream.pipeThrough().
    /// Note: The returned TransformStream shares the same underlying JS object.
    /// Only free the DecompressionStream, not the returned TransformStream.
    ///
    /// ## Example
    /// ```zig
    /// const decompression = DecompressionStream.new(.gzip);
    /// defer decompression.free();
    ///
    /// const decompressed = compressed.pipeThrough(&decompression.asTransform(), .{});
    /// defer decompressed.free();
    /// ```
    pub fn asTransform(self: *const DecompressionStream) TransformStream {
        // DecompressionStream implements the TransformStream interface
        return TransformStream{ .id = self.id };
    }
};
