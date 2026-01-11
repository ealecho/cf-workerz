//! Cloudflare Workers KV - Global, low-latency key-value storage.
//!
//! Workers KV is a global, low-latency, key-value data store. It supports
//! exceptionally high read volumes with low-latency, making it possible to
//! build highly dynamic APIs and websites that respond as quickly as a cached
//! static file would.
//!
//! ## Quick Start
//!
//! ```zig
//! fn handleKV(ctx: *FetchContext) void {
//!     const kv = ctx.env.kv("MY_KV") orelse {
//!         ctx.throw(500, "KV not configured");
//!         return;
//!     };
//!     defer kv.free();
//!
//!     // Get a value
//!     if (kv.getText("user:123", .{})) |value| {
//!         ctx.json(.{ .data = value }, 200);
//!         return;
//!     }
//!
//!     // Put a value
//!     kv.put("user:123", .{ .text = "Alice" }, .{});
//!
//!     // Put with TTL (expires in 1 hour)
//!     kv.put("session:abc", .{ .text = "token" }, .{ .expirationTtl = 3600 });
//!
//!     // Delete a value
//!     kv.delete("old:key");
//!
//!     ctx.json(.{ .stored = true }, 200);
//! }
//! ```
//!
//! ## Configuration
//!
//! Add to your `wrangler.toml`:
//!
//! ```toml
//! [[kv_namespaces]]
//! binding = "MY_KV"
//! id = "your-kv-namespace-id"
//! ```

const std = @import("std");
const allocator = std.heap.page_allocator;
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const True = common.True;
const Null = common.Null;
const DefaultValueSize = common.DefaultValueSize;
const object = @import("../bindings/object.zig");
const Object = object.Object;
const getObjectValue = object.getObjectValue;
const getObjectValueNum = object.getObjectValueNum;
const jsParse = object.jsParse;
const ArrayBuffer = @import("../bindings/arraybuffer.zig").ArrayBuffer;
const string = @import("../bindings/string.zig");
const String = string.String;
const getStringFree = string.getStringFree;
const Array = @import("../bindings/array.zig").Array;
const ReadableStream = @import("../bindings/streams/readable.zig").ReadableStream;
const AsyncFunction = @import("../bindings/function.zig").AsyncFunction;

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L932
// Note: To simplify, we getX rather than applying type to the options.

