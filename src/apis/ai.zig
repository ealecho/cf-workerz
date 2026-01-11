const std = @import("std");
const allocator = std.heap.page_allocator;
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const DefaultValueSize = common.DefaultValueSize;
const object = @import("../bindings/object.zig");
const Object = object.Object;
const getObjectValue = object.getObjectValue;
const String = @import("../bindings/string.zig").String;
const Array = @import("../bindings/array.zig").Array;
const AsyncFunction = @import("../bindings/function.zig").AsyncFunction;

/// Text generation options for LLM models
pub const TextGenerationOptions = struct {
    max_tokens: ?u32 = null,
    temperature: ?f32 = null,
    top_p: ?f32 = null,
    top_k: ?u32 = null,
    seed: ?u32 = null,
    repetition_penalty: ?f32 = null,
    frequency_penalty: ?f32 = null,
    presence_penalty: ?f32 = null,
    stream: bool = false,

    pub fn toObject(self: *const TextGenerationOptions) Object {
        const obj = Object.new();
        if (self.max_tokens) |v| obj.setNum("max_tokens", u32, v);
        if (self.temperature) |v| obj.setNum("temperature", f32, v);
        if (self.top_p) |v| obj.setNum("top_p", f32, v);
        if (self.top_k) |v| obj.setNum("top_k", u32, v);
        if (self.seed) |v| obj.setNum("seed", u32, v);
        if (self.repetition_penalty) |v| obj.setNum("repetition_penalty", f32, v);
        if (self.frequency_penalty) |v| obj.setNum("frequency_penalty", f32, v);
        if (self.presence_penalty) |v| obj.setNum("presence_penalty", f32, v);
        if (self.stream) obj.setBool("stream", true);
        return obj;
    }
};

/// Chat message for conversation-style models
pub const ChatMessage = struct {
    role: []const u8, // "system", "user", "assistant"
    content: []const u8,
};

/// Image generation options
pub const ImageGenerationOptions = struct {
    num_steps: ?u32 = null,
    guidance: ?f32 = null,
    width: ?u32 = null,
    height: ?u32 = null,

    pub fn toObject(self: *const ImageGenerationOptions) Object {
        const obj = Object.new();
        if (self.num_steps) |v| obj.setNum("num_steps", u32, v);
        if (self.guidance) |v| obj.setNum("guidance", f32, v);
        if (self.width) |v| obj.setNum("width", u32, v);
        if (self.height) |v| obj.setNum("height", u32, v);
        return obj;
    }
};

/// AI response containing generated text
pub const AiTextResponse = struct {
    id: u32,

    pub fn init(ptr: u32) AiTextResponse {
        return AiTextResponse{ .id = ptr };
    }

    pub fn free(self: *const AiTextResponse) void {
        jsFree(self.id);
    }

    /// Get the response text
    pub fn response(self: *const AiTextResponse) ?[]const u8 {
        const responsePtr = getObjectValue(self.id, "response");
        if (responsePtr <= DefaultValueSize) return null;
        const str = String.init(responsePtr);
        defer str.free();
        return str.value();
    }

    /// Get usage information if available
    pub fn usage(self: *const AiTextResponse) ?AiUsage {
        const usagePtr = getObjectValue(self.id, "usage");
        if (usagePtr <= DefaultValueSize) return null;
        return AiUsage.init(usagePtr);
    }
};

/// Token usage statistics
pub const AiUsage = struct {
    id: u32,

    pub fn init(ptr: u32) AiUsage {
        return AiUsage{ .id = ptr };
    }

    pub fn free(self: *const AiUsage) void {
        jsFree(self.id);
    }

    pub fn promptTokens(self: *const AiUsage) u32 {
        return @intCast(object.getObjectValueNum(self.id, "prompt_tokens", u32));
    }

    pub fn completionTokens(self: *const AiUsage) u32 {
        return @intCast(object.getObjectValueNum(self.id, "completion_tokens", u32));
    }

    pub fn totalTokens(self: *const AiUsage) u32 {
        return @intCast(object.getObjectValueNum(self.id, "total_tokens", u32));
    }
};

