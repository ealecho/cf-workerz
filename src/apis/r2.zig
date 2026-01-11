//! Cloudflare R2 - S3-compatible object storage.
//!
//! R2 is Cloudflare's object storage solution, offering S3-compatible APIs
//! with zero egress fees. Store and retrieve any amount of data with high
//! durability and availability.
//!
//! ## Quick Start
//!
//! ```zig
//! fn handleR2(ctx: *FetchContext) void {
//!     const bucket = ctx.env.r2("MY_BUCKET") orelse {
//!         ctx.throw(500, "R2 bucket not configured");
//!         return;
//!     };
//!     defer bucket.free();
//!
//!     // Put an object
//!     const obj = bucket.put("hello.txt", .{ .text = "Hello, World!" }, .{});
//!     defer obj.free();
//!
//!     // Get an object
//!     const result = bucket.get("hello.txt", .{});
//!     defer result.free();
//!     switch (result) {
//!         .r2objectBody => |body| {
//!             const data = body.text();
//!             ctx.text(data, 200);
//!         },
//!         .r2object => |_| ctx.noContent(), // Conditional request - not modified
//!         .none => ctx.json(.{ .err = "Not found" }, 404),
//!     }
//!
//!     // Delete an object
//!     bucket.delete("hello.txt");
//!
//!     // List objects
//!     const list = bucket.list(.{ .prefix = "uploads/", .limit = 100 });
//!     defer list.free();
//! }
//! ```
//!
//! ## Configuration
//!
//! Add to your `wrangler.toml`:
//!
//! ```toml
//! [[r2_buckets]]
//! binding = "MY_BUCKET"
//! bucket_name = "my-bucket-name"
//! ```

const std = @import("std");
const allocator = std.heap.page_allocator;
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const Null = common.Null;
const True = common.True;
const DefaultValueSize = common.DefaultValueSize;
const object = @import("../bindings/object.zig");
const Object = object.Object;
const getObjectValue = object.getObjectValue;
const getObjectValueNum = object.getObjectValueNum;
const ArrayBuffer = @import("../bindings/arraybuffer.zig").ArrayBuffer;
const string = @import("../bindings/string.zig");
const String = string.String;
const getStringFree = string.getStringFree;
const Array = @import("../bindings/array.zig").Array;
const ReadableStream = @import("../bindings/streams/readable.zig").ReadableStream;
const AsyncFunction = @import("../bindings/function.zig").AsyncFunction;
const Blob = @import("../bindings/blob.zig").Blob;
const Date = @import("../bindings/date.zig").Date;
const Headers = @import("../bindings/headers.zig").Headers;
const Record = @import("../bindings/record.zig").Record;

