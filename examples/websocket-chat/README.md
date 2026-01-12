# WebSocket Chat Example

Real-time WebSocket chat application using cf-workerz with Durable Objects.

Based on [Upstash's cloudflare-websockets example](https://github.com/upstash/examples/tree/main/examples/cloudflare-websockets), ported to Zig.

## Features

- Real-time bidirectional WebSocket communication
- Message persistence using Durable Object storage
- Message broadcasting to all connected clients
- Chat history on connection (last 20 messages)
- Join/leave notifications
- HTTP API for testing without WebSocket client

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | API documentation |
| GET | `/ws` | WebSocket upgrade for chat |
| GET | `/history` | Get chat history (last 20 messages) |
| POST | `/message` | Send message via HTTP |

## Usage

### Build

```bash
zig build
```

### Install Dependencies

```bash
npm install
```

### Run Locally

```bash
npm run dev
```

### Deploy

```bash
npm run deploy
```

## Production Deployment

Deploy both the worker and client to Cloudflare:

### 1. Deploy the Worker

```bash
cd examples/websocket-chat
npm install
npx wrangler deploy
```

This deploys to `https://websocket-chat.<your-subdomain>.workers.dev`

### 2. Deploy the React Client

```bash
cd examples/websocket-chat/client
npm install

# Create the Pages project (first time only)
npx wrangler pages project create websocket-chat-client --production-branch main

# Set the production WebSocket URL
echo "VITE_WS_URL=wss://websocket-chat.<your-subdomain>.workers.dev/ws" > .env.production

# Build and deploy
npm run build
npx wrangler pages deploy ./dist --project-name websocket-chat-client --branch main
```

This deploys to `https://websocket-chat-client.pages.dev`

### Live Demo

- **Client**: https://websocket-chat-client.pages.dev
- **Worker API**: https://websocket-chat.alaara.workers.dev

## WebSocket Protocol

### Connect

Connect to `ws://localhost:8787/ws` (or your deployed URL).

### Initialize Session

Send your user ID to initialize the session:

```json
{"type": "init", "userId": "your-username"}
```

You'll receive chat history:

```json
{"type": "history", "messages": [...]}
```

### Send Messages

```json
{"type": "message", "content": "Hello, everyone!"}
```

### Receive Messages

All connected clients receive messages in this format:

```json
{"userId": "alice", "message": "Hello!", "timestamp": 1704067200000}
```

### System Messages

Join/leave notifications:

```json
{"type": "system", "message": "alice joined the chat", "timestamp": 1704067200000}
```

## Testing with curl

### Get API Documentation

```bash
curl http://localhost:8787/
```

### Get Chat History

```bash
curl http://localhost:8787/history
```

### Send Message via HTTP

```bash
curl -X POST http://localhost:8787/message \
  -H "Content-Type: application/json" \
  -d '{"userId": "test-user", "content": "Hello from HTTP!"}'
```

## Testing with websocat

```bash
# Install websocat: cargo install websocat
websocat ws://localhost:8787/ws

# Then type:
{"type":"init","userId":"alice"}
{"type":"message","content":"Hello!"}
```

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│   Client    │────▶│  Zig Worker  │────▶│  ChatRoom DO    │
│ (WebSocket) │     │   (Router)   │     │ (TypeScript)    │
└─────────────┘     └──────────────┘     └─────────────────┘
                                                  │
                                                  ▼
                                         ┌───────────────┐
                                         │  DO Storage   │
                                         │  (Messages)   │
                                         └───────────────┘
```

- **Zig Worker**: Routes HTTP requests, handles WebSocket upgrade forwarding
- **ChatRoom DO**: Manages WebSocket connections, broadcasts messages, persists to storage
- **DO Storage**: Stores last 100 messages for history

## React Client

A React + Tailwind CSS client is included for a full chat experience.

### Setup

```bash
# Terminal 1: Run the worker
cd examples/websocket-chat
npm install
npm run dev

# Terminal 2: Run the client
cd examples/websocket-chat/client
npm install
npm run dev
```

The client runs on `http://localhost:3000` and proxies WebSocket connections to the worker on port 8787.

### Configuration

Copy `.env.example` to `.env` to customize the WebSocket URL:

```bash
cp .env.example .env
```

For production, set `VITE_WS_URL` to your deployed worker's WebSocket endpoint.

## Project Structure

```
websocket-chat/
├── build.zig           # Zig build configuration
├── build.zig.zon       # Dependencies
├── package.json        # NPM scripts
├── wrangler.toml       # Cloudflare config with DO bindings
├── src/
│   ├── main.zig        # Zig worker (routing)
│   ├── index.ts        # TypeScript runtime + ChatRoom DO
│   └── wasm.d.ts       # WASM type declarations
├── client/             # React chat client
│   ├── src/
│   │   ├── App.tsx     # Main chat UI component
│   │   ├── hooks/
│   │   │   └── useChat.ts  # WebSocket connection hook
│   │   └── ...
│   ├── package.json
│   └── vite.config.ts
└── README.md           # This file
```

## Differences from Original

| Aspect | Original (TypeScript) | This Port (Zig + TS) |
|--------|----------------------|----------------------|
| Worker Logic | TypeScript | Zig |
| Durable Object | TypeScript | TypeScript |
| Message Storage | Upstash Redis | DO Storage |
| Binary Size | ~100KB+ | ~15KB WASM |

The Durable Object is implemented in TypeScript because it needs to:
1. Maintain WebSocket connections across requests
2. Use native JS WebSocket APIs
3. Handle async storage operations

The main worker routing is in Zig for performance and small binary size.
