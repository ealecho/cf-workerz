//! CompressionStream bindings for the Compression Streams API.
//!
//! CompressionStream compresses data using a specified algorithm (gzip, deflate, deflate-raw).
//!
//! ## Example Usage
//!
//! ```zig
//! // Create a gzip compression stream
//! const compression = CompressionStream.new(.gzip);
//! defer compression.free();
//!
//! // Pipe readable data through the compressor
//! const compressed = readable.pipeThrough(&compression.asTransform(), .{});
//! defer compressed.free();
//!
//! // Read compressed data
//! const reader = compressed.getReader();
//! defer reader.free();
//! while (reader.read()) |chunk| {
//!     // Process compressed chunk
//! }
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

/// Compression algorithm to use.
pub const CompressionFormat = enum {
    /// gzip compression (RFC 1952)
    gzip,
    /// deflate compression (RFC 1951 with zlib wrapper)
    deflate,
    /// Raw deflate compression (RFC 1951 without wrapper)
    @"deflate-raw",

    /// Convert to the string value expected by the JavaScript API.
    pub fn toString(self: CompressionFormat) []const u8 {
        return switch (self) {
            .gzip => "gzip",
            .deflate => "deflate",
            .@"deflate-raw" => "deflate-raw",
        };
    }
};

/// A stream that compresses data using the specified algorithm.
///
/// CompressionStream is a TransformStream that compresses data written to its
/// writable side and provides compressed data on its readable side.
///
/// See: https://developer.mozilla.org/en-US/docs/Web/API/CompressionStream
///
/// ## Example
///
/// ```zig
/// // Compress response body with gzip
/// const compression = CompressionStream.new(.gzip);
/// defer compression.free();
///
/// const compressed = body.pipeThrough(&compression.asTransform(), .{});
/// defer compressed.free();
/// ```
///
/// ## Supported Algorithms
///
/// - `.gzip` - gzip compression (most compatible)
/// - `.deflate` - deflate with zlib wrapper
/// - `.@"deflate-raw"` - raw deflate without wrapper
pub const CompressionStream = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) CompressionStream {
        return CompressionStream{ .id = ptr };
    }

    /// Create a new CompressionStream with the specified algorithm.
    ///
    /// ## Parameters
    /// - `format`: The compression algorithm to use
    ///
    /// ## Example
    /// ```zig
    /// const gzip = CompressionStream.new(.gzip);
    /// defer gzip.free();
    ///
    /// const deflate = CompressionStream.new(.deflate);
    /// defer deflate.free();
    /// ```
    pub fn new(format: CompressionFormat) CompressionStream {
        const formatStr = String.new(format.toString());
        defer formatStr.free();
        return CompressionStream{ .id = jsCreateClass(Classes.CompressionStream.toInt(), formatStr.id) };
    }

    /// Free the CompressionStream from the JavaScript heap.
    pub fn free(self: CompressionStream) void {
        jsFree(self.id);
    }

    /// Get the readable side of the compression stream.
    ///
    /// Compressed data is available on this stream.
    ///
    /// ## Example
    /// ```zig
    /// const output = compression.readable();
    /// const reader = output.getReader();
    /// // Read compressed data...
    /// ```
    pub fn readable(self: *const CompressionStream) ReadableStream {
        return ReadableStream{ .id = getObjectValue(self.id, "readable") };
    }

    /// Get the writable side of the compression stream.
    ///
    /// Write uncompressed data to this stream.
    ///
    /// ## Example
    /// ```zig
    /// const input = compression.writable();
    /// const writer = input.getWriter();
    /// defer writer.free();
    /// writer.write("data to compress");
    /// writer.close();
    /// ```
    pub fn writable(self: *const CompressionStream) WritableStream {
        return WritableStream{ .id = getObjectValue(self.id, "writable") };
    }

    /// Get this CompressionStream as a TransformStream for use with pipeThrough.
    ///
    /// This allows using the compression stream with ReadableStream.pipeThrough().
    /// Note: The returned TransformStream shares the same underlying JS object.
    /// Only free the CompressionStream, not the returned TransformStream.
    ///
    /// ## Example
    /// ```zig
    /// const compression = CompressionStream.new(.gzip);
    /// defer compression.free();
    ///
    /// const compressed = readable.pipeThrough(&compression.asTransform(), .{});
    /// defer compressed.free();
    /// ```
    pub fn asTransform(self: *const CompressionStream) TransformStream {
        // CompressionStream implements the TransformStream interface
        return TransformStream{ .id = self.id };
    }
};
