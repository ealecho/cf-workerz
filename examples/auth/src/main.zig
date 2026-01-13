//! cf-workerz Auth Example
//!
//! A complete authentication example demonstrating:
//! - User registration with password hashing
//! - User login with JWT token generation
//! - Protected routes with JWT verification
//! - Rate limiting on login attempts
//!
//! ## Endpoints
//!
//! - POST /api/register - Create a new user account
//! - POST /api/login    - Login and get JWT token
//! - GET  /api/me       - Get current user (requires JWT)
//! - GET  /health       - Health check
//!

const std = @import("std");
const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const Route = workers.Router;
const auth = workers.auth;
const Date = workers.Date;

// Page allocator for auth operations
const allocator = std.heap.page_allocator;

// JWT configuration
const JWT_SECRET = "your-256-bit-secret-replace-in-production";
const JWT_ISSUER = "auth-example";
const JWT_AUDIENCE = "api.auth-example.com";
const JWT_EXPIRY_SECONDS: u64 = 3600; // 1 hour

// ============================================================================
// Routes
// ============================================================================

const routes: []const Route = &.{
    Route.get("/health", handleHealth),
    Route.post("/api/register", handleRegister),
    Route.post("/api/login", handleLogin),
    Route.get("/api/me", handleMe),
};

// ============================================================================
// Handlers
// ============================================================================

/// Health check endpoint
fn handleHealth(ctx: *FetchContext) void {
    ctx.json(.{
        .status = "ok",
        .service = "auth-example",
    }, 200);
}

/// Register a new user
/// POST /api/register
/// Body: { "email": "user@example.com", "password": "secure-password" }
fn handleRegister(ctx: *FetchContext) void {
    // Parse request body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .@"error" = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const email = json.getString("email") orelse {
        ctx.json(.{ .@"error" = "Email is required" }, 400);
        return;
    };

    const password = json.getString("password") orelse {
        ctx.json(.{ .@"error" = "Password is required" }, 400);
        return;
    };

    // Validate password strength
    if (password.len < 8) {
        ctx.json(.{ .@"error" = "Password must be at least 8 characters" }, 400);
        return;
    }

    // Hash the password
    const hashed = auth.hashPassword(allocator, password, .{
        .weakPasswordList = &.{
            "password", "12345678", "password123", "qwerty123",
        },
    }) catch |err| {
        switch (err) {
            auth.PasswordError.WeakPassword => {
                ctx.json(.{ .@"error" = "Password is too common. Choose a stronger password." }, 400);
                return;
            },
            auth.PasswordError.PasswordTooShort => {
                ctx.json(.{ .@"error" = "Password must be at least 8 characters" }, 400);
                return;
            },
            else => {
                auth.log.eventSimple(.login_failed, "Password hashing failed");
                ctx.json(.{ .@"error" = "Registration failed" }, 500);
                return;
            },
        }
    };
    defer hashed.deinit();

    // Generate user ID
    const user_id = workers.apis.randomUUID();

    // Get current timestamp from JavaScript Date.now()
    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));

    // Store user in D1 database
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .@"error" = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    _ = db.execute(
        "INSERT INTO users (id, email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        .{ user_id, email, hashed.toString(), now, now },
    );

    auth.log.event(.account_created, email, .{
        .ip = ctx.header("CF-Connecting-IP") orelse "unknown",
        .path = "/api/register",
    });

    ctx.json(.{
        .success = true,
        .message = "User registered successfully",
        .userId = user_id,
    }, 201);
}

