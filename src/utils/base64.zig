//! Base64 encoding/decoding utilities for cf-workerz.
//!
//! Provides standard Base64 and URL-safe Base64 encoding used by JWTs
//! and other authentication mechanisms.
//!
//! ## Example
//!
//! ```zig
//! const base64 = @import("cf-workerz").base64;
//!
//! // Standard base64
//! var buf: [100]u8 = undefined;
//! const encoded = base64.encode(&buf, "Hello, World!");
//! // encoded = "SGVsbG8sIFdvcmxkIQ=="
//!
//! // URL-safe base64 (for JWTs)
//! const urlEncoded = base64.encodeUrl(&buf, "Hello, World!");
//! // urlEncoded = "SGVsbG8sIFdvcmxkIQ" (no padding, URL-safe)
//! ```

const std = @import("std");

/// Standard Base64 alphabet
const standard_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// URL-safe Base64 alphabet (RFC 4648)
const url_safe_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// Standard Base64 encoder with padding
const standard_encoder = std.base64.Base64Encoder.init(standard_alphabet.*, '=');

/// Standard Base64 decoder
const standard_decoder = std.base64.Base64Decoder.init(standard_alphabet.*, '=');

/// URL-safe Base64 encoder without padding (for JWTs)
const url_encoder = std.base64.Base64Encoder.init(url_safe_alphabet.*, null);

/// URL-safe Base64 decoder (handles both padded and unpadded)
const url_decoder = std.base64.Base64Decoder.init(url_safe_alphabet.*, null);

// ============================================================================
// Standard Base64
// ============================================================================

/// Calculate the encoded length for standard base64.
pub fn calcEncodedSize(input_len: usize) usize {
    return standard_encoder.calcSize(input_len);
}

/// Calculate the maximum decoded length for standard base64.
pub fn calcDecodedSize(encoded_len: usize) usize {
    return standard_decoder.calcSizeUpperBound(encoded_len) catch encoded_len;
}

/// Encode data to standard Base64.
///
/// Returns a slice of the buffer containing the encoded data.
/// The buffer must be large enough to hold the encoded output.
/// Use `calcEncodedSize()` to determine the required buffer size.
///
/// ## Example
/// ```zig
/// var buf: [100]u8 = undefined;
/// const encoded = base64.encode(&buf, "Hello");
/// // encoded = "SGVsbG8="
/// ```
pub fn encode(dest: []u8, source: []const u8) []const u8 {
    return standard_encoder.encode(dest, source);
}

/// Decode standard Base64 data.
///
/// Returns the decoded data as a slice, or an error if the input is invalid.
/// The destination buffer must be large enough to hold the decoded output.
/// Use `calcDecodedSize()` to determine the required buffer size.
///
/// ## Example
/// ```zig
/// var buf: [100]u8 = undefined;
/// const decoded = try base64.decode(&buf, "SGVsbG8=");
/// // decoded = "Hello"
/// ```
pub fn decode(dest: []u8, source: []const u8) ![]const u8 {
    const len = try standard_decoder.calcSizeForSlice(source);
    try standard_decoder.decode(dest[0..len], source);
    return dest[0..len];
}

// ============================================================================
// URL-Safe Base64 (for JWTs)
// ============================================================================

/// Calculate the encoded length for URL-safe base64 (no padding).
pub fn calcEncodedSizeUrl(input_len: usize) usize {
    return url_encoder.calcSize(input_len);
}

/// Calculate the maximum decoded length for URL-safe base64.
pub fn calcDecodedSizeUrl(encoded_len: usize) usize {
    return url_decoder.calcSizeUpperBound(encoded_len) catch encoded_len;
}

/// Encode data to URL-safe Base64 (no padding).
///
/// This is the format used by JWTs and other URL-safe contexts.
/// Uses `-` and `_` instead of `+` and `/`, with no padding.
///
/// ## Example
/// ```zig
/// var buf: [100]u8 = undefined;
/// const encoded = base64.encodeUrl(&buf, "Hello");
/// // encoded = "SGVsbG8" (no padding)
/// ```
pub fn encodeUrl(dest: []u8, source: []const u8) []const u8 {
    return url_encoder.encode(dest, source);
}