/// Options for KV get operations.
///
/// ## Fields
///
/// - `cacheTtl`: Optional cache TTL in seconds. If specified, the value will be
///   cached at the edge for this duration. Minimum is 60 seconds.
///
/// ## Example
///
/// ```zig
/// // Get with default options (no caching)
/// const value = kv.getText("key", .{});
///
/// // Get with 5-minute edge cache
/// const cached = kv.getText("key", .{ .cacheTtl = 300 });
/// ```
pub const GetOptions = struct {
    cacheTtl: ?u64 = null,

    pub fn toObject(self: *const GetOptions) Object {
        const obj = Object.new();
        if (self.cacheTtl != null) obj.setNum("cacheTtl", u64, self.cacheTtl.?);

        return obj;
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L890

/// Value types that can be stored in KV.
///
/// KV supports storing text, binary data, objects, and streams. Use the
/// appropriate variant based on your data type.
///
/// ## Variants
///
/// | Variant | Use Case |
/// |---------|----------|
/// | `.text` | UTF-8 strings (most common) |
/// | `.bytes` | Binary data as `[]const u8` |
/// | `.object` | JSON-serializable objects |
/// | `.arrayBuffer` | Raw `ArrayBuffer` from JS |
/// | `.readableStream` | Streaming data |
///
/// ## Example
///
/// ```zig
/// // Store text
/// kv.put("greeting", .{ .text = "Hello, World!" }, .{});
///
/// // Store binary data
/// const data = [_]u8{ 0x00, 0x01, 0x02 };
/// kv.put("binary", .{ .bytes = &data }, .{});
///
/// // Store JSON object
/// const obj = Object.new();
/// defer obj.free();
/// obj.setText("name", "Alice");
/// kv.put("user", .{ .object = &obj }, .{});
/// ```
pub const PutValue = union(enum) {
    text: []const u8,
    string: *const String,
    object: *const Object,
    bytes: []const u8,
    arrayBuffer: *const ArrayBuffer,
    readableStream: *const ReadableStream,

    pub fn toID(self: *const PutValue) u32 {
        switch (self.*) {
            .text => |str| return String.new(str).id,
            .string => |str| return str.id,
            .object => |obj| return obj.stringify().id,
            .bytes => |bytes| return ArrayBuffer.new(bytes).id,
            .arrayBuffer => |ab| return ab.id,
            .readableStream => |rStream| return rStream.id,
        }
    }

    pub fn free(self: *const PutValue, id: u32) void {
        switch (self.*) {
            .text => jsFree(id),
            .object => jsFree(id),
            .bytes => jsFree(id),
            else => {},
        }
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L960

/// Options for KV put operations.
///
/// Control expiration and attach metadata to stored values.
///
/// ## Fields
///
/// - `expiration`: Unix timestamp (seconds since epoch) when the key expires
/// - `expirationTtl`: Seconds from now until the key expires (minimum 60)
/// - `metadata`: Optional JSON object to store alongside the value
///
/// ## Example
///
/// ```zig
/// // Store with 1-hour TTL
/// kv.put("session", .{ .text = "token" }, .{ .expirationTtl = 3600 });
///
/// // Store with absolute expiration
/// kv.put("cache", .{ .text = "data" }, .{ .expiration = 1735689600 });
///
/// // Store with metadata
/// const meta = Object.new();
/// defer meta.free();
/// meta.setText("created_by", "system");
/// kv.put("key", .{ .text = "value" }, .{ .metadata = &meta });
/// ```
pub const PutOptions = struct {
    expiration: ?u64 = null, // secondsSinceEpoch
    expirationTtl: ?u64 = null, // secondsFromNow
    metadata: ?*const Object = null,

    pub fn toObject(self: *const PutOptions) Object {
        const obj = Object.new();

        if (self.expiration != null) obj.setNum("expiration", u64, self.expiration.?);
        if (self.expirationTtl != null) obj.setNum("expirationTtl", u64, self.expirationTtl.?);
        if (self.metadata != null) obj.set("metadata", self.metadata.?);

        return obj;
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L948

/// Options for listing keys in a KV namespace.
///
/// ## Fields
///
/// - `limit`: Maximum number of keys to return (default 1000, max 1000)
/// - `prefix`: Only return keys starting with this prefix
/// - `cursor`: Pagination cursor from a previous `list()` call
///
/// ## Example
///
/// ```zig
/// // List all keys (up to 1000)
/// const result = kv.list(.{});
/// defer result.free();
///
/// // List keys with a prefix
/// const users = kv.list(.{ .prefix = "user:", .limit = 100 });
/// defer users.free();
///
/// // Paginate through all keys
/// var cursor: ?[]const u8 = null;
/// while (true) {
///     const page = kv.list(.{ .cursor = cursor });
///     defer page.free();
///
///     var keys = page.keys();
///     defer keys.free();
///     while (keys.next()) |key| {
///         defer key.free();
///         // Process key.name()
///     }
///
///     if (page.listComplete()) break;
///     cursor = page.cursor();
/// }
/// ```
pub const ListOptions = struct {
    limit: u16 = 1_000,
    prefix: ?[]const u8 = null,
    jsPrefix: ?*const String = null,
    cursor: ?[]const u8 = null,
    jsCursor: ?*const String = null,

    pub fn toObject(self: *const ListOptions) Object {
        const obj = Object.new();

        obj.setNum("limit", u16, self.limit);
        if (self.prefix != null) obj.setText("prefix", self.prefix.?);
        if (self.jsPrefix != null) obj.set("prefix", self.jsPrefix.?);
        if (self.cursor != null) obj.setText("cursor", self.cursor.?);
        if (self.jsCursor != null) obj.set("cursor", self.jsCursor.?);

        return obj;
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L954

/// Result from a KV list operation.
///
/// Contains the list of keys and pagination information. Use `keys()` to
/// iterate over the results, `listComplete()` to check if there are more
/// pages, and `cursor()` to get the pagination cursor for the next page.
///
/// ## Example
///
/// ```zig
/// const result = kv.list(.{ .prefix = "user:" });
/// defer result.free();
///
/// var keys = result.keys();
/// defer keys.free();
///
/// while (keys.next()) |key| {
///     defer key.free();
///     const name = key.name();
///     const expiration = key.expiration(); // ?u64
///     // Process key...
/// }
///
/// if (!result.listComplete()) {
///     const next_cursor = result.cursor();
///     // Use cursor for next page
/// }
/// ```
pub const ListResult = struct {
    id: u32,

    pub fn init(id: u32) ListResult {
        return ListResult{ .id = id };
    }

    /// Release the JavaScript object. Always call this when done.
    pub fn free(self: *const ListResult) void {
        jsFree(self.id);
    }

    /// Get an iterator over the keys in this result.
    ///
    /// Returns a `ListKeys` iterator that yields `ListKey` objects.
    /// Remember to free both the iterator and each key.
    pub fn keys(self: *const ListResult) ListKeys {
        return ListKeys.init(getObjectValue(self.id, "keys"));
    }

    /// Get the pagination cursor for the next page.
    ///
    /// Use this value in `ListOptions.cursor` to fetch the next page of results.
    /// Only valid when `listComplete()` returns `false`.
    pub fn cursor(self: *const ListResult) []const u8 {
        return getStringFree(getObjectValue(self.id, "cursor"));
    }

    /// Check if all keys have been returned.
    ///
    /// Returns `true` if there are no more pages, `false` if you should
    /// call `list()` again with the `cursor()` value.
    pub fn listComplete(self: *const ListResult) bool {
        const jsPtr = getObjectValue(self.id, "list_complete");
        return jsPtr == True;
    }

    /// Iterator over keys returned from a list operation.
    ///
    /// Use `next()` to iterate and get `ListKey` objects.
    /// Remember to call `free()` on the iterator when done.
    pub const ListKeys = struct {
        arr: Array,
        pos: u32 = 0,
        len: u32,

        pub fn init(jsPtr: u32) ListKeys {
            const arr = Array.init(jsPtr);
            return ListKeys{
                .arr = arr,
                .len = arr.length(),
            };
        }

        /// Release the underlying array. Call when done iterating.
        pub fn free(self: *const ListKeys) void {
            self.arr.free();
        }

        /// Get the next key in the list, or `null` if exhausted.
        ///
        /// Remember to call `free()` on each returned `ListKey`.
        pub fn next(self: *ListKeys) ?ListKey {
            if (self.pos == self.len) return null;
            const listkey = self.arr.getType(ListKey, self.pos);
            self.pos += 1;
            return listkey;
        }
    };

    /// A single key from a list operation.
    ///
    /// Contains the key name and optional metadata/expiration information.
    pub const ListKey = struct {
        id: u32,

        pub fn init(jsPtr: u32) ListKey {
            return ListKey{ .id = jsPtr };
        }

        /// Release the JavaScript object.
        pub fn free(self: *const ListKey) void {
            jsFree(self.id);
        }

        /// Get the key name.
        pub fn name(self: *const ListKey) []const u8 {
            return getStringFree(getObjectValue(self.id, "name"));
        }

        /// Get the expiration timestamp (seconds since epoch), if set.
        ///
        /// Returns `null` if the key has no expiration.
        pub fn expiration(self: *const ListKey) ?u64 {
            const num = getObjectValueNum(self.id, "expiration", u64);
            if (num <= DefaultValueSize) return null;
            return num;
        }

        /// Parse the key's metadata into a Zig struct.
        ///
        /// Returns `null` if no metadata exists or parsing fails.
        pub fn metadata(self: *const ListKey, comptime T: type) ?T {
            const obj = self.metaObject() orelse return null;
            defer obj.free();
            return obj.parse(T) orelse null;
        }

        /// Get the key's metadata as a raw JavaScript Object.
        ///
        /// Returns `null` if no metadata exists. Remember to `free()` the object.
        pub fn metaObject(self: *const ListKey) ?Object {
            const objPtr = getObjectValue(self.id, "metadata");
            if (objPtr <= DefaultValueSize) return null;
            return Object.init(objPtr);
        }
    };
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L852

/// Cloudflare Workers KV Namespace.
///
/// Workers KV is a global, low-latency, key-value data store. It supports
/// exceptionally high read volumes with low-latency, making it possible to
/// build highly dynamic APIs and websites that respond as quickly as a
/// cached static file would.
///
/// ## Getting a KV Namespace
///
/// ```zig
/// fn handler(ctx: *FetchContext) void {
///     const kv = ctx.env.kv("MY_KV") orelse {
///         ctx.throw(500, "KV binding not found");
///         return;
///     };
///     defer kv.free();
///
///     // Use kv...
/// }
/// ```
///
/// ## Common Operations
///
/// ```zig
/// // Store a value
/// kv.put("key", .{ .text = "value" }, .{});
///
/// // Store with expiration (1 hour TTL)
/// kv.put("session", .{ .text = "token" }, .{ .expirationTtl = 3600 });
///
/// // Get as text
/// if (kv.getText("key", .{})) |value| {
///     // value is []const u8
/// }
///
/// // Get as JSON struct
/// const User = struct { name: []const u8, age: u32 };
/// if (kv.getJSON(User, "user:123", .{})) |user| {
///     // user.name, user.age
/// }
///
/// // Delete
/// kv.delete("key");
///
/// // List keys
/// const result = kv.list(.{ .prefix = "user:" });
/// defer result.free();
/// ```
pub const KVNamespace = struct {
    id: u32,

    pub fn init(ptr: u32) KVNamespace {
        return KVNamespace{ .id = ptr };
    }

    /// Release the JavaScript binding. Always call when done.
    pub fn free(self: *const KVNamespace) void {
        jsFree(self.id);
    }

    /// Store a value in KV.
    ///
    /// ## Parameters
    ///
    /// - `key`: The key to store (max 512 bytes)
    /// - `value`: The value to store (see `PutValue` for types)
    /// - `options`: Expiration and metadata options
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Simple text storage
    /// kv.put("greeting", .{ .text = "Hello!" }, .{});
    ///
    /// // With 1-hour expiration
    /// kv.put("cache:data", .{ .text = json_string }, .{
    ///     .expirationTtl = 3600,
    /// });
    ///
    /// // Binary data
    /// kv.put("image", .{ .bytes = image_data }, .{});
    /// ```
    pub fn put(self: *const KVNamespace, key: []const u8, value: PutValue, options: PutOptions) void {
        // prep the string
        const str = String.new(key);
        defer str.free();
        // prep the object
        const val = value.toID();
        defer value.free(val);
        // prep the options
        const opts = options.toObject();
        defer opts.free();
        // grab the function
        const func = AsyncFunction.init(getObjectValue(self.id, "put"));
        defer func.free();
        // prep the args
        const args = Array.new();
        defer args.free();
        args.push(&str);
        args.pushID(val);
        args.push(&opts);

        _ = func.callArgsID(args.id);
    }

    /// Store a value with a Zig struct as metadata.
    ///
    /// Automatically serializes the metadata struct to JSON.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const Meta = struct { created_at: u64, version: u32 };
    /// kv.putMetadata("key", .{ .text = "value" }, Meta, .{
    ///     .created_at = 1234567890,
    ///     .version = 1,
    /// }, .{});
    /// ```
    pub fn putMetadata(self: *const KVNamespace, key: []const u8, value: PutValue, comptime T: type, metadata: T, options: PutOptions) void {
        // prep the string
        const str = String.new(key);
        defer str.free();
        // prep the object
        const val = value.toID();
        defer value.free(val);
        // metadata -> string -> Object -> options.metadata.
        var buf: [1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        var metaBuf = std.ArrayList(u8).init(fba.allocator());
        std.json.stringify(metadata, .{}, metaBuf.writer()) catch {
            String.new("Failed to stringify " ++ @typeName(T)).throw();
            return;
        };
        const metaString = String.new(metaBuf.items);
        defer metaString.free();
        const metaObj = Object.init(jsParse(metaString.id));
        defer metaObj.free();
        // prep the options
        const newOptions = PutOptions{
            .expiration = options.expiration,
            .expirationTtl = options.expirationTtl,
            .metadata = &metaObj,
        };
        const opts = newOptions.toObject();
        defer opts.free();
        // grab the function
        const func = AsyncFunction.init(getObjectValue(self.id, "put"));
        defer func.free();
        // prep the args
        const args = Array.new();
        defer args.free();
        args.push(&str);
        args.pushID(val);
        args.push(&opts);

        _ = func.callArgsID(args.id);
    }

    fn _get(
        self: *const KVNamespace,
        key: []const u8,
        options: GetOptions,
        resType: []const u8,
    ) u32 {
        // prep the string
        const str = String.new(key);
        defer str.free();
        // grab options
        const opts = options.toObject();
        defer opts.free();
        opts.setText("type", resType);
        // grab the function
        const func = AsyncFunction.init(getObjectValue(self.id, "get"));
        defer func.free();
        // prep the args
        const args = Array.new();
        defer args.free();
        args.push(&str);
        args.push(&opts);

        return func.callArgsID(args.id);
    }

    fn _getMeta(
        self: *const KVNamespace,
        key: []const u8,
        options: GetOptions,
        resType: []const u8,
    ) u32 {
        // prep the string
        const str = String.new(key);
        defer str.free();
        // grab options
        const opts = options.toObject();
        defer opts.free();
        opts.setText("type", resType);
        // grab the function
        const func = AsyncFunction.init(getObjectValue(self.id, "getWithMetadata"));
        defer func.free();
        // prep the args
        const args = Array.new();
        defer args.free();
        args.push(&str);
        args.push(&opts);

        return func.callArgsID(args.id);
    }

    /// Get a value as a JavaScript String object.
    ///
    /// Returns `null` if the key doesn't exist. Remember to `free()` the String.
    /// For most cases, prefer `getText()` which returns a Zig slice directly.
    pub fn getString(self: *const KVNamespace, key: []const u8, options: GetOptions) ?String {
        const result = self._get(key, options, "text");
        if (result <= DefaultValueSize) return null;
        return String{ .id = result };
    }

    /// Value and metadata returned from `getStringWithMetadata`.
    pub const KVStringMetadata = struct {
        value: String,
        metadata: ?Object,

        pub fn init(valuePtr: u32, metaPtr: u32) KVStringMetadata {
            var metadata: ?Object = null;
            if (metaPtr > DefaultValueSize) metadata = Object.init(metaPtr);
            return KVStringMetadata{
                .value = String.init(valuePtr),
                .metadata = metadata,
            };
        }

        pub fn free(self: *const KVStringMetadata) void {
            self.value.free();
            self.metadata.?.free();
        }
    };

    /// Get a value as a String along with its metadata.
    pub fn getStringWithMetadata(self: *const KVNamespace, key: []const u8, options: GetOptions) ?KVStringMetadata {
        const result = self._getMeta(key, options, "text");
        if (result <= DefaultValueSize) return null;
        const resObj = Object.init(result);
        defer resObj.free();
        return KVStringMetadata.init(resObj.get("value"), resObj.get("metadata"));
    }

    /// Get a value as a Zig string slice.
    ///
    /// This is the most common way to retrieve text values from KV.
    /// Returns `null` if the key doesn't exist.
    ///
    /// ## Example
    ///
    /// ```zig
    /// if (kv.getText("user:123:name", .{})) |name| {
    ///     ctx.json(.{ .name = name }, 200);
    /// } else {
    ///     ctx.json(.{ .err = "User not found" }, 404);
    /// }
    /// ```
    pub fn getText(self: *const KVNamespace, key: []const u8, options: GetOptions) ?[]const u8 {
        const str = self.getString(key, options) orelse return null;
        defer str.free();
        return str.value();
    }

    /// Value and metadata returned from `getTextWithMetadata`.
    pub const KVTextMetadata = struct {
        value: []const u8,
        metadata: ?Object,

        pub fn init(value: []const u8, metadata: ?Object) KVTextMetadata {
            return KVTextMetadata{
                .value = value,
                .metadata = metadata,
            };
        }

        /// Free the allocated string and metadata object.
        pub fn free(self: *const KVTextMetadata) void {
            allocator.free(self.value);
            self.metadata.?.free();
        }
    };

    /// Get a text value along with its metadata.
    pub fn getTextWithMetadata(self: *const KVNamespace, key: []const u8, options: GetOptions) ?KVTextMetadata {
        const strMeta = self.getStringWithMetadata(key, options);
        if (strMeta == null) return null;
        defer strMeta.?.value.free();
        return KVTextMetadata.init(strMeta.?.value.value(), strMeta.?.metadata);
    }

    /// Get a value as a JavaScript Object (parsed JSON).
    ///
    /// Returns `null` if the key doesn't exist. Remember to `free()` the Object.
    /// For typed access, prefer `getJSON()` instead.
    pub fn getObject(self: *const KVNamespace, key: []const u8, options: GetOptions) ?Object {
        const result = self._get(key, options, "json");
        if (result <= DefaultValueSize) return null;
        return Object{ .id = result };
    }

    /// Value and metadata returned from `getObjectWithMetadata`.
    pub const KVObjectMetadata = struct {
        value: Object,
        metadata: ?Object,

        pub fn init(valuePtr: u32, metaPtr: u32) KVObjectMetadata {
            var metadata: ?Object = null;
            if (metaPtr > DefaultValueSize) metadata = Object.init(metaPtr);
            return KVObjectMetadata{
                .value = Object.init(valuePtr),
                .metadata = metadata,
            };
        }

        pub fn free(self: *const KVObjectMetadata) void {
            self.value.free();
            self.metadata.?.free();
        }
    };

    /// Get a JSON object value along with its metadata.
    pub fn getObjectWithMetadata(self: *const KVNamespace, key: []const u8, options: GetOptions) ?KVObjectMetadata {
        const result = self._getMeta(key, options, "json");
        if (result <= DefaultValueSize) return null;
        const resObj = Object.init(result);
        defer resObj.free();
        return KVObjectMetadata.init(resObj.get("value"), resObj.get("metadata"));
    }

    /// Get a JSON value and parse it directly into a Zig struct.
    ///
    /// This is the most ergonomic way to retrieve structured data from KV.
    /// Automatically parses the JSON and returns a typed value.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const User = struct {
    ///     id: u32,
    ///     name: []const u8,
    ///     email: []const u8,
    /// };
    ///
    /// if (kv.getJSON(User, "user:123", .{})) |user| {
    ///     ctx.json(.{
    ///         .id = user.id,
    ///         .name = user.name,
    ///     }, 200);
    /// } else {
    ///     ctx.json(.{ .err = "User not found" }, 404);
    /// }
    /// ```
    pub fn getJSON(self: *const KVNamespace, comptime T: type, key: []const u8, options: GetOptions) ?T {
        // grab the data as a string
        const text = self.getText(key, options) orelse return null;
        defer allocator.free(text);
        // Zig 0.11+ uses parseFromSlice instead of TokenStream
        const parsed = std.json.parseFromSlice(T, allocator, text, .{
            .ignore_unknown_fields = true,
        }) catch return null;
        defer parsed.deinit();
        return parsed.value;
    }

    /// Get a value as a JavaScript ArrayBuffer.
    ///
    /// Returns `null` if the key doesn't exist. Remember to `free()` the ArrayBuffer.
    /// For most cases, prefer `getBytes()` which returns a Zig slice directly.
    pub fn getArrayBuffer(self: *const KVNamespace, key: []const u8, options: GetOptions) ?ArrayBuffer {
        const result = self._get(key, options, "arrayBuffer");
        if (result <= DefaultValueSize) return null;
        return ArrayBuffer{ .id = result };
    }

    /// Value and metadata returned from `getArrayBufferWithMetadata`.
    pub const KVArrayBufferMetadata = struct {
        value: ArrayBuffer,
        metadata: ?Object,

        pub fn init(valuePtr: u32, metaPtr: u32) KVArrayBufferMetadata {
            var metadata: ?Object = null;
            if (metaPtr > DefaultValueSize) metadata = Object.init(metaPtr);
            return KVArrayBufferMetadata{
                .value = ArrayBuffer.init(valuePtr),
                .metadata = metadata,
            };
        }

        pub fn free(self: *const KVArrayBufferMetadata) void {
            self.value.free();
            self.metadata.?.free();
        }
    };

    /// Get an ArrayBuffer value along with its metadata.
    pub fn getArrayBufferWithMetadata(self: *const KVNamespace, key: []const u8, options: GetOptions) ?KVArrayBufferMetadata {
        const result = self._getMeta(key, options, "arrayBuffer");
        if (result <= DefaultValueSize) return null;
        const resObj = Object.init(result);
        defer resObj.free();
        return KVArrayBufferMetadata.init(resObj.get("value"), resObj.get("metadata"));
    }

    /// Get a value as raw bytes.
    ///
    /// Returns `null` if the key doesn't exist.
    /// **Note**: The caller must free the returned bytes with `allocator.free()`.
    ///
    /// ## Example
    ///
    /// ```zig
    /// if (kv.getBytes("image:123", .{})) |data| {
    ///     defer std.heap.page_allocator.free(data);
    ///     // Process binary data...
    /// }
    /// ```
    pub fn getBytes(self: *const KVNamespace, key: []const u8, options: GetOptions) ?[]const u8 {
        const ab = self.getArrayBuffer(key, options) orelse return null;
        defer ab.free();
        return ab.bytes();
    }

    /// Value and metadata returned from `getBytesWithMetadata`.
    pub const KVBytesMetadata = struct {
        value: []const u8,
        metadata: ?Object,

        pub fn init(value: []const u8, metadata: ?Object) KVBytesMetadata {
            return KVBytesMetadata{
                .value = value,
                .metadata = metadata,
            };
        }

        /// Free the allocated bytes and metadata object.
        pub fn free(self: *const KVBytesMetadata) void {
            allocator.free(self.value);
            self.metadata.?.free();
        }
    };

    /// Get raw bytes along with metadata.
    pub fn getBytesWithMetadata(self: *const KVNamespace, key: []const u8, options: GetOptions) ?KVBytesMetadata {
        const abMeta = self.getArrayBufferWithMetadata(key, options);
        if (abMeta == null) return null;
        defer abMeta.?.value.free();
        return KVBytesMetadata.init(abMeta.?.value.bytes(), abMeta.?.metadata);
    }

    /// Get a value as a ReadableStream for streaming large values.
    ///
    /// Useful for large values that shouldn't be loaded entirely into memory.
    /// Returns `null` if the key doesn't exist.
    pub fn getStream(self: *const KVNamespace, key: []const u8, options: GetOptions) ?ReadableStream {
        const result = self._get(key, options, "stream");
        if (result <= DefaultValueSize) return null;
        return ReadableStream.init(result);
    }

    /// Value and metadata returned from `getStreamWithMetadata`.
    pub const KVStreamMetadata = struct {
        value: ReadableStream,
        metadata: ?Object,

        pub fn init(valuePtr: u32, metaPtr: u32) KVStreamMetadata {
            var metadata: ?Object = null;
            if (metaPtr > DefaultValueSize) metadata = Object.init(metaPtr);
            return KVStreamMetadata{
                .value = ReadableStream.init(valuePtr),
                .metadata = metadata,
            };
        }

        pub fn free(self: *const KVStreamMetadata) void {
            self.value.free();
            self.metadata.?.free();
        }
    };

    /// Get a stream value along with its metadata.
    pub fn getStreamWithMetadata(self: *const KVNamespace, key: []const u8, options: GetOptions) ?KVStreamMetadata {
        const result = self._getMeta(key, options, "stream");
        if (result <= DefaultValueSize) return null;
        const resObj = Object.init(result);
        defer resObj.free();
        return KVStreamMetadata.init(resObj.get("value"), resObj.get("metadata"));
    }

    /// Delete a key from KV.
    ///
    /// This operation is idempotent - deleting a non-existent key succeeds silently.
    ///
    /// ## Example
    ///
    /// ```zig
    /// kv.delete("user:123");
    /// kv.delete("session:abc");
    /// ctx.json(.{ .deleted = true }, 200);
    /// ```
    pub fn delete(self: *const KVNamespace, key: []const u8) void {
        // prep the string
        const str = String.new(key);
        defer str.free();
        // grab the function
        const func = AsyncFunction{ .id = getObjectValue(self.id, "delete") };
        defer func.free();

        _ = func.callArgsID(str.id);
    }

    /// List keys in the namespace.
    ///
    /// Returns a `ListResult` containing keys and pagination information.
    /// Use `prefix` to filter keys and `cursor` for pagination.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // List all keys with a prefix
    /// const result = kv.list(.{ .prefix = "user:", .limit = 100 });
    /// defer result.free();
    ///
    /// var keys = result.keys();
    /// defer keys.free();
    ///
    /// while (keys.next()) |key| {
    ///     defer key.free();
    ///     const name = key.name();
    ///     // Process each key...
    /// }
    ///
    /// // Check if there are more pages
    /// if (!result.listComplete()) {
    ///     const next_cursor = result.cursor();
    ///     // Store cursor for next page
    /// }
    /// ```
    pub fn list(self: *const KVNamespace, options: ListOptions) ListResult {
        // prep the opts
        const opts = options.toObject();
        defer opts.free();
        // grab the function
        const func = AsyncFunction{ .id = getObjectValue(self.id, "list") };
        defer func.free();

        return ListResult.init(func.callArgsID(opts.id));
    }
};
