# Hello World Example

A comprehensive example demonstrating cf-workerz features:

- **Built-in Router** - Path parameters, route groups
- **Ergonomic D1 API** - `query()`, `one()`, `execute()` with struct mapping
- **JsonBody** - Parse JSON request bodies with typed getters
- **Struct Serialization** - `ctx.json()` auto-serializes Zig structs

## Quick Start

```bash
# Build WASM
zig build

# Run locally
npx wrangler@latest dev --port 8787
```

## Endpoints

### Basic Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Welcome message with feature list |
| GET | `/hello/:name` | Personalized greeting |
| GET | `/health` | Health check |
| POST | `/echo` | Echo JSON body back |

### D1 Database Routes

| Method | Path | Description |
|--------|------|-------------|
| POST | `/setup` | Create users table |
| GET | `/users` | List all users |
| GET | `/users/:id` | Get single user |
| POST | `/users` | Create user |
| DELETE | `/users/:id` | Delete user |

## Test the API

```bash
# Welcome message
curl http://localhost:8787/

# Personalized greeting
curl http://localhost:8787/hello/Zig

# Health check
curl http://localhost:8787/health

# Echo JSON body
curl -X POST http://localhost:8787/echo \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello","count":42,"enabled":true}'

# Setup D1 (requires D1 binding in wrangler.toml)
curl -X POST http://localhost:8787/setup

# Create user
curl -X POST http://localhost:8787/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice","email":"alice@example.com"}'

# Get user
curl http://localhost:8787/users/1

# Delete user
curl -X DELETE http://localhost:8787/users/1
```

## D1 Setup

To use the D1 endpoints, create a database:

```bash
# Create the database
npx wrangler d1 create hello-world-db

# Update wrangler.toml with the database_id from the output
```

## Key Features Demonstrated

### Ergonomic D1 API

```zig
// Define struct for result mapping
const User = struct { id: u32, name: []const u8, email: []const u8 };

// Query multiple rows
var users = db.query(User, "SELECT * FROM users WHERE active = ?", .{true});
defer users.deinit();
while (users.next()) |user| {
    // user.id, user.name, user.email - fully typed!
}

// Query single row
const user = db.one(User, "SELECT * FROM users WHERE id = ?", .{123});

// Execute INSERT/UPDATE/DELETE
const affected = db.execute("DELETE FROM users WHERE id = ?", .{id});
```

### JsonBody Parsing

```zig
var json = ctx.bodyJson() orelse {
    ctx.json(.{ .err = "Invalid JSON" }, 400);
    return;
};
defer json.deinit();

const name = json.getString("name") orelse "default";
const count = json.getIntOr("count", i32, 0);
const enabled = json.getBoolOr("enabled", false);
```

### Struct Serialization

```zig
// Anonymous struct
ctx.json(.{ .message = "Hello", .count = 42 }, 200);

// Named struct
const Response = struct { status: []const u8, code: u32 };
ctx.json(Response{ .status = "ok", .code = 200 }, 200);
```

## WASM Size

```bash
$ ls -la zig-out/bin/worker.wasm
-rwxr-xr-x  1 user  staff  82000  worker.wasm  # ~80KB (includes std.fmt, std.json)
```

Note: Size increases when using `std.fmt` and JSON parsing. Minimal workers without these features are ~10-15KB.
