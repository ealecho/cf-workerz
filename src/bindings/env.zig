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

pub const Env = struct {
    id: u32,

    pub fn init(ptr: u32) Env {
        return Env{ .id = ptr };
    }

    pub fn free(self: *const Env) void {
        jsFree(self.id);
    }

    pub fn key(self: *const Env, name: []const u8) ?[]const u8 {
        const strPtr = getObjectValue(self.id, name);
        if (strPtr <= DefaultValueSize) return null;
        return getStringFree(strPtr);
    }

    pub fn secret(self: *const Env, name: []const u8) ?[]const u8 {
        const strPtr = getObjectValue(self.id, name);
        if (strPtr <= DefaultValueSize) return null;
        return getStringFree(strPtr);
    }

    pub fn d1(self: *const Env, name: []const u8) ?D1Database {
        const d1Ptr = getObjectValue(self.id, name);
        if (d1Ptr <= DefaultValueSize) return null;
        return D1Database.init(d1Ptr);
    }

    pub fn durableObject() void {}

    pub fn kv(self: *const Env, name: []const u8) ?KVNamespace {
        const kvPtr = getObjectValue(self.id, name);
        if (kvPtr <= DefaultValueSize) return null;
        return KVNamespace.init(kvPtr);
    }

    pub fn r2(self: *const Env, name: []const u8) ?R2Bucket {
        const r2Ptr = getObjectValue(self.id, name);
        if (r2Ptr <= DefaultValueSize) return null;
        return R2Bucket.init(r2Ptr);
    }

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
