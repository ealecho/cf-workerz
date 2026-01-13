//! Authentication event logging.
//!
//! Provides simple console-based logging for authentication events
//! including login attempts, failures, and rate limiting.
//!
//! This module uses JavaScript console.log for WASM compatibility.
//!
//! ## Example
//!
//! ```zig
//! const auth = @import("cf-workerz").auth;
//!
//! // Log a successful login
//! auth.log.event(.login_success, "user@example.com", .{
//!     .ip = ctx.header("CF-Connecting-IP") orelse "unknown",
//!     .path = "/api/login",
//! });
//!
//! // Log a failed login with minimal context
//! auth.log.eventSimple(.login_failed, "Invalid password");
//! ```

const std = @import("std");
const String = @import("../bindings/string.zig").String;
const jsLog = @import("../bindings/common.zig").jsLog;

/// Authentication event types.
pub const AuthEventType = enum {
    /// Successful login
    login_success,
    /// Failed login attempt
    login_failed,
    /// Successful token verification
    auth_success,
    /// Failed token verification
    auth_failed,
    /// Request was rate limited
    rate_limited,
    /// Rate limiter configuration error
    rate_limit_error,
    /// Password was changed
    password_changed,
    /// User logged out
    logout,
    /// Account created
    account_created,
    /// Account locked (too many failures)
    account_locked,

    pub fn toString(self: AuthEventType) []const u8 {
        return switch (self) {
            .login_success => "LOGIN_SUCCESS",
            .login_failed => "LOGIN_FAILED",
            .auth_success => "AUTH_SUCCESS",
            .auth_failed => "AUTH_FAILED",
            .rate_limited => "RATE_LIMITED",
            .rate_limit_error => "RATE_LIMIT_ERROR",
            .password_changed => "PASSWORD_CHANGED",
            .logout => "LOGOUT",
            .account_created => "ACCOUNT_CREATED",
            .account_locked => "ACCOUNT_LOCKED",
        };
    }

    pub fn severity(self: AuthEventType) []const u8 {
        return switch (self) {
            .login_success, .auth_success, .logout, .account_created, .password_changed => "INFO",
            .login_failed, .auth_failed, .rate_limited => "WARN",
            .rate_limit_error, .account_locked => "ERROR",
        };
    }
};

/// Log context information extracted from a request.
pub const LogContext = struct {
    /// Client IP address
    ip: []const u8 = "unknown",
    /// User agent string
    userAgent: []const u8 = "unknown",
    /// Request path
    path: []const u8 = "unknown",
    /// Request method
    method: []const u8 = "unknown",
};

/// Log an authentication event to the JavaScript console.
///
/// Output format:
/// `[AUTH] <severity> <event> | <message> | ip=<ip> | path=<path>`
///
/// ## Arguments
///
/// - `event_type`: The type of authentication event.
/// - `message`: A descriptive message (e.g., user email, error details).
/// - `context`: Optional context from the request.
///
/// ## Example
///
/// ```zig
/// auth.log.event(.login_failed, "user@example.com", .{
///     .ip = "203.0.113.50",
///     .path = "/api/login",
/// });
/// // Output: [AUTH] WARN LOGIN_FAILED | user@example.com | ip=203.0.113.50 | path=/api/login
/// ```
pub fn event(
    event_type: AuthEventType,
    message: []const u8,
    context: LogContext,
) void {
    // Format: [AUTH] SEVERITY EVENT | message | ip=x | path=y
    var buf: [1024]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "[AUTH] {s} {s} | {s} | ip={s} | path={s}", .{
        event_type.severity(),
        event_type.toString(),
        message,
        context.ip,
        context.path,
    }) catch {
        // Fallback to simple message
        const simple = String.new("[AUTH] event logging error");
        defer simple.free();
        jsLog(simple.id);
        return;
    };

    const str = String.new(formatted);
    defer str.free();
    jsLog(str.id);
}

/// Log an authentication event with minimal context.
///
/// Use this when you don't have access to request context.
pub fn eventSimple(event_type: AuthEventType, message: []const u8) void {
    var buf: [512]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "[AUTH] {s} {s} | {s}", .{
        event_type.severity(),
        event_type.toString(),
        message,
    }) catch {
        const simple = String.new("[AUTH] event logging error");
        defer simple.free();
        jsLog(simple.id);
        return;
    };

    const str = String.new(formatted);
    defer str.free();
    jsLog(str.id);
}

/// Log a simple text message to the JavaScript console.
pub fn logMessage(message: []const u8) void {
    const str = String.new(message);
    defer str.free();
    jsLog(str.id);
}
