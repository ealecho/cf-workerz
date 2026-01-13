//! JSON Web Token (JWT) creation and verification.
//!
//! This module provides JWT creation and verification using HMAC-SHA256 (HS256),
//! with support for standard claims and OWASP-compliant validation.
//!
//! ## Supported Algorithms
//!
//! - HS256 (HMAC-SHA256) - Currently implemented
//! - RS256, ES256 - Planned for future versions
//!
//! ## Security Features
//!
//! - Timing-safe signature verification
//! - Issuer (`iss`) and Audience (`aud`) validation
//! - Expiration (`exp`) and Not-Before (`nbf`) checks
//! - Clock skew tolerance
//!
//! ## Example
//!
//! ```zig
//! const jwt = @import("cf-workerz").jwt;
//!
//! // Create a token
//! const token = try jwt.create(allocator, .{
//!     .sub = "user123",
//!     .iss = "my-app",
//!     .aud = "api.myapp.com",
//!     .exp = timestamp + 3600,
//!     .iat = timestamp,
//! }, secret);
//! defer token.deinit();
//!
//! // Verify a token
//! const claims = try jwt.verify(allocator, token_str, secret, .{
//!     .issuer = "my-app",
//!     .audience = "api.myapp.com",
//! });
//! defer claims.deinit();
//! ```

const std = @import("std");
const crypto = @import("../apis/crypto.zig");
const base64 = @import("../utils/base64.zig");
const Date = @import("../bindings/date.zig").Date;

// ============================================================================
// Types and Errors
// ============================================================================

/// JWT-related errors.
pub const JwtError = error{
    /// Signature verification failed.
    InvalidSignature,
    /// Token format is invalid (not 3 parts separated by dots).
    InvalidFormat,
    /// Token has expired (exp claim).
    TokenExpired,
    /// Token is not yet valid (nbf claim).
    TokenNotYetValid,
    /// Issuer claim doesn't match expected value.
    InvalidIssuer,
    /// Audience claim doesn't match expected value.
    InvalidAudience,
    /// Required claim is missing.
    MissingClaim,
    /// JSON parsing failed.
    JsonParseError,
    /// Cryptographic operation failed.
    CryptoError,
    /// Unsupported algorithm.
    UnsupportedAlgorithm,
    /// Memory allocation failed.
    OutOfMemory,
};

/// Supported JWT algorithms.
pub const Algorithm = enum {
    /// HMAC with SHA-256 (symmetric)
    HS256,
    // Future: RS256, ES256

    pub fn toString(self: Algorithm) []const u8 {
        return switch (self) {
            .HS256 => "HS256",
        };
    }

    pub fn fromString(str: []const u8) ?Algorithm {
        if (std.mem.eql(u8, str, "HS256")) return .HS256;
        return null;
    }
};

/// Standard JWT claims.
pub const Claims = struct {
    /// Subject - typically the user ID
    sub: ?[]const u8 = null,
    /// Issuer - who created the token
    iss: ?[]const u8 = null,
    /// Audience - intended recipient
    aud: ?[]const u8 = null,
    /// Expiration time (Unix timestamp)
    exp: ?u64 = null,
    /// Issued at (Unix timestamp)
    iat: ?u64 = null,
    /// Not before (Unix timestamp)
    nbf: ?u64 = null,
    /// JWT ID (unique identifier)
    jti: ?[]const u8 = null,

    // Internal: store allocator for cleanup
    _allocator: ?std.mem.Allocator = null,
    _raw_json: ?[]u8 = null,

    pub fn deinit(self: *const Claims) void {
        if (self._allocator) |alloc| {
            if (self._raw_json) |raw| {
                alloc.free(raw);
            }
        }
    }
};

/// Options for creating a JWT.
pub const CreateOptions = struct {
    /// Algorithm to use (default: HS256)
    algorithm: Algorithm = .HS256,
};

