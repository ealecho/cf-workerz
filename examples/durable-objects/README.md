# Durable Objects Example

This example demonstrates **advanced Durable Objects features** with cf-workerz, including location hints, alarm scheduling, and SQL storage.

## Features

- **Location hints** for latency optimization (`getWithLocationHint()`, `getStubForId()`)
- **Alarm scheduling** with `ScheduledTime` helper
- **Alarm options**: `allowConcurrency`, `allowUnconfirmed`
- **SQL Storage** (SQLite-backed storage) with `SqlStorage` and `SqlCursor`
- **State methods**: `waitUntil()`, `getTags()`, WebSocket auto-response

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Welcome message with API docs |
| POST | `/do/create` | Create DO with location hint |
| GET | `/do/:name/fetch` | Fetch from Durable Object |
| POST | `/do/:name/alarm` | Schedule an alarm |
| POST | `/do/:name/sql` | Execute SQL query |
| GET | `/do/:name/sql/list` | List SQL tables |

## Quick Start

```bash
# Build the WASM module
zig build

# Run locally
npm run dev

# Deploy to Cloudflare
npm run deploy
```

## Usage Examples

### Create DO with Location Hint

```bash
curl -X POST http://localhost:8789/do/create \
  -H "Content-Type: application/json" \
  -d '{"name": "my-counter", "locationHint": "enam"}'
```

### Fetch from Durable Object

```bash
curl http://localhost:8789/do/my-counter/fetch
```

### Schedule an Alarm

```bash
# Schedule alarm 30 seconds from now
curl -X POST http://localhost:8789/do/my-counter/alarm \
  -H "Content-Type: application/json" \
  -d '{"offsetType": "seconds", "offset": 30}'

# Schedule alarm 5 minutes from now
curl -X POST http://localhost:8789/do/my-counter/alarm \
  -H "Content-Type: application/json" \
  -d '{"offsetType": "minutes", "offset": 5}'
```

### Execute SQL Query

```bash
curl -X POST http://localhost:8789/do/my-counter/sql \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT * FROM users"}'
```

## Location Hint Values

| Hint | Region |
|------|--------|
| `wnam` | Western North America |
| `enam` | Eastern North America |
| `sam` | South America |
| `weur` | Western Europe |
| `eeur` | Eastern Europe |
| `apac` | Asia Pacific |
| `oc` | Oceania |
| `afr` | Africa |
| `me` | Middle East |

## Code Highlights

### Location Hints

```zig
const workers = @import("cf-workerz");

fn useDOWithHint(ctx: *FetchContext) void {
    const namespace = ctx.env.durableObject("MY_DO") orelse return;
    defer namespace.free();
    
    // Get stub with location hint
    const stub = namespace.getWithLocationHint("user:123", "enam");
    defer stub.free();
    
    const response = stub.fetch(.{ .text = "https://do/action" }, null);
    defer response.free();
}
```

### ScheduledTime Helper

```zig
fn scheduleAlarm() void {
    // Create scheduled times
    const inSeconds = workers.ScheduledTime.fromOffsetSecs(30);
    const inMinutes = workers.ScheduledTime.fromOffsetMins(5);
    const inHours = workers.ScheduledTime.fromOffsetHours(1);
    
    // Convert to timestamp
    const timestamp = inSeconds.toTimestamp();
    
    // Use with storage
    storage.setAlarmWithOptions(timestamp, .{
        .allowConcurrency = true,
        .allowUnconfirmed = false,
    });
}
```

### SQL Storage

```zig
fn useSqlStorage(state: *workers.DurableObjectState) void {
    const storage = state.storage();
    defer storage.free();
    
    const sql = storage.sql();
    defer sql.free();
    
    // Execute queries
    sql.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)");
    
    var cursor = sql.exec("SELECT * FROM users");
    defer cursor.free();
    
    while (cursor.next()) |row| {
        defer row.free();
        // Process row
    }
}
```

## Configuration

The `wrangler.toml` includes Durable Objects binding:

```toml
[[durable_objects.bindings]]
name = "COUNTER"
class_name = "Counter"

[[migrations]]
tag = "v1"
new_classes = ["Counter"]
```
