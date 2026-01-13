//! OWASP-compliant password hashing using PBKDF2-HMAC-SHA256.
//!
//! This module provides secure password hashing and verification using
//! PBKDF2 with HMAC-SHA256, following OWASP guidelines for 2024.
//!
//! ## Security Features
//!
//! - PBKDF2-HMAC-SHA256 (600,000+ iterations by default)
//! - Random 16-byte salt per password
//! - Timing-safe verification via SubtleCrypto
//! - User-provided weak password list support
//!
//! ## Example
//!
//! ```zig
//! const auth = @import("cf-workerz").auth;
//!
//! // Hash a password
//! const hash = try auth.hashPassword("user-password", .{});
//! defer hash.deinit();
//!
//! // Verify a password
//! const valid = try auth.verifyPassword("user-password", stored_hash);
//!
//! // With weak password check
//! const hash2 = auth.hashPassword("password123", .{
//!     .weakPasswordList = &.{ "password", "123456", "password123" },
//! }) catch |err| switch (err) {
//!     error.WeakPassword => // handle weak password
//! };
//! ```

const std = @import("std");
const crypto = @import("../apis/crypto.zig");
const base64 = @import("../utils/base64.zig");

// ============================================================================
// Types and Constants
// ============================================================================

/// Password hashing errors.
pub const PasswordError = error{
    /// The password is in the weak password list.
    WeakPassword,
    /// The password is too short (minimum 8 characters).
    PasswordTooShort,
    /// The password is too long (maximum 128 characters for DoS prevention).
    PasswordTooLong,
    /// Cryptographic operation failed.
    CryptoError,
    /// Hash format is invalid.
    InvalidHashFormat,
    /// Memory allocation failed.
    OutOfMemory,
};

/// Configuration for password hashing.
pub const PasswordConfig = struct {
    /// Number of PBKDF2 iterations.
    /// OWASP 2024 recommends minimum 600,000 for PBKDF2-HMAC-SHA256.
    iterations: u32 = 600_000,

    /// Length of the derived key in bytes (256 bits = 32 bytes).
    hashLength: u32 = 32,

    /// Length of the random salt in bytes (128 bits = 16 bytes).
    saltLength: u32 = 16,

    /// Minimum password length.
    minLength: u32 = 8,

    /// Maximum password length (DoS prevention).
    maxLength: u32 = 128,

    /// Optional list of weak passwords to reject.
    /// If provided, passwords in this list will return error.WeakPassword.
    weakPasswordList: ?[]const []const u8 = null,
};

/// A hashed password with its components.
/// Format: "base64salt$iterations$base64hash"
pub const HashedPassword = struct {
    /// The full hash string in format "salt$iterations$hash"
    value: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const HashedPassword) void {
        self.allocator.free(self.value);
    }

    /// Get the string value of the hash.
    pub fn toString(self: *const HashedPassword) []const u8 {
        return self.value;
    }
};

// ============================================================================
// Password Hashing
// ============================================================================

/// Hash a password using PBKDF2-HMAC-SHA256.
///
/// Returns a `HashedPassword` containing the hash in format "salt$iterations$hash".
/// The caller must call `deinit()` on the returned value when done.
///
/// ## Errors
///
/// - `error.WeakPassword`: Password is in the weak password list.
/// - `error.PasswordTooShort`: Password is shorter than `config.minLength`.
/// - `error.PasswordTooLong`: Password is longer than `config.maxLength`.
/// - `error.CryptoError`: Cryptographic operation failed.
/// - `error.OutOfMemory`: Memory allocation failed.
///
/// ## Example
///
/// ```zig
/// const hash = try hashPassword(allocator, "my-secure-password", .{});
/// defer hash.deinit();
///
/// // Store hash.toString() in database
/// ```
pub fn hashPassword(
    allocator: std.mem.Allocator,
    password: []const u8,
    config: PasswordConfig,
) PasswordError!HashedPassword {
    // Validate password length
    if (password.len < config.minLength) {
        return PasswordError.PasswordTooShort;
    }
    if (password.len > config.maxLength) {
        return PasswordError.PasswordTooLong;
    }

    // Check against weak password list
    if (config.weakPasswordList) |list| {
        for (list) |weak| {
            if (std.mem.eql(u8, password, weak)) {
                return PasswordError.WeakPassword;
            }
        }
    }

    // Generate random salt
    var salt: [16]u8 = undefined;
    if (config.saltLength <= 16) {
        crypto.getRandomValues(salt[0..config.saltLength]);
    } else {
        crypto.getRandomValues(&salt);
    }
    const salt_slice = salt[0..@min(config.saltLength, 16)];

    // Derive key using PBKDF2
    const derived = deriveKey(password, salt_slice, config.iterations, config.hashLength) orelse {
        return PasswordError.CryptoError;
    };

    // Encode to base64
    const salt_encoded_size = base64.calcEncodedSize(salt_slice.len);
    const hash_encoded_size = base64.calcEncodedSize(derived.len);

    // Format: "salt$iterations$hash"
    // Calculate total size: salt_b64 + "$" + iterations_str + "$" + hash_b64
    var iter_buf: [10]u8 = undefined;
    const iter_str = std.fmt.bufPrint(&iter_buf, "{d}", .{config.iterations}) catch {
        return PasswordError.CryptoError;
    };

    const total_size = salt_encoded_size + 1 + iter_str.len + 1 + hash_encoded_size;

    const result = allocator.alloc(u8, total_size) catch {
        return PasswordError.OutOfMemory;
    };
    errdefer allocator.free(result);

    // Build the hash string
    var offset: usize = 0;

    // Salt (base64)
    const salt_b64 = base64.encode(result[offset..], salt_slice);
    offset += salt_b64.len;

    // Delimiter
    result[offset] = '$';
    offset += 1;

    // Iterations
    @memcpy(result[offset .. offset + iter_str.len], iter_str);
    offset += iter_str.len;

    // Delimiter
    result[offset] = '$';
    offset += 1;

    // Hash (base64)
    _ = base64.encode(result[offset..], derived);

    return HashedPassword{
        .value = result,
        .allocator = allocator,
    };
}

