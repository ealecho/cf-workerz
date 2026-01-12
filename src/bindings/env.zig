//! Environment bindings for Cloudflare Workers.
//!
//! The `Env` struct provides access to all Cloudflare bindings configured
//! in your `wrangler.toml`. This includes KV namespaces, D1 databases,
//! R2 buckets, Queues, Service Bindings, Workers AI, and more.
//!
//! ## Accessing Bindings
//!
//! ```zig
//! fn handleRequest(ctx: *FetchContext) void {
//!     // KV Namespace
//!     const kv = ctx.env.kv("MY_KV") orelse return;
//!     defer kv.free();
//!
//!     // D1 Database
//!     const db = ctx.env.d1("MY_DB") orelse return;
//!     defer db.free();
//!
//!     // R2 Bucket
//!     const bucket = ctx.env.r2("MY_BUCKET") orelse return;
//!     defer bucket.free();
//!
//!     // Environment variables
//!     const api_key = ctx.env.secret("API_KEY") orelse "";
//! }
//! ```
//!
//! ## Configuration
//!
//! Bindings are configured in `wrangler.toml`:
//!
//! ```toml
//! [[kv_namespaces]]
//! binding = "MY_KV"
//! id = "..."
//!
//! [[d1_databases]]
//! binding = "MY_DB"
//! database_id = "..."
//!
//! [[r2_buckets]]
//! binding = "MY_BUCKET"
//! bucket_name = "..."
//!
//! [vars]
//! API_URL = "https://api.example.com"
//!
//! # Secrets are set via `wrangler secret put SECRET_NAME`
//! ```

const getStringFree = @import("string.zig").getStringFree;
const getObjectValue = @import("object.zig").getObjectValue;
const common = @import("common.zig");
const jsFree = common.jsFree;
const DefaultValueSize = common.DefaultValueSize;
const KVNamespace = @import("../apis/kv.zig").KVNamespace;
const R2Bucket = @import("../apis/r2.zig").R2Bucket;
const D1Database = @import("../apis/d1.zig").D1Database;
const Queue = @import("../apis/queues.zig").Queue;
const Fetcher = @import("../apis/service.zig").Fetcher;
const AI = @import("../apis/ai.zig").AI;
const DurableObjectNamespace = @import("../apis/durable.zig").DurableObjectNamespace;

