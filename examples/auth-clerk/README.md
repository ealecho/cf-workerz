# cf-workerz + Clerk Authentication Example

Production-ready authentication for Cloudflare Workers using [Clerk](https://clerk.com).

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Frontend      │     │   Clerk         │     │  cf-workerz     │
│   (React/etc)   │────▶│   (Auth)        │     │  (Backend)      │
│                 │◀────│                 │     │                 │
└────────┬────────┘     └─────────────────┘     └────────┬────────┘
         │                      │                        │
         │  1. User signs in    │                        │
         │─────────────────────▶│                        │
         │                      │                        │
         │  2. Get JWT token    │                        │
         │◀─────────────────────│                        │
         │                      │                        │
         │  3. Request with JWT (Authorization: Bearer)  │
         │──────────────────────────────────────────────▶│
         │                      │                        │
         │                      │  4. Verify via JWKS    │
         │                      │◀───────────────────────│
         │                      │        (cached)        │
         │                      │                        │
         │  5. Response (authenticated)                  │
         │◀──────────────────────────────────────────────│
```

**Key Points:**
- JWT verification uses Clerk's official `@clerk/backend` SDK
- Verified claims (userId, orgId, etc.) are passed to Zig
- Same pattern used by Stripe, Vercel, and other production companies

## Setup

### 1. Create a Clerk Application

1. Go to [clerk.com](https://clerk.com) and create an account
2. Create a new application
3. Note your **Publishable Key** and **Secret Key** from the API Keys page

### 2. Configure Secrets

```bash
# Set your Clerk secret key (required)
npx wrangler secret put CLERK_SECRET_KEY

# Optional: Set JWT key for networkless verification (faster)
# Find this in Clerk Dashboard > API Keys > Advanced > JWT Public Key
npx wrangler secret put CLERK_JWT_KEY
```

### 3. Update wrangler.toml

Uncomment and set your publishable key:

```toml
[vars]
CLERK_PUBLISHABLE_KEY = "pk_test_..."
```

### 4. Build and Run

```bash
# Install dependencies
npm install

# Build the WASM module
zig build

# Start development server
npm run dev
```

## API Endpoints

### Public Routes

| Endpoint | Description |
|----------|-------------|
| `GET /` | API info and available endpoints |
| `GET /health` | Health check |

### Protected Routes (require valid Clerk session)

| Endpoint | Description |
|----------|-------------|
| `GET /api/me` | Get authenticated user ID |
| `GET /api/profile` | Get user profile |
| `GET /api/dashboard` | Get dashboard data |
| `GET /api/org` | Get organization info |

## Testing

### Without Authentication

```bash
# Public routes work without auth
curl http://localhost:8787/
curl http://localhost:8787/health

# Protected routes return 401
curl http://localhost:8787/api/me
# => {"error":"Unauthorized","message":"Valid Clerk session required..."}
```

### With Authentication

To test authenticated requests, you need a valid Clerk session token:

1. Set up a frontend with Clerk (React, Next.js, etc.)
2. Sign in to get a session token
3. Use the token in your requests:

```bash
# Get your session token from Clerk's useAuth() hook or __session cookie
TOKEN="your-clerk-session-token"

curl http://localhost:8787/api/me \
  -H "Authorization: Bearer $TOKEN"

curl http://localhost:8787/api/profile \
  -H "Authorization: Bearer $TOKEN"

curl http://localhost:8787/api/org \
  -H "Authorization: Bearer $TOKEN"
```

## How It Works

### TypeScript Runtime (src/index.ts)

The TypeScript runtime handles JWT verification using Clerk's SDK:

```typescript
import { verifyToken, createClerkClient } from '@clerk/backend';

// Verify token and extract claims
const claims = await verifyClerkToken(request, env);

// Pass claims to WASM context
context.clerkClaims = claims;
```

### Zig Worker (src/main.zig)

The Zig code accesses verified claims via extern functions:

```zig
// Check if authenticated
if (!isAuthenticated(ctx)) {
    ctx.json(.{ .err = "Unauthorized" }, 401);
    return;
}

// Get verified user ID
const user_id = getUserId(ctx) orelse return;

// Get organization info (if applicable)
const org_id = getOrgId(ctx);
const org_role = getOrgRole(ctx);
```

## Production Considerations

### Networkless Verification

For better performance, use `CLERK_JWT_KEY` for networkless verification:

```bash
npx wrangler secret put CLERK_JWT_KEY
```

This verifies tokens locally without making network requests to Clerk's JWKS endpoint.

### Authorized Parties

In production, configure `authorizedParties` to prevent CSRF attacks:

```typescript
// In src/index.ts
const payload = await verifyToken(token, {
  jwtKey: env.CLERK_JWT_KEY,
  authorizedParties: ['https://your-app.com', 'https://api.your-app.com'],
});
```

### Database Integration

Use D1 to store user data:

```zig
fn handleProfile(ctx: *FetchContext) void {
    const user_id = getUserId(ctx) orelse return;
    
    const db = ctx.env.d1("DB") orelse {
        ctx.throw(500, "Database not configured");
        return;
    };
    defer db.free();
    
    // Query user data by Clerk user ID
    if (db.one(User, "SELECT * FROM users WHERE clerk_id = ?", .{user_id})) |user| {
        ctx.json(.{ .user = user }, 200);
    } else {
        ctx.json(.{ .err = "User not found" }, 404);
    }
}
```

## Security

This example follows Clerk's security best practices:

- **RS256 Algorithm**: Clerk uses asymmetric keys (RSA), not shared secrets
- **JWKS Rotation**: Public keys are fetched from Clerk's JWKS endpoint
- **Session Validation**: Tokens are validated for expiry, signature, and claims
- **Official SDK**: Uses Clerk's maintained `@clerk/backend` package

## Resources

- [Clerk Documentation](https://clerk.com/docs)
- [Manual JWT Verification](https://clerk.com/docs/backend-requests/handling/manual-jwt)
- [Session Tokens](https://clerk.com/docs/backend-requests/resources/session-tokens)
- [cf-workerz Documentation](https://github.com/ealecho/cf-workerz)