/// Embedding result from text embedding models
pub const AiEmbeddingResponse = struct {
    id: u32,

    pub fn init(ptr: u32) AiEmbeddingResponse {
        return AiEmbeddingResponse{ .id = ptr };
    }

    pub fn free(self: *const AiEmbeddingResponse) void {
        jsFree(self.id);
    }

    /// Get the embedding data array
    pub fn data(self: *const AiEmbeddingResponse) ?Array {
        const dataPtr = getObjectValue(self.id, "data");
        if (dataPtr <= DefaultValueSize) return null;
        return Array.init(dataPtr);
    }

    /// Get the shape of the embeddings
    pub fn shape(self: *const AiEmbeddingResponse) ?Array {
        const shapePtr = getObjectValue(self.id, "shape");
        if (shapePtr <= DefaultValueSize) return null;
        return Array.init(shapePtr);
    }
};

/// Workers AI binding for running AI models on Cloudflare's edge network.
///
/// Workers AI provides access to various AI models including:
/// - Text generation (Llama, Mistral, etc.)
/// - Text embeddings (BGE, etc.)
/// - Image generation (Stable Diffusion, Flux)
/// - Speech-to-text (Whisper)
/// - Image classification
/// - And more
///
/// Configuration in wrangler.toml:
/// ```toml
/// [ai]
/// binding = "AI"
/// ```
///
/// Example:
/// ```zig
/// const ai = ctx.env.ai("AI") orelse {
///     ctx.throw(500, "AI not configured");
///     return;
/// };
/// defer ai.free();
///
/// // Simple text generation
/// const result = ai.textGeneration("@cf/meta/llama-3.1-8b-instruct", "Hello!", .{});
/// if (result) |res| {
///     defer res.free();
///     if (res.response()) |text| {
///         // Use generated text
///     }
/// }
/// ```
pub const AI = struct {
    id: u32,

    pub fn init(ptr: u32) AI {
        return AI{ .id = ptr };
    }

    pub fn free(self: *const AI) void {
        jsFree(self.id);
    }

    /// Run an AI model with raw input object.
    /// This is the most flexible method - you construct the input object yourself.
    /// Returns the raw result object that you need to parse based on the model type.
    pub fn run(self: *const AI, model: []const u8, input: *const Object) ?Object {
        const model_str = String.new(model);
        defer model_str.free();

        const func = AsyncFunction.init(getObjectValue(self.id, "run"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&model_str);
        args.push(input);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return null;
        return Object.init(result);
    }

    /// Run text generation with a simple prompt.
    /// For models like @cf/meta/llama-3.1-8b-instruct, @cf/mistral/mistral-7b-instruct-v0.1
    pub fn textGeneration(
        self: *const AI,
        model: []const u8,
        prompt: []const u8,
        options: TextGenerationOptions,
    ) ?AiTextResponse {
        const input = options.toObject();
        defer input.free();
        input.setText("prompt", prompt);

        const model_str = String.new(model);
        defer model_str.free();

        const func = AsyncFunction.init(getObjectValue(self.id, "run"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&model_str);
        args.push(&input);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return null;
        return AiTextResponse.init(result);
    }

    /// Run text generation with chat messages (conversation format).
    /// For models that support the messages format.
    pub fn chat(
        self: *const AI,
        model: []const u8,
        messages: []const ChatMessage,
        options: TextGenerationOptions,
    ) ?AiTextResponse {
        const input = options.toObject();
        defer input.free();

        // Build messages array
        const msgs = Array.new();
        defer msgs.free();

        for (messages) |msg| {
            const msgObj = Object.new();
            defer msgObj.free();
            msgObj.setText("role", msg.role);
            msgObj.setText("content", msg.content);
            msgs.push(&msgObj);
        }

        input.setArray("messages", &msgs);

        const model_str = String.new(model);
        defer model_str.free();

        const func = AsyncFunction.init(getObjectValue(self.id, "run"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&model_str);
        args.push(&input);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return null;
        return AiTextResponse.init(result);
    }

    /// Generate text embeddings for similarity search, clustering, etc.
    /// For models like @cf/baai/bge-base-en-v1.5, @cf/baai/bge-large-en-v1.5
    pub fn textEmbeddings(
        self: *const AI,
        model: []const u8,
        text: []const u8,
    ) ?AiEmbeddingResponse {
        const input = Object.new();
        defer input.free();

        // Single text input
        const textArr = Array.new();
        defer textArr.free();
        const textStr = String.new(text);
        defer textStr.free();
        textArr.push(&textStr);
        input.setArray("text", &textArr);

        const model_str = String.new(model);
        defer model_str.free();

        const func = AsyncFunction.init(getObjectValue(self.id, "run"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&model_str);
        args.push(&input);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return null;
        return AiEmbeddingResponse.init(result);
    }

    /// Generate text embeddings for multiple texts at once (batch).
    pub fn textEmbeddingsBatch(
        self: *const AI,
        model: []const u8,
        texts: []const []const u8,
    ) ?AiEmbeddingResponse {
        const input = Object.new();
        defer input.free();

        const textArr = Array.new();
        defer textArr.free();
        for (texts) |text| {
            const textStr = String.new(text);
            defer textStr.free();
            textArr.push(&textStr);
        }
        input.setArray("text", &textArr);

        const model_str = String.new(model);
        defer model_str.free();

        const func = AsyncFunction.init(getObjectValue(self.id, "run"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&model_str);
        args.push(&input);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return null;
        return AiEmbeddingResponse.init(result);
    }

    /// Generate an image from a text prompt.
    /// For models like @cf/black-forest-labs/flux-1-schnell, @cf/stabilityai/stable-diffusion-xl-base-1.0
    /// Returns raw binary image data (PNG/JPEG depending on model).
    pub fn imageGeneration(
        self: *const AI,
        model: []const u8,
        prompt: []const u8,
        options: ImageGenerationOptions,
    ) ?Object {
        const input = options.toObject();
        defer input.free();
        input.setText("prompt", prompt);

        const model_str = String.new(model);
        defer model_str.free();

        const func = AsyncFunction.init(getObjectValue(self.id, "run"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&model_str);
        args.push(&input);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return null;
        return Object.init(result);
    }

    /// Summarize text content.
    /// For models like @cf/facebook/bart-large-cnn
    pub fn summarization(
        self: *const AI,
        model: []const u8,
        input_text: []const u8,
        max_length: ?u32,
    ) ?AiTextResponse {
        const input = Object.new();
        defer input.free();
        input.setText("input_text", input_text);
        if (max_length) |ml| {
            input.setNum("max_length", u32, ml);
        }

        const model_str = String.new(model);
        defer model_str.free();

        const func = AsyncFunction.init(getObjectValue(self.id, "run"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&model_str);
        args.push(&input);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return null;
        return AiTextResponse.init(result);
    }

    /// Translate text between languages.
    /// For models like @cf/meta/m2m100-1.2b
    pub fn translation(
        self: *const AI,
        model: []const u8,
        text: []const u8,
        source_lang: []const u8,
        target_lang: []const u8,
    ) ?AiTextResponse {
        const input = Object.new();
        defer input.free();
        input.setText("text", text);
        input.setText("source_lang", source_lang);
        input.setText("target_lang", target_lang);

        const model_str = String.new(model);
        defer model_str.free();

        const func = AsyncFunction.init(getObjectValue(self.id, "run"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&model_str);
        args.push(&input);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return null;
        return AiTextResponse.init(result);
    }
};
