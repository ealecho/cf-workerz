# Todo API Example

A complete CRUD API demonstrating the unified D1 `run()` API with cf-workerz.

## Features

- Full CRUD operations for todos
- Query parameter filtering
- Path parameters
- JSON body parsing
- Statistics endpoint with aggregate queries
- Demonstrates all D1Result variants: `.rows`, `.command`, `.empty`

## Quick Start

```bash
# Build the Zig WASM module
zig build

# Install dependencies
npm install

# Initialize the local database
npm run setup-db

# Start the development server
npm run dev
```

## API Endpoints

### Health Check
```bash
GET /health
```

### Database Setup
```bash
POST /setup
```
Initializes the database schema (creates the `todos` table).

### List Todos
```bash
GET /todos
GET /todos?completed=true
GET /todos?completed=false
GET /todos?priority=high
GET /todos?completed=false&priority=high
```

### Get Todo
```bash
GET /todos/:id
```

### Create Todo
```bash
POST /todos
Content-Type: application/json

{
  "title": "Learn Zig",
  "description": "Complete the Zig tutorial",
  "priority": "high"
}
```
Priority options: `high`, `medium`, `low` (default: `medium`)

### Update Todo
```bash
PUT /todos/:id
Content-Type: application/json

{
  "title": "Learn Zig",
  "description": "Updated description",
  "priority": "medium",
  "completed": true
}
```

### Toggle Todo
```bash
PATCH /todos/:id/toggle
```
Toggles the completion status of a todo.

### Delete Todo
```bash
DELETE /todos/:id
```

### Delete Completed
```bash
DELETE /todos/completed
```
Deletes all completed todos.

### Get Statistics
```bash
GET /stats
```
Returns:
```json
{
  "total": 10,
  "completed": 3,
  "pending": 7,
  "highPriority": 2,
  "completionRate": 30.0
}
```

## Example Usage

```bash
# Health check
curl http://localhost:8787/health

# Initialize database
curl -X POST http://localhost:8787/setup

# Create a todo
curl -X POST http://localhost:8787/todos \
  -H "Content-Type: application/json" \
  -d '{"title":"Learn Zig","priority":"high"}'

# List all todos
curl http://localhost:8787/todos

# Get a specific todo
curl http://localhost:8787/todos/1

# Toggle completion
curl -X PATCH http://localhost:8787/todos/1/toggle

# Get stats
curl http://localhost:8787/stats

# Delete a todo
curl -X DELETE http://localhost:8787/todos/1
```

## D1 run() API Patterns

This example demonstrates the unified `run()` API:

### SELECT (returns `.rows`)
```zig
var result = db.run(Todo, "SELECT * FROM todos", .{});
defer result.deinit();
switch (result) {
    .rows => |*rows| {
        while (rows.next()) |todo| { /* use todo */ }
    },
    else => {},
}
```

### INSERT (returns `.command`)
```zig
var result = db.run(void, "INSERT INTO todos (title) VALUES (?)", .{title});
defer result.deinit();
switch (result) {
    .command => |cmd| {
        const id = cmd.last_row_id;
        const affected = cmd.changes;
    },
    else => {},
}
```

### Helper Methods
```zig
// Quick checks
if (result.isErr()) { /* handle error */ }
if (result.isOk()) { /* success */ }

// Quick accessors
const affected = result.changes();     // 0 if not .command
const id = result.lastRowId();         // null if not .command
const ms = result.duration();          // 0 if .err
```

## Project Structure

```
examples/todo/
├── build.zig          # Zig build configuration
├── build.zig.zon      # Package dependencies
├── package.json       # NPM scripts and dependencies
├── wrangler.toml      # Cloudflare Workers configuration
├── schema.sql         # Database schema and sample data
├── README.md          # This file
└── src/
    ├── main.zig       # Zig API implementation
    └── index.ts       # TypeScript WASM runtime
```

## License

MIT