/// Decode URL-safe Base64 data.
///
/// Handles both padded and unpadded input.
///
/// ## Example
/// ```zig
/// var buf: [100]u8 = undefined;
/// const decoded = try base64.decodeUrl(&buf, "SGVsbG8");
/// // decoded = "Hello"
/// ```
pub fn decodeUrl(dest: []u8, source: []const u8) ![]const u8 {
    const len = try url_decoder.calcSizeForSlice(source);
    try url_decoder.decode(dest[0..len], source);
    return dest[0..len];
}

// ============================================================================
// Allocating Variants
// ============================================================================

/// Encode data to standard Base64, allocating the result.
///
/// Caller owns the returned memory and must free it with the same allocator.
///
/// ## Example
/// ```zig
/// const allocator = std.heap.page_allocator;
/// const encoded = try base64.encodeAlloc(allocator, "Hello");
/// defer allocator.free(encoded);
/// ```
pub fn encodeAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const size = calcEncodedSize(source.len);
    const dest = try allocator.alloc(u8, size);
    _ = encode(dest, source);
    return dest;
}

/// Decode standard Base64 data, allocating the result.
///
/// Caller owns the returned memory and must free it with the same allocator.
///
/// ## Example
/// ```zig
/// const allocator = std.heap.page_allocator;
/// const decoded = try base64.decodeAlloc(allocator, "SGVsbG8=");
/// defer allocator.free(decoded);
/// ```
pub fn decodeAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const max_size = calcDecodedSize(source.len);
    const dest = try allocator.alloc(u8, max_size);
    errdefer allocator.free(dest);

    const result = decode(dest, source) catch |err| {
        allocator.free(dest);
        return err;
    };

    // Resize to actual decoded length
    if (result.len < dest.len) {
        return allocator.realloc(dest, result.len) catch dest[0..result.len];
    }
    return dest;
}

/// Encode data to URL-safe Base64, allocating the result.
///
/// Caller owns the returned memory and must free it with the same allocator.
pub fn encodeUrlAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const size = calcEncodedSizeUrl(source.len);
    const dest = try allocator.alloc(u8, size);
    _ = encodeUrl(dest, source);
    return dest;
}

/// Decode URL-safe Base64 data, allocating the result.
///
/// Caller owns the returned memory and must free it with the same allocator.
pub fn decodeUrlAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const max_size = calcDecodedSizeUrl(source.len);
    const dest = try allocator.alloc(u8, max_size);
    errdefer allocator.free(dest);

    const result = decodeUrl(dest, source) catch |err| {
        allocator.free(dest);
        return err;
    };

    // Resize to actual decoded length
    if (result.len < dest.len) {
        return allocator.realloc(dest, result.len) catch dest[0..result.len];
    }
    return dest;
}

// ============================================================================
// Tests
// ============================================================================

test "standard base64 encode" {
    var buf: [100]u8 = undefined;
    const result = encode(&buf, "Hello, World!");
    try std.testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ==", result);
}

test "standard base64 decode" {
    var buf: [100]u8 = undefined;
    const result = try decode(&buf, "SGVsbG8sIFdvcmxkIQ==");
    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "url-safe base64 encode" {
    var buf: [100]u8 = undefined;
    const result = encodeUrl(&buf, "Hello, World!");
    try std.testing.expectEqualStrings("SGVsbG8sIFdvcmxkIQ", result);
}

test "url-safe base64 decode" {
    var buf: [100]u8 = undefined;
    const result = try decodeUrl(&buf, "SGVsbG8sIFdvcmxkIQ");
    try std.testing.expectEqualStrings("Hello, World!", result);
}

test "empty input" {
    var buf: [100]u8 = undefined;
    const encoded = encode(&buf, "");
    try std.testing.expectEqualStrings("", encoded);
}

test "binary data" {
    var buf: [100]u8 = undefined;
    const binary = &[_]u8{ 0x00, 0xFF, 0x7F, 0x80 };
    const encoded = encode(&buf, binary);
    try std.testing.expectEqualStrings("AP9/gA==", encoded);

    var decode_buf: [100]u8 = undefined;
    const decoded = try decode(&decode_buf, encoded);
    try std.testing.expectEqualSlices(u8, binary, decoded);
}
