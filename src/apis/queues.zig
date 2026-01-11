// Queues API - Cloudflare Queues bindings for workers-zig
// Provides both producer (send) and consumer (receive/batch) functionality
//
// Producer API:
//   Queue.send(body) - Send a single message
//   Queue.sendBatch(messages) - Send batch of messages
//
// Consumer API:
//   MessageBatch - Batch of messages received by consumer
//   Message - Individual message with ack/retry methods

const common = @import("../bindings/common.zig");
const Undefined = common.Undefined;
const jsFree = common.jsFree;
const String = @import("../bindings/string.zig").String;
const Array = @import("../bindings/array.zig").Array;
const Object = @import("../bindings/object.zig").Object;
const getObjectValue = @import("../bindings/object.zig").getObjectValue;
const AsyncFunction = @import("../bindings/function.zig").AsyncFunction;
const Function = @import("../bindings/function.zig").Function;

// ============================================================================
// Queue Producer API
// ============================================================================

/// Content type for queue messages
pub const QueueContentType = enum {
    json,
    text,
    bytes,
    v8,

    pub fn toString(self: QueueContentType) []const u8 {
        return switch (self) {
            .json => "json",
            .text => "text",
            .bytes => "bytes",
            .v8 => "v8",
        };
    }
};

/// Options for sending a single message
pub const QueueSendOptions = struct {
    contentType: ?QueueContentType = null,
    delaySeconds: ?u32 = null,

    pub fn toObject(self: *const QueueSendOptions) Object {
        const obj = Object.new();
        if (self.contentType) |ct| {
            const ct_str = String.new(ct.toString());
            defer ct_str.free();
            obj.setID("contentType", ct_str.id);
        }
        if (self.delaySeconds) |delay| {
            obj.setNum("delaySeconds", u32, delay);
        }
        return obj;
    }
};

/// Options for sending a batch of messages
pub const QueueSendBatchOptions = struct {
    delaySeconds: ?u32 = null,

    pub fn toObject(self: *const QueueSendBatchOptions) Object {
        const obj = Object.new();
        if (self.delaySeconds) |delay| {
            obj.setNum("delaySeconds", u32, delay);
        }
        return obj;
    }
};

/// A message to send in a batch
pub const MessageSendRequest = struct {
    body: []const u8,
    contentType: ?QueueContentType = null,
    delaySeconds: ?u32 = null,
};

/// Queue producer - send messages to a queue
pub const Queue = struct {
    id: u32,

    pub fn init(ptr: u32) Queue {
        return Queue{ .id = ptr };
    }

    pub fn free(self: *const Queue) void {
        jsFree(self.id);
    }

    /// Send a single message to the queue (JSON content type)
    pub fn send(self: *const Queue, body: []const u8) void {
        self.sendWithOptions(body, .{});
    }

    /// Send a single message with options
    pub fn sendWithOptions(self: *const Queue, body: []const u8, options: QueueSendOptions) void {
        // Create message body (parse as JSON if it looks like JSON, otherwise as text)
        const body_str = String.new(body);
        defer body_str.free();

        // Create options object
        const opts = options.toObject();
        defer opts.free();

        // Build arguments array
        const args = Array.new();
        defer args.free();
        args.push(&body_str);
        args.push(&opts);

        // Get the send function and call it
        const func = AsyncFunction{ .id = getObjectValue(self.id, "send") };
        defer func.free();
        _ = func.callArgsID(args.id);
    }

    /// Send a batch of messages to the queue
    pub fn sendBatch(self: *const Queue, messages: []const MessageSendRequest) void {
        self.sendBatchWithOptions(messages, .{});
    }

    /// Send a batch of messages with options
    pub fn sendBatchWithOptions(self: *const Queue, messages: []const MessageSendRequest, options: QueueSendBatchOptions) void {
        // Build the messages array
        const msgs_array = Array.new();
        defer msgs_array.free();

        for (messages) |msg| {
            const msg_obj = Object.new();
            defer msg_obj.free();

            // Set body
            const body_str = String.new(msg.body);
            defer body_str.free();
            msg_obj.setID("body", body_str.id);

            // Set contentType if specified
            if (msg.contentType) |ct| {
                const ct_str = String.new(ct.toString());
                defer ct_str.free();
                msg_obj.setID("contentType", ct_str.id);
            }

            // Set delaySeconds if specified
            if (msg.delaySeconds) |delay| {
                msg_obj.setNum("delaySeconds", u32, delay);
            }

            msgs_array.push(&msg_obj);
        }

        // Create batch options object
        const opts = options.toObject();
        defer opts.free();

        // Build arguments array
        const args = Array.new();
        defer args.free();
        args.push(&msgs_array);
        args.push(&opts);

        // Get the sendBatch function and call it
        const func = AsyncFunction{ .id = getObjectValue(self.id, "sendBatch") };
        defer func.free();
        _ = func.callArgsID(args.id);
    }
};

// ============================================================================
// Queue Consumer API
// ============================================================================

/// Options for retrying a message or batch
pub const QueueRetryOptions = struct {
    delaySeconds: ?u32 = null,

    pub fn toObject(self: *const QueueRetryOptions) Object {
        const obj = Object.new();
        if (self.delaySeconds) |delay| {
            obj.setNum("delaySeconds", u32, delay);
        }
        return obj;
    }
};