/// Options for verifying a JWT.
pub const VerifyOptions = struct {
    /// Expected issuer (if set, must match `iss` claim)
    issuer: ?[]const u8 = null,
    /// Expected audience (if set, must match `aud` claim)
    audience: ?[]const u8 = null,
    /// Allowed clock skew in seconds (default: 60)
    clockSkew: u64 = 60,
    /// Algorithm to accept (default: HS256)
    algorithm: Algorithm = .HS256,
};

/// A created JWT token.
pub const Token = struct {
    value: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const Token) void {
        self.allocator.free(self.value);
    }

    pub fn toString(self: *const Token) []const u8 {
        return self.value;
    }
};

// ============================================================================
// JWT Creation
// ============================================================================

/// Create a JWT token.
///
/// ## Arguments
///
/// - `allocator`: Memory allocator for the token.
/// - `claims`: The claims to include in the token.
/// - `secret`: The secret key for signing (for HS256).
/// - `options`: Optional creation options.
///
/// ## Returns
///
/// A `Token` containing the JWT string. Caller must call `deinit()` when done.
///
/// ## Example
///
/// ```zig
/// const token = try jwt.create(allocator, .{
///     .sub = "user123",
///     .iss = "my-app",
///     .exp = std.time.timestamp() + 3600,
///     .iat = std.time.timestamp(),
/// }, "my-secret-key", .{});
/// defer token.deinit();
/// ```
pub fn create(
    allocator: std.mem.Allocator,
    claims: Claims,
    secret: []const u8,
    options: CreateOptions,
) JwtError!Token {
    // Build header - currently only HS256 is supported
    // When adding more algorithms, use runtime string building
    const header_json = switch (options.algorithm) {
        .HS256 => "{\"alg\":\"HS256\",\"typ\":\"JWT\"}",
    };

    // Build payload JSON using bufPrint
    var payload_buf: [2048]u8 = undefined;
    var pos: usize = 0;

    payload_buf[pos] = '{';
    pos += 1;

    var first = true;

    // Helper to append string claim
    const appendStrClaim = struct {
        fn f(buf: []u8, p: *usize, name: []const u8, value: []const u8, is_first: *bool) bool {
            const prefix: []const u8 = if (is_first.*) "" else ",";
            const formatted = std.fmt.bufPrint(buf[p.*..], "{s}\"{s}\":\"{s}\"", .{ prefix, name, value }) catch return false;
            p.* += formatted.len;
            is_first.* = false;
            return true;
        }
    }.f;

    // Helper to append numeric claim
    const appendNumClaim = struct {
        fn f(buf: []u8, p: *usize, name: []const u8, value: u64, is_first: *bool) bool {
            const prefix: []const u8 = if (is_first.*) "" else ",";
            const formatted = std.fmt.bufPrint(buf[p.*..], "{s}\"{s}\":{d}", .{ prefix, name, value }) catch return false;
            p.* += formatted.len;
            is_first.* = false;
            return true;
        }
    }.f;

    // Write claims
    if (claims.sub) |sub| {
        if (!appendStrClaim(&payload_buf, &pos, "sub", sub, &first)) return JwtError.OutOfMemory;
    }
    if (claims.iss) |iss| {
        if (!appendStrClaim(&payload_buf, &pos, "iss", iss, &first)) return JwtError.OutOfMemory;
    }
    if (claims.aud) |aud| {
        if (!appendStrClaim(&payload_buf, &pos, "aud", aud, &first)) return JwtError.OutOfMemory;
    }
    if (claims.exp) |exp| {
        if (!appendNumClaim(&payload_buf, &pos, "exp", exp, &first)) return JwtError.OutOfMemory;
    }
    if (claims.iat) |iat| {
        if (!appendNumClaim(&payload_buf, &pos, "iat", iat, &first)) return JwtError.OutOfMemory;
    }
    if (claims.nbf) |nbf| {
        if (!appendNumClaim(&payload_buf, &pos, "nbf", nbf, &first)) return JwtError.OutOfMemory;
    }
    if (claims.jti) |jti| {
        if (!appendStrClaim(&payload_buf, &pos, "jti", jti, &first)) return JwtError.OutOfMemory;
    }

    payload_buf[pos] = '}';
    pos += 1;

    const payload_json = payload_buf[0..pos];

    // Base64url encode header and payload
    var header_b64_buf: [256]u8 = undefined;
    const header_b64 = base64.encodeUrl(&header_b64_buf, header_json);

    var payload_b64_buf: [4096]u8 = undefined;
    const payload_b64 = base64.encodeUrl(&payload_b64_buf, payload_json);

    // Create signing input: header.payload
    const signing_input_len = header_b64.len + 1 + payload_b64.len;
    var signing_input_buf: [8192]u8 = undefined;
    if (signing_input_len > signing_input_buf.len) {
        return JwtError.OutOfMemory;
    }

    var offset: usize = 0;
    @memcpy(signing_input_buf[offset .. offset + header_b64.len], header_b64);
    offset += header_b64.len;
    signing_input_buf[offset] = '.';
    offset += 1;
    @memcpy(signing_input_buf[offset .. offset + payload_b64.len], payload_b64);
    offset += payload_b64.len;

    const signing_input = signing_input_buf[0..offset];

    // Sign with HMAC-SHA256
    const signature = signHmacSha256(signing_input, secret) orelse {
        return JwtError.CryptoError;
    };

    // Base64url encode signature
    var sig_b64_buf: [128]u8 = undefined;
    const sig_b64 = base64.encodeUrl(&sig_b64_buf, signature);

    // Build final token: header.payload.signature
    const token_len = signing_input.len + 1 + sig_b64.len;
    const token_buf = allocator.alloc(u8, token_len) catch {
        return JwtError.OutOfMemory;
    };
    errdefer allocator.free(token_buf);

    offset = 0;
    @memcpy(token_buf[offset .. offset + signing_input.len], signing_input);
    offset += signing_input.len;
    token_buf[offset] = '.';
    offset += 1;
    @memcpy(token_buf[offset .. offset + sig_b64.len], sig_b64);

    return Token{
        .value = token_buf,
        .allocator = allocator,
    };
}

