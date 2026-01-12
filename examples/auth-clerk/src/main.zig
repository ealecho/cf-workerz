//! cf-workerz + Clerk Authentication Example
//!
//! This example demonstrates production-ready authentication using Clerk.
//! JWT verification is handled by the TypeScript runtime using Clerk's
//! official SDK, and verified claims are passed to Zig for business logic.
//!
//! Architecture:
//! 1. Request arrives at Cloudflare Worker
//! 2. TypeScript runtime verifies JWT using @clerk/backend
//! 3. Verified claims (userId, orgId, etc.) are passed to WASM
//! 4. Zig handles business logic with trusted user identity
//!
//! This is the same pattern used by production companies like Stripe, Vercel, etc.

const std = @import("std");
const workers = @import("cf-workerz");
const FetchContext = workers.FetchContext;
const Route = workers.Router;
const Middleware = workers.Middleware;

// ============================================================================
// External Functions - Clerk claims access (implemented in TypeScript runtime)
// ============================================================================

extern "env" fn jsClerkGetUserId(ctx_id: u32) u32;
extern "env" fn jsClerkGetSessionId(ctx_id: u32) u32;
extern "env" fn jsClerkGetOrgId(ctx_id: u32) u32;
extern "env" fn jsClerkGetOrgRole(ctx_id: u32) u32;
extern "env" fn jsClerkGetOrgSlug(ctx_id: u32) u32;
extern "env" fn jsClerkIsAuthenticated(ctx_id: u32) u32;

// ============================================================================
// Clerk Helper Functions
// ============================================================================

/// Check if the current request is authenticated (has valid Clerk session)
fn isAuthenticated(ctx: *FetchContext) bool {
    const result = jsClerkIsAuthenticated(ctx.id);
    // Result is a heap pointer to a boolean
    return result == 3; // ReservedHeapPtr.TRUE = 3
}

/// Get the authenticated user's ID, or null if not authenticated
fn getUserId(ctx: *FetchContext) ?[]const u8 {
    const ptr = jsClerkGetUserId(ctx.id);
    if (ptr == 0) return null;
    return workers.String.init(ptr).value();
}

/// Get the authenticated session ID, or null if not authenticated
fn getSessionId(ctx: *FetchContext) ?[]const u8 {
    const ptr = jsClerkGetSessionId(ctx.id);
    if (ptr == 0) return null;
    return workers.String.init(ptr).value();
}

/// Get the active organization ID, or null if not in an org
fn getOrgId(ctx: *FetchContext) ?[]const u8 {
    const ptr = jsClerkGetOrgId(ctx.id);
    if (ptr == 0) return null;
    return workers.String.init(ptr).value();
}

/// Get the user's role in the active organization
fn getOrgRole(ctx: *FetchContext) ?[]const u8 {
    const ptr = jsClerkGetOrgRole(ctx.id);
    if (ptr == 0) return null;
    return workers.String.init(ptr).value();
}

/// Get the active organization's slug
fn getOrgSlug(ctx: *FetchContext) ?[]const u8 {
    const ptr = jsClerkGetOrgSlug(ctx.id);
    if (ptr == 0) return null;
    return workers.String.init(ptr).value();
}

// ============================================================================
// Routes
// ============================================================================

const routes: []const Route = &.{
    // Public routes - no authentication required
    Route.get("/", handleRoot),
    Route.get("/health", handleHealth),

    // Protected routes - require authentication
    Route.group("/api", &.{
        Route.get("/me", handleMe),
        Route.get("/profile", handleProfile),
        Route.get("/dashboard", handleDashboard),
        Route.get("/org", handleOrg),
    }),
};

// ============================================================================
// Middleware
// ============================================================================

