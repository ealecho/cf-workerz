//! Rate Limiting API for Cloudflare Workers.
//!
//! The Rate Limiting API lets you define rate limits and enforce them
//! directly from your Worker. Limits are applied per Cloudflare location.
//!
//! ## Example
//!
//! ```zig
//! const limiter = ctx.env.rateLimiter("MY_RATE_LIMITER") orelse return;
//! defer limiter.free();
//!
//! const outcome = limiter.limit("user:123");
//! if (!outcome.success) {
//!     ctx.json(.{ .error = "Rate limit exceeded" }, 429);
//!     return;
//! }
//! ```
//!
//! ## Configuration
//!
//! ```toml
//! [[ratelimits]]
//! name = "MY_RATE_LIMITER"
//! namespace_id = "1001"
//! simple = { limit = 100, period = 60 }
//! ```
//!
//! ## Key Selection
//!
//! The key you pass to `limit()` should uniquely identify the actor
//! you want to rate limit:
//!
//! - User IDs or API keys (recommended)
//! - Specific API routes or resources
//! - Combination of user + resource
//!
//! Avoid using IP addresses as keys since many users may share an IP.
//!
//! ## Locality
//!
//! Rate limits are enforced per Cloudflare location. A user hitting
//! your worker from Sydney has a separate limit from one in London.

const std = @import("std");
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;

// JS imports for rate limiting
extern "env" fn js_rate_limiter_limit(limiter_ptr: u32, key_ptr: u32, key_len: u32) u32;

/// Outcome of a rate limit check.
pub const RateLimitOutcome = struct {
    /// Whether the request is allowed (within rate limit).
    /// `true` means the request is within the limit.
    /// `false` means the rate limit has been exceeded.
    success: bool,
};

/// A Rate Limiter binding for enforcing rate limits.
///
/// Rate limiters are configured in `wrangler.toml` and accessed via
/// `ctx.env.rateLimiter("BINDING_NAME")`.
///
/// ## Key Selection
///
/// The key you pass to `limit()` should uniquely identify the actor
/// you want to rate limit:
///
/// - User IDs or API keys (recommended)
/// - Specific API routes or resources
/// - Combination of user + resource
///
/// Avoid using IP addresses as keys since many users may share an IP.
///
/// ## Locality
///
/// Rate limits are enforced per Cloudflare location. A user hitting
/// your worker from Sydney has a separate limit from one in London.
///
/// ## Performance
///
/// The Rate Limiting API is designed to be fast. Counters are cached
/// locally and updated asynchronously, so calls to `limit()` don't
/// introduce meaningful latency.
///
/// ## Example
///
/// ```zig
/// fn handleRequest(ctx: *FetchContext) void {
///     const limiter = ctx.env.rateLimiter("API_LIMITER") orelse {
///         ctx.throw(500, "Rate limiter not configured");
///         return;
///     };
///     defer limiter.free();
///
///     const user_id = ctx.header("X-User-ID") orelse "anonymous";
///     const outcome = limiter.limit(user_id);
///
///     if (!outcome.success) {
///         ctx.json(.{ .error = "Rate limit exceeded" }, 429);
///         return;
///     }
///
///     ctx.json(.{ .message = "Success!" }, 200);
/// }
/// ```
pub const RateLimiter = struct {
    handle: u32,

    /// Initialize a RateLimiter from a JS heap pointer.
    /// This is called internally by `Env.rateLimiter()`.
    pub fn init(ptr: u32) RateLimiter {
        return RateLimiter{ .handle = ptr };
    }

    /// Free the rate limiter handle.
    /// Always call this when done with the rate limiter.
    pub fn free(self: *const RateLimiter) void {
        jsFree(self.handle);
    }

    /// Check and increment the rate limit for a given key.
    ///
    /// Returns `RateLimitOutcome` with `success = true` if the request
    /// is within the rate limit, or `success = false` if the limit
    /// has been exceeded.
    ///
    /// ## Parameters
    ///
    /// - `key`: A string identifying what to rate limit. Common choices:
    ///   - User ID: `"user:123"`
    ///   - API key: `"apikey:abc123"`
    ///   - User + route: `"user:123:/api/expensive"`
    ///
    /// ## Example
    ///
    /// ```zig
    /// const limiter = ctx.env.rateLimiter("API_LIMITER") orelse return;
    /// defer limiter.free();
    ///
    /// const user_id = getUserId(ctx);
    /// const outcome = limiter.limit(user_id);
    ///
    /// if (!outcome.success) {
    ///     ctx.json(.{ .error = "Too many requests" }, 429);
    ///     return;
    /// }
    ///
    /// // Process request...
    /// ```
    pub fn limit(self: *const RateLimiter, key: []const u8) RateLimitOutcome {
        const result = js_rate_limiter_limit(self.handle, @intFromPtr(key.ptr), key.len);
        return RateLimitOutcome{
            .success = result == 1,
        };
    }
};