// ============================================================================
// JWT Verification
// ============================================================================

/// Verify a JWT token and return the claims.
///
/// ## Arguments
///
/// - `allocator`: Memory allocator.
/// - `token`: The JWT string to verify.
/// - `secret`: The secret key for verification (for HS256).
/// - `options`: Verification options.
///
/// ## Returns
///
/// The `Claims` from the token. Caller must call `deinit()` when done.
///
/// ## Errors
///
/// - `InvalidSignature`: Signature doesn't match.
/// - `TokenExpired`: Token has expired.
/// - `TokenNotYetValid`: Token's `nbf` claim is in the future.
/// - `InvalidIssuer`: Issuer doesn't match expected.
/// - `InvalidAudience`: Audience doesn't match expected.
///
/// ## Example
///
/// ```zig
/// const claims = try jwt.verify(allocator, token_string, "my-secret", .{
///     .issuer = "my-app",
///     .audience = "api.myapp.com",
/// });
/// defer claims.deinit();
///
/// // Access claims
/// if (claims.sub) |user_id| {
///     // Use user_id
/// }
/// ```
pub fn verify(
    allocator: std.mem.Allocator,
    token: []const u8,
    secret: []const u8,
    options: VerifyOptions,
) JwtError!Claims {
    // Split token into parts
    var parts = std.mem.splitScalar(u8, token, '.');

    const header_b64 = parts.next() orelse return JwtError.InvalidFormat;
    const payload_b64 = parts.next() orelse return JwtError.InvalidFormat;
    const sig_b64 = parts.next() orelse return JwtError.InvalidFormat;

    // Make sure there's no 4th part
    if (parts.next() != null) {
        return JwtError.InvalidFormat;
    }

    // Decode and verify header
    var header_buf: [256]u8 = undefined;
    const header_json = base64.decodeUrl(&header_buf, header_b64) catch {
        return JwtError.InvalidFormat;
    };

    // Parse header to check algorithm
    const alg = extractJsonString(header_json, "alg") orelse {
        return JwtError.InvalidFormat;
    };

    const token_alg = Algorithm.fromString(alg) orelse {
        return JwtError.UnsupportedAlgorithm;
    };

    if (token_alg != options.algorithm) {
        return JwtError.UnsupportedAlgorithm;
    }

    // Verify signature
    const signing_input_len = header_b64.len + 1 + payload_b64.len;
    const signing_input = allocator.alloc(u8, signing_input_len) catch {
        return JwtError.OutOfMemory;
    };
    defer allocator.free(signing_input);

    @memcpy(signing_input[0..header_b64.len], header_b64);
    signing_input[header_b64.len] = '.';
    @memcpy(signing_input[header_b64.len + 1 ..], payload_b64);

    // Decode signature
    var sig_buf: [64]u8 = undefined;
    const signature = base64.decodeUrl(&sig_buf, sig_b64) catch {
        return JwtError.InvalidFormat;
    };

    // Verify HMAC-SHA256
    if (!verifyHmacSha256(signing_input, secret, signature)) {
        return JwtError.InvalidSignature;
    }

    // Decode payload
    const payload_max_size = base64.calcDecodedSizeUrl(payload_b64.len);
    const payload_buf = allocator.alloc(u8, payload_max_size) catch {
        return JwtError.OutOfMemory;
    };
    errdefer allocator.free(payload_buf);

    const payload_json = base64.decodeUrl(payload_buf, payload_b64) catch {
        allocator.free(payload_buf);
        return JwtError.InvalidFormat;
    };

    // Parse claims
    var claims = Claims{
        ._allocator = allocator,
        ._raw_json = payload_buf,
    };

    claims.sub = extractJsonString(payload_json, "sub");
    claims.iss = extractJsonString(payload_json, "iss");
    claims.aud = extractJsonString(payload_json, "aud");
    claims.jti = extractJsonString(payload_json, "jti");
    claims.exp = extractJsonNumber(payload_json, "exp");
    claims.iat = extractJsonNumber(payload_json, "iat");
    claims.nbf = extractJsonNumber(payload_json, "nbf");

    // Validate issuer
    if (options.issuer) |expected_iss| {
        const actual_iss = claims.iss orelse return JwtError.InvalidIssuer;
        if (!std.mem.eql(u8, expected_iss, actual_iss)) {
            return JwtError.InvalidIssuer;
        }
    }

    // Validate audience
    if (options.audience) |expected_aud| {
        const actual_aud = claims.aud orelse return JwtError.InvalidAudience;
        if (!std.mem.eql(u8, expected_aud, actual_aud)) {
            return JwtError.InvalidAudience;
        }
    }

    // Get current time (Unix timestamp)
    const now = getCurrentTimestamp();

    // Validate expiration
    if (claims.exp) |exp| {
        if (now > exp + options.clockSkew) {
            return JwtError.TokenExpired;
        }
    }

    // Validate not-before
    if (claims.nbf) |nbf| {
        if (now + options.clockSkew < nbf) {
            return JwtError.TokenNotYetValid;
        }
    }

    return claims;
}