/// Verify a password against a stored hash.
///
/// The stored hash must be in the format "salt$iterations$hash" as produced
/// by `hashPassword()`.
///
/// Uses timing-safe comparison to prevent timing attacks.
///
/// ## Returns
///
/// `true` if the password matches, `false` otherwise.
///
/// ## Errors
///
/// - `error.InvalidHashFormat`: The stored hash is not in the expected format.
/// - `error.CryptoError`: Cryptographic operation failed.
/// - `error.OutOfMemory`: Memory allocation failed.
///
/// ## Example
///
/// ```zig
/// const valid = try verifyPassword(allocator, "user-input", stored_hash);
/// if (valid) {
///     // Password correct
/// } else {
///     // Password incorrect
/// }
/// ```
pub fn verifyPassword(
    allocator: std.mem.Allocator,
    password: []const u8,
    stored_hash: []const u8,
) PasswordError!bool {
    // Parse the stored hash: "salt$iterations$hash"
    var parts = std.mem.splitScalar(u8, stored_hash, '$');

    const salt_b64 = parts.next() orelse return PasswordError.InvalidHashFormat;
    const iter_str = parts.next() orelse return PasswordError.InvalidHashFormat;
    const hash_b64 = parts.next() orelse return PasswordError.InvalidHashFormat;

    // Decode salt
    const salt_max_size = base64.calcDecodedSize(salt_b64.len);
    const salt_buf = allocator.alloc(u8, salt_max_size) catch {
        return PasswordError.OutOfMemory;
    };
    defer allocator.free(salt_buf);

    const salt = base64.decode(salt_buf, salt_b64) catch {
        return PasswordError.InvalidHashFormat;
    };

    // Parse iterations
    const iterations = std.fmt.parseInt(u32, iter_str, 10) catch {
        return PasswordError.InvalidHashFormat;
    };

    // Decode expected hash
    const hash_max_size = base64.calcDecodedSize(hash_b64.len);
    const expected_buf = allocator.alloc(u8, hash_max_size) catch {
        return PasswordError.OutOfMemory;
    };
    defer allocator.free(expected_buf);

    const expected = base64.decode(expected_buf, hash_b64) catch {
        return PasswordError.InvalidHashFormat;
    };

    // Derive key from input password
    const derived = deriveKey(password, salt, iterations, @intCast(expected.len)) orelse {
        return PasswordError.CryptoError;
    };

    // Timing-safe comparison
    return timingSafeEqual(derived, expected);
}

/// Check if a password is in a weak password list.
///
/// This is a convenience function for checking passwords before hashing.
///
/// ## Example
///
/// ```zig
/// const weak_list = &.{ "password", "123456", "qwerty" };
/// if (isWeakPassword("password123", weak_list)) {
///     // Reject the password
/// }
/// ```
pub fn isWeakPassword(password: []const u8, weak_list: []const []const u8) bool {
    for (weak_list) |weak| {
        if (std.mem.eql(u8, password, weak)) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Internal Helpers
// ============================================================================

/// Derive a key using PBKDF2-HMAC-SHA256.
fn deriveKey(
    password: []const u8,
    salt: []const u8,
    iterations: u32,
    length: u32,
) ?[]const u8 {
    const subtle = crypto.SubtleCrypto.get();
    defer subtle.free();

    // Import password as key material
    const keyMaterial = subtle.importKey(
        .raw,
        password,
        &crypto.SubtleCryptoImportKeyAlgorithm{ .name = "PBKDF2" },
        false,
        &.{.deriveBits},
    ) orelse return null;
    defer keyMaterial.free();

    // Derive bits using PBKDF2
    const derived = subtle.deriveBits(
        &crypto.SubtleCryptoDeriveKeyAlgorithm{
            .name = "PBKDF2",
            .salt = salt,
            .iterations = iterations,
            .hash = "SHA-256",
        },
        &keyMaterial,
        length * 8, // length in bits
    ) orelse return null;

    return derived;
}

/// Timing-safe comparison of two byte slices.
fn timingSafeEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }

    const subtle = crypto.SubtleCrypto.get();
    defer subtle.free();

    return subtle.timingSafeEqual(a, b);
}
