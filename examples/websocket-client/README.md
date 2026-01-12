# WebSocket Client Example

This example demonstrates **outbound WebSocket connections** and event handling with cf-workerz.

## Features

- **Outbound WebSocket connections** using `wsConnect()` and `wsConnectWithProtocols()`
- **WebSocket event types**: `MessageEvent`, `CloseEvent`, `ErrorEvent`
- **WebSocketIncomingMessage** union for handling text/binary messages
- **Inbound WebSocket handling** (server-side upgrade)

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Welcome message with API docs |
| GET | `/ws/echo` | Connect to external echo server |
| GET | `/ws/connect` | Upgrade to WebSocket (inbound) |
| POST | `/ws/send` | Send message via outbound WebSocket |

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

### Connect to Echo Server

```bash
curl http://localhost:8788/ws/echo
```

### Send Message via Outbound WebSocket

```bash
curl -X POST http://localhost:8788/ws/send \
  -H "Content-Type: application/json" \
  -d '{"url": "wss://echo.websocket.org", "message": "Hello!"}'
```

### WebSocket with Subprotocol

```bash
curl -X POST http://localhost:8788/ws/send \
  -H "Content-Type: application/json" \
  -d '{"url": "wss://api.example.com/ws", "message": "{}", "protocol": "graphql-ws"}'
```

## Code Highlights

### Outbound Connection

```zig
const workers = @import("cf-workerz");

fn connectToServer() void {
    // Simple connection
    const ws = workers.wsConnect("wss://echo.websocket.org");
    defer ws.free();
    
    ws.sendText("Hello!");
}
```

### Connection with Subprotocols

```zig
fn connectWithProtocol() void {
    const ws = workers.wsConnectWithProtocols(
        "wss://api.example.com/ws",
        &.{ "graphql-ws", "subscriptions-transport-ws" },
    );
    defer ws.free();
    
    ws.sendText("{\"type\":\"connection_init\"}");
}
```

### Inbound WebSocket (Server)

```zig
fn handleUpgrade(ctx: *FetchContext) void {
    const pair = workers.WebSocketPair.new();
    defer pair.free();
    
    var server = pair.server();
    defer server.free();
    
    server.accept();
    server.sendText("Welcome!");
    
    const client = pair.client();
    defer client.free();
    
    const response = workers.Response.webSocketUpgrade(&client);
    defer response.free();
    ctx.send(&response);
}
```
