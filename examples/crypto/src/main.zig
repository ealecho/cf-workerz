const std = @import("std");
const workers = @import("cf-workerz");

const FetchContext = workers.FetchContext;
const Route = workers.Router;
const SubtleCrypto = workers.SubtleCrypto;

// ============================================================================
// Routes
// ============================================================================

const routes: []const Route = &.{
    Route.get("/", handleRoot),
    Route.get("/hash/:algorithm", handleHash),
    Route.post("/hash/:algorithm", handleHashPost),
    Route.get("/random", handleRandom),
    Route.get("/uuid", handleUUID),
    Route.post("/hmac/sign", handleHmacSign),
    Route.post("/hmac/verify", handleHmacVerify),
    Route.get("/aes/generate", handleAesGenerate),
};

// ============================================================================
// Handlers
// ============================================================================

fn handleRoot(ctx: *FetchContext) void {
    ctx.json(.{
        .name = "cf-workerz Crypto Example",
        .endpoints = .{
            .@"GET /hash/:algorithm?data=..." = "Hash data using SHA-1, SHA-256, SHA-384, SHA-512, or MD5",
            .@"POST /hash/:algorithm" = "Hash request body",
            .@"GET /random" = "Generate 32 random bytes (hex)",
            .@"GET /uuid" = "Generate a random UUID",
            .@"POST /hmac/sign" = "Sign data with HMAC-SHA256",
            .@"POST /hmac/verify" = "Verify HMAC signature",
            .@"GET /aes/generate" = "Generate AES-256-GCM key",
        },
    }, 200);
}

fn handleHash(ctx: *FetchContext) void {
    const algorithm = ctx.param("algorithm") orelse {
        ctx.json(.{ .err = "Missing algorithm parameter" }, 400);
        return;
    };

    // Get data from query parameter
    const params = ctx.query();
    defer params.free();
    const data = params.get("data") orelse {
        ctx.json(.{ .err = "Missing 'data' query parameter" }, 400);
        return;
    };

    // Determine algorithm
    const algo = parseAlgorithm(algorithm) orelse {
        ctx.json(.{ .err = "Invalid algorithm. Use: sha1, sha256, sha384, sha512, or md5" }, 400);
        return;
    };

    // Compute hash
    const subtle = SubtleCrypto.get();
    defer subtle.free();

    if (subtle.digest(algo, data)) |hash| {
        const hex = bytesToHex(hash);
        ctx.json(.{
            .algorithm = algorithm,
            .input = data,
            .hash = hex,
        }, 200);
    } else {
        ctx.json(.{ .err = "Failed to compute hash" }, 500);
    }
}

fn handleHashPost(ctx: *FetchContext) void {
    const algorithm = ctx.param("algorithm") orelse {
        ctx.json(.{ .err = "Missing algorithm parameter" }, 400);
        return;
    };

    // Get body text
    const body = ctx.req.text() orelse {
        ctx.json(.{ .err = "Failed to read request body" }, 400);
        return;
    };

    // Determine algorithm
    const algo = parseAlgorithm(algorithm) orelse {
        ctx.json(.{ .err = "Invalid algorithm. Use: sha1, sha256, sha384, sha512, or md5" }, 400);
        return;
    };

    // Compute hash
    const subtle = SubtleCrypto.get();
    defer subtle.free();

    if (subtle.digest(algo, body)) |hash| {
        const hex = bytesToHex(hash);
        ctx.json(.{
            .algorithm = algorithm,
            .hash = hex,
            .length = hash.len,
        }, 200);
    } else {
        ctx.json(.{ .err = "Failed to compute hash" }, 500);
    }
}

fn handleRandom(ctx: *FetchContext) void {
    var buffer: [32]u8 = undefined;
    workers.getRandomValues(&buffer);

    const hex = bytesToHex(&buffer);
    ctx.json(.{
        .random_bytes = hex,
        .length = 32,
    }, 200);
}

fn handleUUID(ctx: *FetchContext) void {
    const uuid = workers.randomUUID();
    ctx.json(.{ .uuid = uuid }, 200);
}

fn handleHmacSign(ctx: *FetchContext) void {
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const message = json.getString("message") orelse {
        ctx.json(.{ .err = "Missing 'message' field" }, 400);
        return;
    };

    const keyHex = json.getString("key") orelse {
        ctx.json(.{ .err = "Missing 'key' field (hex-encoded)" }, 400);
        return;
    };

    // Parse key from hex
    const key = hexToBytes(keyHex) orelse {
        ctx.json(.{ .err = "Invalid hex key" }, 400);
        return;
    };

    const subtle = SubtleCrypto.get();
    defer subtle.free();

    // Import the key
    const importAlgo = workers.SubtleCryptoImportKeyAlgorithm{
        .name = "HMAC",
        .hash = "SHA-256",
    };

    const cryptoKey = subtle.importKey(
        .raw,
        key,
        &importAlgo,
        false,
        &.{.sign},
    ) orelse {
        ctx.json(.{ .err = "Failed to import key" }, 500);
        return;
    };
    defer cryptoKey.free();

    // Sign the message
    const signAlgo = workers.SubtleCryptoSignAlgorithm{
        .name = "HMAC",
    };

    if (subtle.sign(&signAlgo, &cryptoKey, message)) |signature| {
        const hex = bytesToHex(signature);
        ctx.json(.{
            .signature = hex,
            .algorithm = "HMAC-SHA256",
        }, 200);
    } else {
        ctx.json(.{ .err = "Failed to sign" }, 500);
    }
}