/// Value types that can be stored in R2.
///
/// R2 supports storing text, binary data, streams, and blobs.
///
/// ## Variants
///
/// | Variant | Use Case |
/// |---------|----------|
/// | `.text` | UTF-8 strings (most common) |
/// | `.bytes` | Binary data as `[]const u8` |
/// | `.readableStream` | Streaming data |
/// | `.arrayBuffer` | Raw ArrayBuffer from JS |
/// | `.blob` | Binary large object |
/// | `.none` | Empty/null value |
///
/// ## Example
///
/// ```zig
/// // Store text
/// bucket.put("doc.txt", .{ .text = "Hello!" }, .{});
///
/// // Store binary
/// bucket.put("image.png", .{ .bytes = png_data }, .{});
/// ```
pub const R2Value = union(enum) {
    readableStream: *const ReadableStream,
    string: *const String,
    text: []const u8,
    object: *const Object,
    arrayBuffer: *const ArrayBuffer,
    bytes: []const u8,
    blob: *const Blob,
    none,

    pub fn toID(self: *const R2Value) u32 {
        switch (self.*) {
            .readableStream => |rs| return rs.id,
            .string => |s| return s.id,
            .text => |t| return String.new(t).id,
            .object => |obj| return obj.stringify().id,
            .arrayBuffer => |ab| return ab.id,
            .bytes => |b| return ArrayBuffer.new(b).id,
            .blob => |blob| return blob.id,
            .none => return Null,
        }
    }

    pub fn free(self: *const R2Value, id: u32) void {
        switch (self.*) {
            .text => jsFree(id),
            .object => jsFree(id),
            .bytes => jsFree(id),
            else => {},
        }
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1066

/// HTTP metadata for R2 objects.
///
/// Standard HTTP headers that can be stored with objects and returned
/// when the object is retrieved. Use `writeHttpMetadata()` to copy
/// these to response headers.
///
/// ## Fields
///
/// - `contentType`: MIME type (e.g., "text/html", "image/png")
/// - `contentLanguage`: Content language (e.g., "en-US")
/// - `contentDisposition`: Download behavior (e.g., "attachment; filename=file.pdf")
/// - `contentEncoding`: Encoding (e.g., "gzip")
/// - `cacheControl`: Cache directives (e.g., "max-age=3600")
/// - `cacheExpiry`: Absolute expiration date
pub const R2HTTPMetadata = struct {
    contentType: ?[]const u8 = null,
    contentLanguage: ?[]const u8 = null,
    contentDisposition: ?[]const u8 = null,
    contentEncoding: ?[]const u8 = null,
    cacheControl: ?[]const u8 = null,
    cacheExpiry: ?Date = null,

    pub fn fromObject(r2Object: *const Object) R2HTTPMetadata {
        var contentType: ?[]const u8 = null;
        var contentLanguage: ?[]const u8 = null;
        var contentDisposition: ?[]const u8 = null;
        var contentEncoding: ?[]const u8 = null;
        var cacheControl: ?[]const u8 = null;
        var cacheExpiry: ?Date = null;
        if (r2Object.has("contentType")) contentType = getStringFree(getObjectValue(r2Object.id, "contentType"));
        if (r2Object.has("contentLanguage")) contentLanguage = getStringFree(getObjectValue(r2Object.id, "contentLanguage"));
        if (r2Object.has("contentDisposition")) contentDisposition = getStringFree(getObjectValue(r2Object.id, "contentDisposition"));
        if (r2Object.has("contentEncoding")) contentEncoding = getStringFree(getObjectValue(r2Object.id, "contentEncoding"));
        if (r2Object.has("cacheControl")) cacheControl = getStringFree(getObjectValue(r2Object.id, "cacheControl"));
        if (r2Object.has("cacheExpiry")) cacheExpiry = Date.init(getObjectValue(r2Object.id, "cacheExpiry"));
        return R2HTTPMetadata{
            .contentType = contentType,
            .contentLanguage = contentLanguage,
            .contentDisposition = contentDisposition,
            .contentEncoding = contentEncoding,
            .cacheControl = cacheControl,
            .cacheExpiry = cacheExpiry,
        };
    }

    pub fn toObject(self: *const R2HTTPMetadata) Object {
        const obj = Object.new();
        if (self.contentType) |ct| obj.setText("contentType", ct);
        if (self.contentLanguage) |cl| obj.setText("contentLanguage", cl);
        if (self.contentDisposition) |cd| obj.setText("contentDisposition", cd);
        if (self.contentEncoding) |ce| obj.setText("contentEncoding", ce);
        if (self.cacheControl) |cc| obj.setText("cacheControl", cc);
        if (self.cacheExpiry) |ce| obj.set("cacheExpiry", &ce);
        return obj;
    }

    /// Write HTTP metadata as response headers.
    ///
    /// Copies content-type, cache-control, and other HTTP metadata
    /// to the provided Headers object.
    pub fn writeHttpMetadata(self: *const R2HTTPMetadata, headers: Headers) void {
        if (self.contentType) |ct| headers.setText("Content-Type", ct);
        if (self.contentLanguage) |cl| headers.setText("Content-Language", cl);
        if (self.contentDisposition) |cd| headers.setText("Content-Disposition", cd);
        if (self.contentEncoding) |ce| headers.setText("Content-Encoding", ce);
        if (self.cacheControl) |cc| headers.setText("Cache-Control", cc);
        if (self.cacheExpiry) |ce| headers.set("Cache-Expiry", ce);
    }
};

/// Byte range for partial object retrieval.
///
/// Use to request only a portion of an object, useful for resumable
/// downloads or streaming large files.
///
/// ## Fields
///
/// - `offset`: Start position in bytes
/// - `length`: Number of bytes to retrieve
/// - `suffix`: Get the last N bytes (alternative to offset/length)
pub const R2Range = struct {
    offset: ?u64 = null,
    length: ?u64 = null,
    suffix: ?u64 = null,

    pub fn fromObject(r2Object: *const Object) R2Range {
        var offset: ?u64 = null;
        var length: ?u64 = null;
        var suffix: ?u64 = null;
        if (r2Object.has("offset")) offset = r2Object.getNum("offset", u64);
        if (r2Object.has("length")) length = r2Object.getNum("length", u64);
        if (r2Object.has("suffix")) suffix = r2Object.getNum("suffix", u64);
        return R2Range{ .offset = offset, .length = length, .suffix = suffix };
    }

    pub fn toObject(self: *const R2Range) Object {
        const obj = Object.new();

        if (self.offset) |o| obj.setNum("offset", u64, o);
        if (self.length) |l| obj.setNum("length", u64, l);
        if (self.suffix) |s| obj.setNum("suffix", u64, s);

        return obj;
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1099

/// Metadata for an R2 object (without body).
///
/// Returned from `head()` operations or conditional `get()` requests
/// where the body wasn't modified. Contains object metadata like key,
/// size, etag, and upload time.
///
/// ## Example
///
/// ```zig
/// if (bucket.head("file.txt")) |obj| {
///     defer obj.free();
///     const size = obj.size();
///     const etag = obj.etag();
///     const uploaded = obj.uploaded();
/// }
/// ```
pub const R2Object = struct {
    id: u32,

    pub fn init(jsPtr: u32) R2Object {
        return R2Object{ .id = jsPtr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const R2Object) void {
        jsFree(self.id);
    }

    /// Get the object's key (path/name in the bucket).
    pub fn key(self: *const R2Object) []const u8 {
        return getStringFree(getObjectValue(self.id, "key"));
    }

    /// Get the object's version ID.
    pub fn version(self: *const R2Object) []const u8 {
        return getStringFree(getObjectValue(self.id, "version"));
    }

    /// Get the object's size in bytes.
    pub fn size(self: *const R2Object) u64 {
        return getObjectValueNum(self.id, "size", u64);
    }

    /// Get the object's ETag (entity tag for caching/versioning).
    pub fn etag(self: *const R2Object) []const u8 {
        return getStringFree(getObjectValue(self.id, "etag"));
    }

    /// Get the HTTP-formatted ETag (with quotes).
    pub fn httpEtag(self: *const R2Object) []const u8 {
        return getStringFree(getObjectValue(self.id, "httpEtag"));
    }

    /// Get the upload timestamp as a Date object.
    pub fn uploaded(self: *const R2Object) Date {
        return Date.init(getObjectValue(self.id, "uploaded"));
    }

    /// Get the HTTP metadata (content-type, cache-control, etc.).
    pub fn httpMetadata(self: *const R2Object) R2HTTPMetadata {
        const obj = Object.init(getObjectValue(self.id, "httpMetadata"));
        defer obj.free();
        return R2HTTPMetadata.fromObject(&obj);
    }

    /// Get custom metadata as a key-value Record.
    pub fn customMetadata(self: *const R2Object) Record {
        return Record.init(getObjectValue(self.id, "customMetadata"));
    }

    /// Get the byte range if this was a partial response.
    pub fn range(self: *const R2Object) ?R2Range {
        const r2rangeID = getObjectValue(self.id, "range");
        if (r2rangeID <= DefaultValueSize) return null;
        const r2range = Object.init(r2rangeID);
        defer r2range.free();
        return R2Range.fromObject(&r2range);
    }

    /// Write HTTP metadata to response headers.
    ///
    /// Convenience method to copy content-type, cache-control, etc.
    /// from this object to response headers.
    pub fn writeHttpMetadata(self: *const R2Object, headers: Headers) void {
        const httpMeta = self.httpMetadata();
        httpMeta.writeHttpMetadata(headers);
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1115

/// An R2 object with its body content.
///
/// Returned from successful `get()` operations. Contains both metadata
/// and the object's body, which can be read as text, bytes, JSON, or stream.
///
/// ## Example
///
/// ```zig
/// const result = bucket.get("data.json", .{});
/// defer result.free();
///
/// switch (result) {
///     .r2objectBody => |body| {
///         // Read as text
///         const text = body.text();
///
///         // Or parse as JSON
///         const Data = struct { id: u32, name: []const u8 };
///         if (body.json(Data)) |data| {
///             // Use data.id, data.name
///         }
///
///         // Get metadata
///         const size = body.size();
///         const content_type = body.httpMetadata().contentType;
///     },
///     .r2object => |_| {}, // Conditional: not modified
///     .none => {}, // Not found
/// }
/// ```
pub const R2ObjectBody = struct {
    id: u32,

    pub fn init(jsPtr: u32) R2ObjectBody {
        return R2ObjectBody{ .id = jsPtr };
    }

    /// Release the JavaScript object. Always call when done.
    pub fn free(self: *const R2ObjectBody) void {
        jsFree(self.id);
    }

    /// Check if the body has already been consumed.
    pub fn bodyUsed(self: *const R2ObjectBody) bool {
        const used = getObjectValue(self.id, "bodyUsed");
        return used == True;
    }

    /// Get the body as a ReadableStream for streaming.
    pub fn body(self: *const R2ObjectBody) ReadableStream {
        return ReadableStream.init(getObjectValue(self.id, "body"));
    }

    /// Get the body as an ArrayBuffer.
    pub fn arrayBuffer(self: *const R2ObjectBody) ArrayBuffer {
        const func = AsyncFunction.init(getObjectValue(self.id, "arrayBuffer"));
        defer func.free();

        return ArrayBuffer.init(func.call());
    }

    /// Get the body as raw bytes.
    ///
    /// **Note**: Caller must free with `std.heap.page_allocator.free()`.
    pub fn bytes(self: *const R2ObjectBody) []const u8 {
        const func = AsyncFunction.init(getObjectValue(self.id, "arrayBuffer"));
        defer func.free();

        const ab = ArrayBuffer.init(func.call());
        defer ab.free();
        return ab.bytes();
    }

    /// Get the body as a JavaScript String object.
    pub fn string(self: *const R2ObjectBody) String {
        const func = AsyncFunction.init(getObjectValue(self.id, "text"));
        defer func.free();

        return String.init(func.call());
    }

    /// Get the body as a Zig string slice.
    ///
    /// **Note**: Caller must free with `std.heap.page_allocator.free()`.
    pub fn text(self: *const R2ObjectBody) []const u8 {
        const func = AsyncFunction.init(getObjectValue(self.id, "text"));
        defer func.free();

        return getStringFree(func.call());
    }

    /// Get the body as a JavaScript Object (parsed JSON).
    pub fn object(self: *const R2ObjectBody) Object {
        const func = AsyncFunction.init(getObjectValue(self.id, "json"));
        defer func.free();

        return Object.init(func.call());
    }

    /// Parse the body as JSON into a Zig struct.
    ///
    /// Returns `null` if parsing fails.
    pub fn json(self: *const R2ObjectBody, comptime T: type) ?T {
        const str = self.text();
        defer allocator.free(str);
        // Zig 0.11+ uses parseFromSlice instead of TokenStream
        const parsed = std.json.parseFromSlice(T, allocator, str, .{
            .ignore_unknown_fields = true,
        }) catch return null;
        defer parsed.deinit();
        return parsed.value;
    }

    /// Get the body as a Blob object.
    pub fn blob(self: *const R2ObjectBody) Blob {
        const func = AsyncFunction.init(getObjectValue(self.id, "blob"));
        defer func.free();

        return Blob.init(func.call());
    }

    /// Get the object's key (path/name in the bucket).
    pub fn key(self: *const R2ObjectBody) []const u8 {
        return getStringFree(getObjectValue(self.id, "key"));
    }

    /// Get the object's version ID.
    pub fn version(self: *const R2ObjectBody) []const u8 {
        return getStringFree(getObjectValue(self.id, "version"));
    }

    /// Get the object's size in bytes.
    pub fn size(self: *const R2ObjectBody) u64 {
        return getObjectValueNum(self.id, "size", u64);
    }

    /// Get the object's ETag.
    pub fn etag(self: *const R2ObjectBody) []const u8 {
        return getStringFree(getObjectValue(self.id, "etag"));
    }

    /// Get the HTTP-formatted ETag (with quotes).
    pub fn httpEtag(self: *const R2ObjectBody) []const u8 {
        return getStringFree(getObjectValue(self.id, "httpEtag"));
    }

    /// Get the upload timestamp.
    pub fn uploaded(self: *const R2ObjectBody) Date {
        return Date.init(getObjectValue(self.id, "uploaded"));
    }

    /// Get the HTTP metadata (content-type, cache-control, etc.).
    pub fn httpMetadata(self: *const R2ObjectBody) R2HTTPMetadata {
        const obj = Object.init(getObjectValue(self.id, "httpMetadata"));
        defer obj.free();
        return R2HTTPMetadata.fromObject(&obj);
    }

    /// Get custom metadata as a key-value Record.
    pub fn customMetadata(self: *const R2ObjectBody) Record {
        return Record.init(getObjectValue(self.id, "customMetadata"));
    }

    /// Get the byte range if this was a partial response.
    pub fn range(self: *const R2ObjectBody) ?R2Range {
        const r2rangeID = getObjectValue(self.id, "range");
        if (r2rangeID <= DefaultValueSize) return null;
        const r2range = Object.init(r2rangeID);
        defer r2range.free();
        return R2Range.fromObject(&r2range);
    }

    /// Write HTTP metadata to response headers.
    pub fn writeHttpMetadata(self: *const R2ObjectBody, headers: Headers) void {
        const httpMeta = self.httpMetadata();
        httpMeta.writeHttpMetadata(headers);
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1124

/// Result from an R2 list operation.
///
/// Contains objects matching the list query, pagination info, and
/// delimited prefixes for hierarchical listing.
///
/// ## Example
///
/// ```zig
/// const result = bucket.list(.{ .prefix = "uploads/", .limit = 100 });
/// defer result.free();
///
/// var objects = result.objects();
/// defer objects.free();
///
/// while (objects.next()) |obj| {
///     defer obj.free();
///     const key = obj.key();
///     const size = obj.size();
///     // Process object...
/// }
///
/// if (result.truncated()) {
///     const next_cursor = result.cursor();
///     // Use cursor for next page
/// }
/// ```
pub const R2Objects = struct {
    id: u32,

    pub fn init(jsPtr: u32) R2Objects {
        return R2Objects{ .id = jsPtr };
    }

    /// Release the JavaScript object.
    pub fn free(self: *const R2Objects) void {
        jsFree(self.id);
    }

    /// Get an iterator over the objects in this result.
    pub fn objects(self: *const R2Objects) ListR2Objects {
        return ListR2Objects.init(getObjectValue(self.id, "objects"));
    }

    /// Check if results were truncated (more pages available).
    pub fn truncated(self: *const R2Objects) bool {
        const trunc = getObjectValue(self.id, "truncated");
        return trunc == True;
    }

    /// Get the pagination cursor for the next page.
    pub fn cursor(self: *const R2Objects) []const u8 {
        return getStringFree(getObjectValue(self.id, "cursor"));
    }

    /// Get delimited prefixes (for hierarchical listing with delimiter).
    pub fn delimitedPrefixes(self: *const R2Objects) ListDelimitedPrefixes {
        return ListDelimitedPrefixes.init(getObjectValue(self.id, "delimitedPrefixes"));
    }

    /// Iterator over R2 objects in a list result.
    pub const ListR2Objects = struct {
        arr: Array,
        pos: u32 = 0,
        len: u32,

        pub fn init(jsPtr: u32) ListR2Objects {
            const arr = Array.init(jsPtr);
            return ListR2Objects{
                .arr = arr,
                .len = arr.length(),
            };
        }

        pub fn free(self: *const ListR2Objects) void {
            self.arr.free();
        }

        /// Get the next object, or `null` if exhausted.
        pub fn next(self: *ListR2Objects) ?R2Object {
            if (self.pos == self.len) return null;
            const r2object = self.arr.getType(R2Object, self.pos);
            self.pos += 1;
            return r2object;
        }
    };

    /// Iterator over delimited prefixes in a list result.
    pub const ListDelimitedPrefixes = struct {
        arr: Array,
        pos: u32 = 0,
        len: u32,

        pub fn init(jsPtr: u32) ListDelimitedPrefixes {
            const arr = Array.init(jsPtr);
            return ListDelimitedPrefixes{
                .arr = arr,
                .len = arr.length(),
            };
        }

        pub fn free(self: *const ListDelimitedPrefixes) void {
            self.arr.free();
        }

        /// Get the next prefix, or `null` if exhausted.
        pub fn next(self: *ListDelimitedPrefixes) ?String {
            if (self.pos == self.len) return null;
            const str = self.arr.getType(String, self.pos);
            self.pos += 1;
            return str;
        }
    };
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1040

/// Conditional request options for R2 get/head operations.
///
/// Use to implement caching and conditional retrieval based on
/// ETag or upload time.
pub const R2Conditional = struct {
    etagMatches: ?[]const u8 = null,
    etagDoesNotMatch: ?[]const u8 = null,
    uploadedBefore: ?Date = null,
    uploadedAfter: ?Date = null,

    pub fn toObject(self: *const R2Conditional) Object {
        const obj = Object.new();
        if (self.etagMatches) |em| obj.setText("etagMatches", em);
        if (self.etagDoesNotMatch) |ednm| obj.setText("etagDoesNotMatch", ednm);
        if (self.uploadedBefore) |ub| obj.set("uploadedBefore", ub);
        if (self.uploadedAfter) |ua| obj.set("uploadedBefore", ua);
        return obj;
    }
};

/// Union type for conditional get requests.
///
/// Either use `R2Conditional` struct or pass request Headers directly
/// (which will extract If-Match, If-None-Match, etc.).
pub const OnlyIf = union(enum) {
    r2Conditional: R2Conditional,
    headers: *const Headers,

    pub fn toID(self: *const OnlyIf) u32 {
        switch (self.*) {
            .r2Conditional => |c| return c.toObject().id,
            .headers => |h| return h.id,
        }
    }

    pub fn free(self: *const OnlyIf, id: u32) void {
        switch (self.*) {
            .r2Conditional => jsFree(id),
            .headers => {},
        }
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1050

/// Options for R2 get operations.
///
/// ## Fields
///
/// - `onlyIf`: Conditional retrieval (etag matching, etc.)
/// - `range`: Byte range for partial retrieval
///
/// ## Example
///
/// ```zig
/// // Simple get
/// const result = bucket.get("file.txt", .{});
///
/// // Conditional get (304 if not modified)
/// const result = bucket.get("file.txt", .{
///     .onlyIf = .{ .r2Conditional = .{ .etagMatches = etag } },
/// });
///
/// // Partial get (first 1KB)
/// const result = bucket.get("large.bin", .{
///     .range = .{ .offset = 0, .length = 1024 },
/// });
/// ```
pub const R2GetOptions = struct {
    onlyIf: ?OnlyIf = null,
    range: ?R2Range = null,

    pub fn toObject(self: *const R2GetOptions) Object {
        const obj = Object.new();
        if (self.onlyIf) |oi| {
            const oiID = oi.toID();
            defer oi.free(oiID);
            obj.setID("onlyIf", oiID);
        }
        if (self.range) |r| {
            const orObj = r.toObject();
            defer orObj.free();
            obj.set("range", orObj);
        }

        return obj;
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1131

/// Options for R2 put operations.
///
/// ## Fields
///
/// - `httpMetadata`: HTTP headers to store (content-type, cache-control, etc.)
/// - `customMetadata`: Custom key-value metadata
/// - `md5*`: MD5 checksum for data integrity verification
///
/// ## Example
///
/// ```zig
/// // Simple put
/// bucket.put("file.txt", .{ .text = "Hello" }, .{});
///
/// // With content type
/// const meta = R2HTTPMetadata{ .contentType = "text/html" };
/// bucket.put("page.html", .{ .text = html }, .{ .httpMetadata = &meta });
/// ```
pub const R2PutOptions = struct {
    httpMetadata: ?*const R2HTTPMetadata = null,
    headers: ?*const Headers = null,
    customMetadata: ?*const Object = null,
    md5String: ?*const String = null,
    md5Text: ?[]const u8 = null,
    md5ArrayBuffer: ?*const ArrayBuffer = null,
    md5Bytes: ?[]const u8 = null,

    pub fn toObject(self: *const R2PutOptions) Object {
        const obj = Object.new();
        if (self.httpMetadata) |m| {
            const mObj = m.toObject();
            defer mObj.free();
            obj.set("httpMetadata", mObj);
        }
        if (self.headers) |h| obj.set("httpMetadata", h);
        if (self.customMetadata) |cm| obj.set("customMetadata", cm);
        if (self.md5String) |md5| obj.set("md5", md5);
        if (self.md5Text) |md5| obj.setText("md5", md5);
        if (self.md5ArrayBuffer) |md5| obj.set("md5", md5);
        if (self.md5Bytes) |md5| {
            const ab = ArrayBuffer.new(md5);
            defer ab.free();
            obj.set("md5", ab);
        }
        return obj;
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L948

/// Options for listing objects in an R2 bucket.
///
/// ## Fields
///
/// - `limit`: Maximum objects to return (default 1000)
/// - `prefix`: Only return objects with this prefix
/// - `cursor`: Pagination cursor from previous list
/// - `delimiter`: Group objects by this delimiter (for hierarchical listing)
/// - `includeHttpMetadata`: Include HTTP metadata in results
/// - `includeCustomMetadata`: Include custom metadata in results
pub const R2ListOptions = struct {
    limit: u16 = 1_000,
    prefix: ?[]const u8 = null,
    jsPrefix: ?*const String = null,
    cursor: ?[]const u8 = null,
    jsCursor: ?*const String = null,
    delimiter: ?[]const u8 = null,
    jsDelimiter: ?*const String = null,
    includeHttpMetadata: bool = false,
    includeCustomMetadata: bool = false,

    pub fn toObject(self: *const R2ListOptions) Object {
        const obj = Object.new();

        obj.setNum("limit", u16, self.limit);
        if (self.prefix) |p| obj.setText("prefix", p);
        if (self.jsPrefix) |jsp| obj.set("jspefix", jsp);
        if (self.cursor) |c| obj.setText("cursor", c);
        if (self.jsCursor) |jsc| obj.set("cursor", jsc);
        if (self.delimiter) |d| obj.setText("delimiter", d);
        if (self.jsDelimiter) |jsd| obj.set("delimiter", jsd);
        if (self.includeHttpMetadata or self.includeCustomMetadata) {
            const arr = Array.new();
            defer arr.free();
            if (self.includeHttpMetadata) arr.pushText("httpMetadata");
            if (self.includeCustomMetadata) arr.pushText("customMetadata");
            obj.set("include", &arr);
        }

        return obj;
    }
};

/// Response from an R2 get operation.
///
/// ## Variants
///
/// - `.r2objectBody`: Object found with body content
/// - `.r2object`: Conditional request - object not modified (no body)
/// - `.none`: Object not found
pub const R2GetResponse = union(enum) {
    r2object: R2Object,
    r2objectBody: R2ObjectBody,
    none,

    pub fn free(self: *const R2GetResponse) void {
        switch (self.*) {
            .r2object => |obj| obj.free(),
            .r2objectBody => |objBod| objBod.free(),
            .none => {},
        }
    }
};

// https://github.com/cloudflare/workers-types/blob/master/index.d.ts#L1008

/// Cloudflare R2 Bucket.
///
/// Provides methods to store, retrieve, and manage objects in R2.
///
/// ## Getting a Bucket
///
/// ```zig
/// fn handler(ctx: *FetchContext) void {
///     const bucket = ctx.env.r2("MY_BUCKET") orelse {
///         ctx.throw(500, "R2 bucket not found");
///         return;
///     };
///     defer bucket.free();
///
///     // Use bucket...
/// }
/// ```
///
/// ## Common Operations
///
/// ```zig
/// // Store an object
/// const obj = bucket.put("path/to/file.txt", .{ .text = "content" }, .{});
/// defer obj.free();
///
/// // Retrieve an object
/// const result = bucket.get("path/to/file.txt", .{});
/// defer result.free();
/// switch (result) {
///     .r2objectBody => |body| {
///         const text = body.text();
///         // Use content...
///     },
///     .none => {}, // Not found
///     .r2object => {}, // Conditional: not modified
/// }
///
/// // Check if object exists (head)
/// if (bucket.head("file.txt")) |obj| {
///     defer obj.free();
///     const size = obj.size();
/// }
///
/// // Delete an object
/// bucket.delete("file.txt");
///
/// // List objects
/// const list = bucket.list(.{ .prefix = "uploads/" });
/// defer list.free();
/// ```
pub const R2Bucket = struct {
    id: u32,

    pub fn init(ptr: u32) R2Bucket {
        return R2Bucket{ .id = ptr };
    }

    /// Release the JavaScript binding. Always call when done.
    pub fn free(self: *const R2Bucket) void {
        jsFree(self.id);
    }

    /// Get object metadata without retrieving the body.
    ///
    /// Returns `null` if the object doesn't exist. Useful for checking
    /// existence or getting size/etag without downloading content.
    ///
    /// ## Example
    ///
    /// ```zig
    /// if (bucket.head("file.txt")) |obj| {
    ///     defer obj.free();
    ///     const size = obj.size();
    ///     const etag = obj.etag();
    /// }
    /// ```
    pub fn head(self: *const R2Bucket, key: []const u8) ?R2Object {
        // prep the string
        const keyStr = String.new(key);
        defer keyStr.free();
        // grab the function
        const func = AsyncFunction.init(getObjectValue(self.id, "head"));
        defer func.free();

        const result = func.callArgsID(keyStr.id);
        if (result <= DefaultValueSize) return null;
        return R2Object{ .id = result };
    }

    /// Retrieve an object from the bucket.
    ///
    /// Returns an `R2GetResponse` union:
    /// - `.r2objectBody`: Object found with body
    /// - `.r2object`: Conditional request - not modified (no body)
    /// - `.none`: Object not found
    ///
    /// ## Example
    ///
    /// ```zig
    /// const result = bucket.get("data.json", .{});
    /// defer result.free();
    ///
    /// switch (result) {
    ///     .r2objectBody => |body| {
    ///         const text = body.text();
    ///         ctx.text(text, 200);
    ///     },
    ///     .r2object => |_| ctx.noContent(),
    ///     .none => ctx.json(.{ .err = "Not found" }, 404),
    /// }
    /// ```
    pub fn get(self: *const R2Bucket, key: []const u8, options: R2GetOptions) R2GetResponse {
        // prep the string
        const keyStr = String.new(key);
        defer keyStr.free();
        // grab options
        const opts = options.toObject();
        defer opts.free();
        // grab the function
        const func = AsyncFunction.init(getObjectValue(self.id, "get"));
        defer func.free();
        // prep the args
        const args = Array.new();
        defer args.free();
        args.push(&keyStr);
        args.push(&opts);

        const result = func.callArgsID(args.id);
        if (result <= DefaultValueSize) return R2GetResponse{ .none = {} };
        const hasBody = object.hasObject(result, "body");
        if (hasBody) return R2GetResponse{ .r2objectBody = R2ObjectBody.init(result) };
        return R2GetResponse{ .r2object = R2Object.init(result) };
    }

    /// Store an object in the bucket.
    ///
    /// Returns metadata about the stored object.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Store text
    /// const obj = bucket.put("file.txt", .{ .text = "Hello!" }, .{});
    /// defer obj.free();
    ///
    /// // Store with metadata
    /// const meta = R2HTTPMetadata{ .contentType = "application/json" };
    /// const obj = bucket.put("data.json", .{ .text = json }, .{
    ///     .httpMetadata = &meta,
    /// });
    /// ```
    pub fn put(self: *const R2Bucket, key: []const u8, value: R2Value, options: R2PutOptions) R2Object {
        // prep the string
        const keyStr = String.new(key);
        defer keyStr.free();
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
        args.push(&keyStr);
        args.pushID(val);
        args.push(&opts);

        return R2Object.init(func.callArgsID(args.id));
    }

    /// Delete an object from the bucket.
    ///
    /// This operation is idempotent - deleting a non-existent key succeeds.
    ///
    /// ## Example
    ///
    /// ```zig
    /// bucket.delete("old-file.txt");
    /// ```
    pub fn delete(self: *const R2Bucket, key: []const u8) void {
        // prep the string
        const str = String.new(key);
        defer str.free();
        // grab the function
        const func = AsyncFunction.init(getObjectValue(self.id, "delete"));
        defer func.free();

        _ = func.callArgsID(str.id);
    }

    /// List objects in the bucket.
    ///
    /// Returns an `R2Objects` result with objects and pagination info.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const result = bucket.list(.{
    ///     .prefix = "uploads/",
    ///     .limit = 100,
    /// });
    /// defer result.free();
    ///
    /// var objects = result.objects();
    /// defer objects.free();
    ///
    /// while (objects.next()) |obj| {
    ///     defer obj.free();
    ///     const key = obj.key();
    ///     const size = obj.size();
    /// }
    /// ```
    pub fn list(self: *const R2Bucket, options: R2ListOptions) R2Objects {
        // grab options
        const opts = options.toObject();
        defer opts.free();
        // grab the function
        const func = AsyncFunction.init(getObjectValue(self.id, "list"));
        defer func.free();

        return R2Objects.init(func.callArgsID(opts.id));
    }
};