/// CORS middleware - handles preflight and adds headers
fn corsMiddleware(ctx: *FetchContext) bool {
    if (ctx.method() == .Options) {
        const headers = workers.Headers.new();
        defer headers.free();
        headers.setText("Access-Control-Allow-Origin", "*");
        headers.setText("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
        headers.setText("Access-Control-Allow-Headers", "Content-Type, Authorization");
        headers.setText("Access-Control-Max-Age", "86400");

        const res = workers.Response.new(
            .{ .none = {} },
            .{ .status = 204, .statusText = "No Content", .headers = &headers },
        );
        defer res.free();
        ctx.send(&res);
        return false;
    }
    return true;
}

/// Authentication middleware - protects /api/* routes
/// Returns 401 if not authenticated
fn authMiddleware(ctx: *FetchContext) bool {
    // Only require auth for /api/* routes
    if (ctx.path.len >= 4 and std.mem.eql(u8, ctx.path[0..4], "/api")) {
        if (!isAuthenticated(ctx)) {
            ctx.json(.{
                .err = "Unauthorized",
                .message = "Valid Clerk session required. Include Authorization: Bearer <token> header.",
            }, 401);
            return false;
        }
    }

    return true;
}

const middleware = Middleware{
    .before = &.{ corsMiddleware, authMiddleware },
    .after = &.{},
};

// ============================================================================
// Public Route Handlers
// ============================================================================

fn handleRoot(ctx: *FetchContext) void {
    ctx.json(.{
        .name = "cf-workerz + Clerk Auth Example",
        .version = "1.0.0",
        .description = "Production-ready authentication using Clerk",
        .endpoints = .{
            .public = .{
                .@"GET /" = "This info",
                .@"GET /health" = "Health check",
            },
            .protected = .{
                .@"GET /api/me" = "Get authenticated user ID",
                .@"GET /api/profile" = "Get user profile",
                .@"GET /api/dashboard" = "Get dashboard data",
                .@"GET /api/org" = "Get organization info",
            },
        },
        .auth = .{
            .provider = "Clerk",
            .docs = "https://clerk.com/docs",
            .header = "Authorization: Bearer <your-clerk-session-token>",
        },
    }, 200);
}

fn handleHealth(ctx: *FetchContext) void {
    ctx.json(.{
        .status = "healthy",
        .auth = "Clerk",
        .timestamp = "2024-01-01T00:00:00Z",
    }, 200);
}

// ============================================================================
// Protected Route Handlers (require authentication)
// ============================================================================

/// Simple endpoint to get the authenticated user's ID
fn handleMe(ctx: *FetchContext) void {
    const user_id = getUserId(ctx) orelse {
        ctx.json(.{ .err = "User ID not found" }, 500);
        return;
    };

    ctx.json(.{
        .user_id = user_id,
        .authenticated = true,
    }, 200);
}

/// Get user profile - demonstrates accessing Clerk claims
fn handleProfile(ctx: *FetchContext) void {
    const user_id = getUserId(ctx) orelse {
        ctx.json(.{ .err = "User ID not found" }, 500);
        return;
    };

    const session_id = getSessionId(ctx);

    ctx.json(.{
        .user_id = user_id,
        .session_id = session_id,
        .message = "Profile data would be fetched from your database using the user_id",
        .note = "In production, use ctx.env.d1() to query user data",
    }, 200);
}

/// Dashboard endpoint - example of protected business logic
fn handleDashboard(ctx: *FetchContext) void {
    const user_id = getUserId(ctx) orelse {
        ctx.json(.{ .err = "User ID not found" }, 500);
        return;
    };

    // In production, you'd fetch this from D1/KV based on user_id
    ctx.json(.{
        .user_id = user_id,
        .stats = .{
            .projects = 5,
            .api_calls_today = 1234,
            .storage_used_mb = 256,
        },
        .recent_activity = .{
            .last_login = "2024-01-01T12:00:00Z",
            .last_action = "Updated project settings",
        },
    }, 200);
}

/// Organization endpoint - demonstrates Clerk organization claims
fn handleOrg(ctx: *FetchContext) void {
    const user_id = getUserId(ctx) orelse {
        ctx.json(.{ .err = "User ID not found" }, 500);
        return;
    };

    const org_id = getOrgId(ctx);
    const org_role = getOrgRole(ctx);
    const org_slug = getOrgSlug(ctx);

    if (org_id == null) {
        ctx.json(.{
            .user_id = user_id,
            .organization = null,
            .message = "User is not part of an organization or no org is active",
        }, 200);
        return;
    }

    ctx.json(.{
        .user_id = user_id,
        .organization = .{
            .id = org_id,
            .role = org_role,
            .slug = org_slug,
        },
        .permissions = .{
            .is_admin = if (org_role) |r| std.mem.eql(u8, r, "org:admin") else false,
        },
    }, 200);
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatchWithMiddleware(routes, ctx, middleware);
}