/// Login and get JWT token
/// POST /api/login
/// Body: { "email": "user@example.com", "password": "secure-password" }
fn handleLogin(ctx: *FetchContext) void {
    // Rate limit check
    const ip = ctx.header("CF-Connecting-IP") orelse "unknown";

    if (ctx.env.rateLimiter("LOGIN_LIMITER")) |limiter| {
        defer limiter.free();
        if (!limiter.limit(ip).success) {
            auth.log.event(.rate_limited, ip, .{
                .ip = ip,
                .path = "/api/login",
            });
            ctx.json(.{ .@"error" = "Too many login attempts. Try again later." }, 429);
            return;
        }
    }

    // Parse request body
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .@"error" = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const email = json.getString("email") orelse {
        ctx.json(.{ .@"error" = "Email is required" }, 400);
        return;
    };

    const password = json.getString("password") orelse {
        ctx.json(.{ .@"error" = "Password is required" }, 400);
        return;
    };

    // Get user from database
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .@"error" = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    const User = struct {
        id: []const u8,
        email: []const u8,
        password_hash: []const u8,
    };

    const user = db.one(User, "SELECT id, email, password_hash FROM users WHERE email = ?", .{email}) orelse {
        // OWASP: Same error message for user not found
        auth.log.event(.login_failed, "User not found", .{ .ip = ip, .path = "/api/login" });
        ctx.json(.{ .@"error" = "Invalid email or password" }, 401);
        return;
    };

    // Verify password
    const valid = auth.verifyPassword(allocator, password, user.password_hash) catch {
        auth.log.event(.login_failed, "Password verification failed", .{ .ip = ip, .path = "/api/login" });
        ctx.json(.{ .@"error" = "Invalid email or password" }, 401);
        return;
    };

    if (!valid) {
        auth.log.event(.login_failed, email, .{ .ip = ip, .path = "/api/login" });
        ctx.json(.{ .@"error" = "Invalid email or password" }, 401);
        return;
    }

    // Generate JWT token
    const now = @as(u64, @intFromFloat(Date.now() / 1000.0));

    const token = auth.jwt.create(allocator, .{
        .sub = user.id,
        .iss = JWT_ISSUER,
        .aud = JWT_AUDIENCE,
        .exp = now + JWT_EXPIRY_SECONDS,
        .iat = now,
    }, JWT_SECRET, .{}) catch {
        auth.log.event(.login_failed, "Token generation failed", .{ .ip = ip, .path = "/api/login" });
        ctx.json(.{ .@"error" = "Login failed" }, 500);
        return;
    };
    defer token.deinit();

    auth.log.event(.login_success, email, .{ .ip = ip, .path = "/api/login" });

    ctx.json(.{
        .success = true,
        .token = token.toString(),
        .expiresIn = JWT_EXPIRY_SECONDS,
    }, 200);
}

/// Get current user info (protected route)
/// GET /api/me
/// Headers: Authorization: Bearer <token>
fn handleMe(ctx: *FetchContext) void {
    const ip = ctx.header("CF-Connecting-IP") orelse "unknown";

    // Get Authorization header
    const auth_header = ctx.header("Authorization") orelse {
        auth.log.event(.auth_failed, "Missing Authorization header", .{ .ip = ip, .path = "/api/me" });
        ctx.json(.{ .@"error" = "Authorization header required" }, 401);
        return;
    };

    // Extract token (remove "Bearer " prefix)
    const token = if (std.mem.startsWith(u8, auth_header, "Bearer "))
        auth_header[7..]
    else {
        auth.log.event(.auth_failed, "Invalid Authorization format", .{ .ip = ip, .path = "/api/me" });
        ctx.json(.{ .@"error" = "Invalid Authorization format. Use: Bearer <token>" }, 401);
        return;
    };

    // Verify JWT
    const claims = auth.jwt.verify(allocator, token, JWT_SECRET, .{
        .issuer = JWT_ISSUER,
        .audience = JWT_AUDIENCE,
    }) catch |err| {
        const err_msg = switch (err) {
            auth.JwtError.TokenExpired => "Token expired",
            auth.JwtError.InvalidSignature => "Invalid token",
            auth.JwtError.InvalidIssuer => "Invalid issuer",
            auth.JwtError.InvalidAudience => "Invalid audience",
            else => "Token verification failed",
        };
        auth.log.event(.auth_failed, err_msg, .{ .ip = ip, .path = "/api/me" });
        ctx.json(.{ .@"error" = err_msg }, 401);
        return;
    };
    defer claims.deinit();

    const user_id = claims.sub orelse {
        ctx.json(.{ .@"error" = "Invalid token claims" }, 401);
        return;
    };

    // Get user from database
    const db = ctx.env.d1("DB") orelse {
        ctx.json(.{ .@"error" = "Database not configured" }, 500);
        return;
    };
    defer db.free();

    const User = struct {
        id: []const u8,
        email: []const u8,
        created_at: u64,
    };

    const user = db.one(User, "SELECT id, email, created_at FROM users WHERE id = ?", .{user_id}) orelse {
        ctx.json(.{ .@"error" = "User not found" }, 404);
        return;
    };

    auth.log.event(.auth_success, user.email, .{ .ip = ip, .path = "/api/me" });

    ctx.json(.{
        .id = user.id,
        .email = user.email,
        .createdAt = user.created_at,
    }, 200);
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