/// Decode a JWT without verifying the signature.
///
/// **WARNING**: This is for debugging only. Never trust unverified tokens!
///
/// ## Example
///
/// ```zig
/// const claims = try jwt.decode(allocator, token_string);
/// defer claims.deinit();
/// // Claims are NOT verified - do not trust!
/// ```
pub fn decode(allocator: std.mem.Allocator, token: []const u8) JwtError!Claims {
    // Split token into parts
    var parts = std.mem.splitScalar(u8, token, '.');

    _ = parts.next() orelse return JwtError.InvalidFormat; // header
    const payload_b64 = parts.next() orelse return JwtError.InvalidFormat;
    _ = parts.next() orelse return JwtError.InvalidFormat; // signature

    // Decode payload
    const payload_max_size = base64.calcDecodedSizeUrl(payload_b64.len);
    const payload_buf = allocator.alloc(u8, payload_max_size) catch {
        return JwtError.OutOfMemory;
    };
    errdefer allocator.free(payload_buf);

    const payload_json = base64.decodeUrl(payload_buf, payload_b64) catch {
        allocator.free(payload_buf);
        return JwtError.InvalidFormat;
    };

    // Parse claims
    var claims = Claims{
        ._allocator = allocator,
        ._raw_json = payload_buf,
    };

    claims.sub = extractJsonString(payload_json, "sub");
    claims.iss = extractJsonString(payload_json, "iss");
    claims.aud = extractJsonString(payload_json, "aud");
    claims.jti = extractJsonString(payload_json, "jti");
    claims.exp = extractJsonNumber(payload_json, "exp");
    claims.iat = extractJsonNumber(payload_json, "iat");
    claims.nbf = extractJsonNumber(payload_json, "nbf");

    return claims;
}