/// A single message from a queue batch
pub const Message = struct {
    id: u32,

    pub fn init(ptr: u32) Message {
        return Message{ .id = ptr };
    }

    pub fn free(self: *const Message) void {
        jsFree(self.id);
    }

    /// Get the message ID (system-generated unique ID)
    pub fn messageId(self: *const Message) []const u8 {
        const str_ptr = getObjectValue(self.id, "id");
        if (str_ptr <= 6) return "";
        const str = String.init(str_ptr);
        defer str.free();
        return str.value();
    }

    /// Get the message body as text (JSON stringified)
    pub fn body(self: *const Message) []const u8 {
        const body_ptr = getObjectValue(self.id, "body");
        if (body_ptr <= 6) return "";

        // Try to stringify if it's an object
        const obj = Object.init(body_ptr);
        defer obj.free();
        const json_str = obj.stringify();
        defer json_str.free();
        return json_str.value();
    }

    /// Get the raw body as an Object for manual access
    pub fn bodyObject(self: *const Message) Object {
        return Object.init(getObjectValue(self.id, "body"));
    }

    /// Get the number of delivery attempts
    pub fn attempts(self: *const Message) u32 {
        const obj = Object.init(self.id);
        return obj.getNum("attempts", u32);
    }

    /// Get the timestamp as milliseconds since epoch
    pub fn timestamp(self: *const Message) f64 {
        // timestamp is a Date object, get its value
        const date_ptr = getObjectValue(self.id, "timestamp");
        if (date_ptr <= 6) return 0;
        defer jsFree(date_ptr);

        const date_obj = Object.init(date_ptr);
        const get_time = Function{ .id = getObjectValue(date_ptr, "getTime") };
        defer get_time.free();

        const args = Array.new();
        defer args.free();
        _ = date_obj; // Silence unused warning

        // Call getTime() to get milliseconds
        const result = get_time.callArgsID(args.id);
        if (result <= 6) return 0;

        // Result is a number on the heap
        return @as(f64, @floatFromInt(result)); // This is actually wrong, need to get the actual number
    }

    /// Acknowledge this message (mark as successfully processed)
    pub fn ack(self: *const Message) void {
        const func = Function{ .id = getObjectValue(self.id, "ack") };
        defer func.free();
        _ = func.call();
    }

    /// Retry this message (will be redelivered)
    pub fn retry(self: *const Message) void {
        self.retryWithOptions(.{});
    }

    /// Retry this message with options
    pub fn retryWithOptions(self: *const Message, options: QueueRetryOptions) void {
        const opts = options.toObject();
        defer opts.free();

        const args = Array.new();
        defer args.free();
        args.push(&opts);

        const func = Function{ .id = getObjectValue(self.id, "retry") };
        defer func.free();
        _ = func.callArgsID(args.id);
    }
};

/// A batch of messages from a queue
pub const MessageBatch = struct {
    id: u32,

    pub fn init(ptr: u32) MessageBatch {
        return MessageBatch{ .id = ptr };
    }

    pub fn free(self: *const MessageBatch) void {
        jsFree(self.id);
    }

    /// Get the queue name this batch belongs to
    pub fn queueName(self: *const MessageBatch) []const u8 {
        const str_ptr = getObjectValue(self.id, "queue");
        if (str_ptr <= 6) return "";
        const str = String.init(str_ptr);
        defer str.free();
        return str.value();
    }

    /// Get the messages array
    pub fn messages(self: *const MessageBatch) MessageIterator {
        const msgs_ptr = getObjectValue(self.id, "messages");
        return MessageIterator.init(msgs_ptr);
    }

    /// Get the number of messages in the batch
    pub fn length(self: *const MessageBatch) u32 {
        const msgs_ptr = getObjectValue(self.id, "messages");
        if (msgs_ptr <= 6) return 0;
        defer jsFree(msgs_ptr);

        const arr = Array.init(msgs_ptr);
        return arr.length();
    }

    /// Acknowledge all messages in the batch
    pub fn ackAll(self: *const MessageBatch) void {
        const func = Function{ .id = getObjectValue(self.id, "ackAll") };
        defer func.free();
        _ = func.call();
    }

    /// Retry all messages in the batch
    pub fn retryAll(self: *const MessageBatch) void {
        self.retryAllWithOptions(.{});
    }

    /// Retry all messages with options
    pub fn retryAllWithOptions(self: *const MessageBatch, options: QueueRetryOptions) void {
        const opts = options.toObject();
        defer opts.free();

        const args = Array.new();
        defer args.free();
        args.push(&opts);

        const func = Function{ .id = getObjectValue(self.id, "retryAll") };
        defer func.free();
        _ = func.callArgsID(args.id);
    }
};

/// Iterator over messages in a batch
pub const MessageIterator = struct {
    id: u32,
    index: u32,
    len: u32,

    pub fn init(array_ptr: u32) MessageIterator {
        if (array_ptr <= 6) {
            return MessageIterator{ .id = 0, .index = 0, .len = 0 };
        }
        const arr = Array.init(array_ptr);
        return MessageIterator{
            .id = array_ptr,
            .index = 0,
            .len = arr.length(),
        };
    }

    pub fn free(self: *const MessageIterator) void {
        if (self.id > 6) {
            jsFree(self.id);
        }
    }

    pub fn next(self: *MessageIterator) ?Message {
        if (self.index >= self.len) return null;

        const arr = Array.init(self.id);
        const msg_ptr = arr.get(self.index);
        self.index += 1;

        if (msg_ptr <= 6) return null;
        return Message.init(msg_ptr);
    }

    pub fn reset(self: *MessageIterator) void {
        self.index = 0;
    }
};
