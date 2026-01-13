//! cf-workerz Authentication Module
//!
//! OWASP-compliant authentication utilities for Cloudflare Workers.
//!
//! ## Features
//!
//! - **Password Hashing**: PBKDF2-HMAC-SHA256 with 600,000+ iterations
//! - **JWT**: Create and verify tokens with HS256 (RS256/ES256 planned)
//! - **Logging**: Built-in console logging for auth events
//!
//! ## Quick Start
//!
//! ```zig
//! const auth = @import("cf-workerz").auth;
//!
//! // Hash a password
//! const hash = try auth.hashPassword(allocator, "password", .{});
//! defer hash.deinit();
//!
//! // Verify a password
//! const valid = try auth.verifyPassword(allocator, "password", stored);
//!
//! // Create a JWT
//! const token = try auth.jwt.create(allocator, .{
//!     .sub = "user123",
//!     .exp = timestamp + 3600,
//! }, secret, .{});
//! defer token.deinit();
//!
//! // Verify a JWT
//! const claims = try auth.jwt.verify(allocator, token_str, secret, .{
//!     .issuer = "my-app",
//! });
//! defer claims.deinit();
//! ```
//!
//! ## OWASP Compliance
//!
//! This module follows OWASP Top 10:2025 guidelines for:
//!
//! - **A04 Cryptographic Failures**: Uses strong algorithms (PBKDF2, HMAC-SHA256)
//! - **A07 Authentication Failures**: Timing-safe verification, proper validation
//!

// Re-export password hashing
pub const password = @import("password.zig");
pub const PasswordError = password.PasswordError;
pub const PasswordConfig = password.PasswordConfig;
pub const HashedPassword = password.HashedPassword;
pub const hashPassword = password.hashPassword;
pub const verifyPassword = password.verifyPassword;
pub const isWeakPassword = password.isWeakPassword;

// Re-export JWT
pub const jwt = @import("jwt.zig");
pub const JwtError = jwt.JwtError;
pub const Algorithm = jwt.Algorithm;
pub const Claims = jwt.Claims;
pub const Token = jwt.Token;
pub const CreateOptions = jwt.CreateOptions;
pub const VerifyOptions = jwt.VerifyOptions;

// Re-export logging
pub const log = @import("log.zig");
pub const AuthEventType = log.AuthEventType;
pub const LogContext = log.LogContext;