// ============================================================================
// Internal Helpers
// ============================================================================

/// Sign data with HMAC-SHA256.
fn signHmacSha256(data: []const u8, secret: []const u8) ?[]const u8 {
    const subtle = crypto.SubtleCrypto.get();
    defer subtle.free();

    // Import secret as HMAC key
    const key = subtle.importKey(
        .raw,
        secret,
        &crypto.SubtleCryptoImportKeyAlgorithm{ .name = "HMAC", .hash = "SHA-256" },
        false,
        &.{.sign},
    ) orelse return null;
    defer key.free();

    // Sign
    return subtle.sign(
        &crypto.SubtleCryptoSignAlgorithm{ .name = "HMAC" },
        &key,
        data,
    );
}

/// Verify HMAC-SHA256 signature.
fn verifyHmacSha256(data: []const u8, secret: []const u8, signature: []const u8) bool {
    const subtle = crypto.SubtleCrypto.get();
    defer subtle.free();

    // Import secret as HMAC key
    const key = subtle.importKey(
        .raw,
        secret,
        &crypto.SubtleCryptoImportKeyAlgorithm{ .name = "HMAC", .hash = "SHA-256" },
        false,
        &.{.verify},
    ) orelse return false;
    defer key.free();

    // Verify
    return subtle.verify(
        &crypto.SubtleCryptoSignAlgorithm{ .name = "HMAC" },
        &key,
        signature,
        data,
    );
}

/// Extract a string value from JSON (simple parser).
fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    // Find "key":"value"
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\":\"", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, search) orelse return null;
    const value_start = start_idx + search.len;

    // Find closing quote (handle escaped quotes)
    var i: usize = value_start;
    while (i < json.len) : (i += 1) {
        if (json[i] == '"' and (i == value_start or json[i - 1] != '\\')) {
            return json[value_start..i];
        }
    }

    return null;
}

/// Extract a number value from JSON (simple parser).
fn extractJsonNumber(json: []const u8, key: []const u8) ?u64 {
    // Find "key":number
    var search_buf: [64]u8 = undefined;
    const search = std.fmt.bufPrint(&search_buf, "\"{s}\":", .{key}) catch return null;

    const start_idx = std.mem.indexOf(u8, json, search) orelse return null;
    const value_start = start_idx + search.len;

    // Find end of number (non-digit character)
    var end: usize = value_start;
    while (end < json.len and (json[end] >= '0' and json[end] <= '9')) : (end += 1) {}

    if (end == value_start) return null;

    return std.fmt.parseInt(u64, json[value_start..end], 10) catch null;
}

/// Get current Unix timestamp.
fn getCurrentTimestamp() u64 {
    // Use JavaScript's Date.now() which returns milliseconds since epoch
    const ms = Date.now();
    return @as(u64, @intFromFloat(ms / 1000.0));
}