/// Environment bindings accessor.
///
/// Provides methods to access all Cloudflare Worker bindings including
/// KV, D1, R2, Queues, Service Bindings, Workers AI, and environment variables.
///
/// Access via `ctx.env` in your request handlers.
pub const Env = struct {
    id: u32,

    pub fn init(ptr: u32) Env {
        return Env{ .id = ptr };
    }

    pub fn free(self: *const Env) void {
        jsFree(self.id);
    }

    /// Get an environment variable by name.
    ///
    /// Returns the value of a non-secret environment variable defined
    /// in `wrangler.toml` under `[vars]`.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const api_url = ctx.env.key("API_URL") orelse "https://default.api.com";
    /// ```
    pub fn key(self: *const Env, name: []const u8) ?[]const u8 {
        const strPtr = getObjectValue(self.id, name);
        if (strPtr <= DefaultValueSize) return null;
        return getStringFree(strPtr);
    }

    /// Get a secret environment variable by name.
    ///
    /// Returns the value of a secret set via `wrangler secret put`.
    /// Secrets are encrypted and not visible in your source code.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const api_key = ctx.env.secret("API_KEY") orelse {
    ///     ctx.throw(500, "API_KEY not configured");
    ///     return;
    /// };
    /// ```
    pub fn secret(self: *const Env, name: []const u8) ?[]const u8 {
        const strPtr = getObjectValue(self.id, name);
        if (strPtr <= DefaultValueSize) return null;
        return getStringFree(strPtr);
    }

    /// Get a D1 database binding.
    ///
    /// Returns a `D1Database` for executing SQL queries against
    /// Cloudflare's serverless SQLite database.
    ///
    /// ## Configuration
    ///
    /// ```toml
    /// [[d1_databases]]
    /// binding = "MY_DB"
    /// database_id = "your-database-id"
    /// ```
    ///
    /// ## Example
    ///
    /// ```zig
    /// const db = ctx.env.d1("MY_DB") orelse {
    ///     ctx.throw(500, "D1 not configured");
    ///     return;
    /// };
    /// defer db.free();
    ///
    /// const User = struct { id: u32, name: []const u8 };
    /// if (db.one(User, "SELECT * FROM users WHERE id = ?", .{1})) |user| {
    ///     ctx.json(.{ .name = user.name }, 200);
    /// }
    /// ```
    pub fn d1(self: *const Env, name: []const u8) ?D1Database {
        const d1Ptr = getObjectValue(self.id, name);
        if (d1Ptr <= DefaultValueSize) return null;
        return D1Database.init(d1Ptr);
    }

    /// Get a Durable Object namespace binding.
    ///
    /// Returns a `DurableObjectNamespace` for accessing Durable Object instances.
    /// Durable Objects provide strongly consistent, globally distributed storage
    /// and coordination.
    ///
    /// ## Configuration
    ///
    /// ```toml
    /// [[durable_objects.bindings]]
    /// name = "MY_DO"
    /// class_name = "MyDurableObject"
    ///
    /// [[migrations]]
    /// tag = "v1"
    /// new_classes = ["MyDurableObject"]
    /// ```
    ///
    /// ## Example
    ///
    /// ```zig
    /// const namespace = ctx.env.durableObject("MY_DO") orelse {
    ///     ctx.throw(500, "Durable Object not configured");
    ///     return;
    /// };
    /// defer namespace.free();
    ///
    /// // Get a DO instance by name
    /// const id = namespace.idFromName("my-object");
    /// defer id.free();
    ///
    /// const stub = id.getStub();
    /// defer stub.free();
    ///
    /// const response = stub.fetch(.{ .text = "https://do/action" }, null);
    /// defer response.free();
    /// ```
    pub fn durableObject(self: *const Env, name: []const u8) ?DurableObjectNamespace {
        const doPtr = getObjectValue(self.id, name);
        if (doPtr <= DefaultValueSize) return null;
        return DurableObjectNamespace.init(doPtr);
    }

    /// Get a KV namespace binding.
    ///
    /// Returns a `KVNamespace` for key-value storage operations.
    ///
    /// ## Configuration
    ///
    /// ```toml
    /// [[kv_namespaces]]
    /// binding = "MY_KV"
    /// id = "your-namespace-id"
    /// ```
    ///
    /// ## Example
    ///
    /// ```zig
    /// const kv = ctx.env.kv("MY_KV") orelse {
    ///     ctx.throw(500, "KV not configured");
    ///     return;
    /// };
    /// defer kv.free();
    ///
    /// // Read
    /// if (kv.getText("user:123", .{})) |value| {
    ///     ctx.text(value, 200);
    /// }
    ///
    /// // Write
    /// kv.put("user:123", .{ .text = "{\"name\":\"Alice\"}" }, .{});
    /// ```
    pub fn kv(self: *const Env, name: []const u8) ?KVNamespace {
        const kvPtr = getObjectValue(self.id, name);
        if (kvPtr <= DefaultValueSize) return null;
        return KVNamespace.init(kvPtr);
    }

    /// Get an R2 bucket binding.
    ///
    /// Returns an `R2Bucket` for object storage operations.
    ///
    /// ## Configuration
    ///
    /// ```toml
    /// [[r2_buckets]]
    /// binding = "MY_BUCKET"
    /// bucket_name = "my-bucket"
    /// ```
    ///
    /// ## Example
    ///
    /// ```zig
    /// const bucket = ctx.env.r2("MY_BUCKET") orelse {
    ///     ctx.throw(500, "R2 not configured");
    ///     return;
    /// };
    /// defer bucket.free();
    ///
    /// // Upload
    /// const obj = bucket.put("uploads/file.txt", .{ .text = content }, .{});
    /// defer obj.free();
    ///
    /// // Download
    /// const result = bucket.get("uploads/file.txt", .{});
    /// defer result.free();
    /// ```
    pub fn r2(self: *const Env, name: []const u8) ?R2Bucket {
        const r2Ptr = getObjectValue(self.id, name);
        if (r2Ptr <= DefaultValueSize) return null;
        return R2Bucket.init(r2Ptr);
    }

    /// Get a Queue producer binding.
    ///
    /// Returns a `Queue` for sending messages to a Cloudflare Queue.
    ///
    /// ## Configuration
    ///
    /// ```toml
    /// [[queues.producers]]
    /// binding = "MY_QUEUE"
    /// queue = "my-queue-name"
    /// ```
    ///
    /// ## Example
    ///
    /// ```zig
    /// const queue = ctx.env.queue("MY_QUEUE") orelse {
    ///     ctx.throw(500, "Queue not configured");
    ///     return;
    /// };
    /// defer queue.free();
    ///
    /// queue.send("{\"action\":\"process\",\"id\":123}");
    /// ctx.json(.{ .queued = true }, 202);
    /// ```
    pub fn queue(self: *const Env, name: []const u8) ?Queue {
        const queuePtr = getObjectValue(self.id, name);
        if (queuePtr <= DefaultValueSize) return null;
        return Queue.init(queuePtr);
    }

    /// Get a Service Binding (Fetcher) from the environment.
    ///
    /// Service Bindings allow calling another Worker directly without
    /// going through a public URL.
    ///
    /// Configuration in wrangler.toml:
    /// ```toml
    /// services = [
    ///   { binding = "AUTH_SERVICE", service = "auth-worker" }
    /// ]
    /// ```
    ///
    /// Example:
    /// ```zig
    /// const auth = ctx.env.service("AUTH_SERVICE") orelse {
    ///     ctx.throw(500, "Auth service not configured");
    ///     return;
    /// };
    /// defer auth.free();
    ///
    /// const response = auth.fetch(.{ .text = "https://internal/validate" }, null);
    /// defer response.free();
    /// ```
    pub fn service(self: *const Env, name: []const u8) ?Fetcher {
        const servicePtr = getObjectValue(self.id, name);
        if (servicePtr <= DefaultValueSize) return null;
        return Fetcher.init(servicePtr);
    }

    /// Get a Workers AI binding from the environment.
    ///
    /// Workers AI provides access to AI models on Cloudflare's edge network
    /// including text generation, embeddings, image generation, and more.
    ///
    /// Configuration in wrangler.toml:
    /// ```toml
    /// [ai]
    /// binding = "AI"
    /// ```
    ///
    /// Example:
    /// ```zig
    /// const ai_binding = ctx.env.ai("AI") orelse {
    ///     ctx.throw(500, "AI not configured");
    ///     return;
    /// };
    /// defer ai_binding.free();
    ///
    /// const result = ai_binding.textGeneration(
    ///     "@cf/meta/llama-3.1-8b-instruct",
    ///     "Hello, how are you?",
    ///     .{}
    /// );
    /// ```
    pub fn ai(self: *const Env, name: []const u8) ?AI {
        const aiPtr = getObjectValue(self.id, name);
        if (aiPtr <= DefaultValueSize) return null;
        return AI.init(aiPtr);
    }
};
