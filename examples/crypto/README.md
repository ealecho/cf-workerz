# Crypto Example

This example demonstrates the SubtleCrypto API in cf-workerz, providing Web Crypto functionality for Cloudflare Workers written in Zig.

## Features

- SHA-256, SHA-1, SHA-512, MD5 hashing
- HMAC signing and verification
- AES-256-GCM key generation
- Random bytes and UUID generation

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | API documentation |
| GET | `/hash/:algorithm?data=...` | Hash query parameter data |
| POST | `/hash/:algorithm` | Hash request body |
| GET | `/random` | Generate 32 random bytes (hex) |
| GET | `/uuid` | Generate a UUID v4 |
| POST | `/hmac/sign` | Sign data with HMAC-SHA256 |
| POST | `/hmac/verify` | Verify HMAC signature |
| GET | `/aes/generate` | Generate AES-256-GCM key |

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

The worker runs at `http://localhost:8790`.

### Deploy

```bash
npx wrangler deploy
```

## Examples

### Hash Data

```bash
# Hash via query parameter
curl "http://localhost:8790/hash/sha256?data=hello%20world"

# Hash via POST body
curl -X POST -d "hello world" http://localhost:8790/hash/sha256

# Other algorithms
curl "http://localhost:8790/hash/sha1?data=test"
curl "http://localhost:8790/hash/sha512?data=test"
curl "http://localhost:8790/hash/md5?data=test"
```

### Random Values

```bash
# Get 32 random bytes (hex encoded)
curl http://localhost:8790/random

# Get a UUID
curl http://localhost:8790/uuid
```

### HMAC Operations

```bash
# Sign data
curl -X POST http://localhost:8790/hmac/sign \
  -H "Content-Type: application/json" \
  -d '{"key": "my-secret-key", "message": "hello world"}'

# Verify signature
curl -X POST http://localhost:8790/hmac/verify \
  -H "Content-Type: application/json" \
  -d '{"key": "my-secret-key", "message": "hello world", "signature": "<hex-signature>"}'
```

### AES Key Generation

```bash
# Generate a new AES-256-GCM key
curl http://localhost:8790/aes/generate
```

## Code Highlights

### Using SubtleCrypto

```zig
const workers = @import("cf-workerz");

fn hashData(ctx: *FetchContext) void {
    const subtle = workers.SubtleCrypto.get();
    defer subtle.free();

    if (subtle.digest(.@"SHA-256", "hello world")) |hash| {
        ctx.bytes(hash, 200);
    }
}
```

### Convenience Functions

```zig
// One-liner hash functions
const hash = workers.sha256("hello world");
const hash1 = workers.sha1("data");
const hash512 = workers.sha512("data");
```

### HMAC Signing

```zig
const subtle = workers.SubtleCrypto.get();
defer subtle.free();

const importAlgo = workers.SubtleCryptoImportKeyAlgorithm{
    .name = "HMAC",
    .hash = .{ .name = "SHA-256" },
};

if (subtle.importKey(.raw, secretKey, &importAlgo, false, &.{.sign})) |key| {
    defer key.free();
    
    const signAlgo = workers.SubtleCryptoSignAlgorithm{ .name = "HMAC" };
    if (subtle.sign(&signAlgo, &key, message)) |signature| {
        // Use signature...
    }
}
```

## Project Structure

```
crypto/
├── build.zig           # Zig build configuration
├── build.zig.zon       # Dependencies
├── package.json        # NPM scripts
├── wrangler.toml       # Cloudflare config
├── src/
│   ├── main.zig        # Worker implementation
│   ├── index.ts        # TypeScript runtime
│   └── wasm.d.ts       # WASM type declarations
└── README.md           # This file
```