fn handleHmacVerify(ctx: *FetchContext) void {
    var json = ctx.bodyJson() orelse {
        ctx.json(.{ .err = "Invalid JSON body" }, 400);
        return;
    };
    defer json.deinit();

    const message = json.getString("message") orelse {
        ctx.json(.{ .err = "Missing 'message' field" }, 400);
        return;
    };

    const keyHex = json.getString("key") orelse {
        ctx.json(.{ .err = "Missing 'key' field (hex-encoded)" }, 400);
        return;
    };

    const signatureHex = json.getString("signature") orelse {
        ctx.json(.{ .err = "Missing 'signature' field (hex-encoded)" }, 400);
        return;
    };

    // Parse key and signature from hex
    const key = hexToBytes(keyHex) orelse {
        ctx.json(.{ .err = "Invalid hex key" }, 400);
        return;
    };

    const signature = hexToBytes(signatureHex) orelse {
        ctx.json(.{ .err = "Invalid hex signature" }, 400);
        return;
    };

    const subtle = SubtleCrypto.get();
    defer subtle.free();

    // Import the key
    const importAlgo = workers.SubtleCryptoImportKeyAlgorithm{
        .name = "HMAC",
        .hash = "SHA-256",
    };

    const cryptoKey = subtle.importKey(
        .raw,
        key,
        &importAlgo,
        false,
        &.{.verify},
    ) orelse {
        ctx.json(.{ .err = "Failed to import key" }, 500);
        return;
    };
    defer cryptoKey.free();

    // Verify the signature
    const signAlgo = workers.SubtleCryptoSignAlgorithm{
        .name = "HMAC",
    };

    const valid = subtle.verify(&signAlgo, &cryptoKey, signature, message);
    ctx.json(.{
        .valid = valid,
        .algorithm = "HMAC-SHA256",
    }, 200);
}

fn handleAesGenerate(ctx: *FetchContext) void {
    const subtle = SubtleCrypto.get();
    defer subtle.free();

    const genAlgo = workers.SubtleCryptoGenerateKeyAlgorithm{
        .name = "AES-GCM",
        .length = 256,
    };

    const key = subtle.generateKey(
        &genAlgo,
        true, // extractable
        &.{ .encrypt, .decrypt },
    ) orelse {
        ctx.json(.{ .err = "Failed to generate key" }, 500);
        return;
    };
    defer key.free();

    // Export the key
    if (subtle.exportKey(.raw, &key)) |keyBytes| {
        const hex = bytesToHex(keyBytes);
        ctx.json(.{
            .algorithm = "AES-GCM",
            .length = 256,
            .key = hex,
        }, 200);
    } else {
        ctx.json(.{ .err = "Failed to export key" }, 500);
    }
}

// ============================================================================
// Helpers
// ============================================================================

fn parseAlgorithm(name: []const u8) ?workers.DigestAlgorithm {
    if (std.mem.eql(u8, name, "sha1") or std.mem.eql(u8, name, "SHA-1")) {
        return .@"SHA-1";
    } else if (std.mem.eql(u8, name, "sha256") or std.mem.eql(u8, name, "SHA-256")) {
        return .@"SHA-256";
    } else if (std.mem.eql(u8, name, "sha384") or std.mem.eql(u8, name, "SHA-384")) {
        return .@"SHA-384";
    } else if (std.mem.eql(u8, name, "sha512") or std.mem.eql(u8, name, "SHA-512")) {
        return .@"SHA-512";
    } else if (std.mem.eql(u8, name, "md5") or std.mem.eql(u8, name, "MD5")) {
        return .MD5;
    }
    return null;
}

fn bytesToHex(bytes: []const u8) []const u8 {
    const hex_chars = "0123456789abcdef";
    var result: [256]u8 = undefined; // Max 128 bytes input
    const len = @min(bytes.len * 2, result.len);

    var i: usize = 0;
    for (bytes) |byte| {
        if (i + 1 >= result.len) break;
        result[i] = hex_chars[byte >> 4];
        result[i + 1] = hex_chars[byte & 0x0F];
        i += 2;
    }

    // Return slice up to the hex-encoded length
    return result[0..len];
}

fn hexToBytes(hex: []const u8) ?[]const u8 {
    if (hex.len % 2 != 0) return null;

    var result: [128]u8 = undefined;
    const len = hex.len / 2;
    if (len > result.len) return null;

    var i: usize = 0;
    while (i < len) : (i += 1) {
        const high = hexCharToNibble(hex[i * 2]) orelse return null;
        const low = hexCharToNibble(hex[i * 2 + 1]) orelse return null;
        result[i] = (@as(u8, high) << 4) | @as(u8, low);
    }

    return result[0..len];
}

fn hexCharToNibble(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

// ============================================================================
// Entry Point
// ============================================================================

export fn handleFetch(ctx_id: u32) void {
    const ctx = FetchContext.init(ctx_id) catch return;
    Route.dispatch(routes, ctx);
}
