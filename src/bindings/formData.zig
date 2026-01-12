//! FormData and File bindings for the Web FormData API.
//!
//! FormData provides a way to construct a set of key/value pairs representing
//! form fields and their values, which can be used with fetch() or other APIs.
//!
//! ## Example Usage
//!
//! ```zig
//! // Create FormData from a request
//! var formData = ctx.bodyFormData() orelse {
//!     ctx.throw(400, "Invalid form data");
//!     return;
//! };
//! defer formData.free();
//!
//! // Get form field values
//! if (formData.get("username")) |entry| {
//!     switch (entry) {
//!         .field => |value| {
//!             // value is []const u8
//!         },
//!         .file => |file| {
//!             defer file.free();
//!             const filename = file.name();
//!             const content = file.text();
//!         },
//!     }
//! }
//!
//! // Create new FormData
//! const form = FormData.new();
//! defer form.free();
//! form.append("name", "Alice");
//! form.set("email", "alice@example.com");
//! ```

const String = @import("string.zig").String;
const Function = @import("function.zig").Function;
const Array = @import("array.zig").Array;
const object = @import("object.zig");
const common = @import("common.zig");
const Undefined = common.Undefined;
const True = common.True;
const Classes = common.Classes;
const JSValue = common.JSValue;
const jsCreateClass = common.jsCreateClass;
const jsFree = common.jsFree;
const getObjectValue = object.getObjectValue;

/// Options for creating a new File.
pub const FileOptions = struct {
    /// The MIME type of the file (e.g., "text/plain", "image/png").
    contentType: ?[]const u8 = null,
    /// The last modified timestamp (milliseconds since Unix epoch).
    lastModified: ?u64 = null,
};

/// Represents a file from a FormData entry.
///
/// File is a specific kind of Blob that represents file data with additional
/// metadata like filename and last modified time.
///
/// See: https://developer.mozilla.org/en-US/docs/Web/API/File
///
/// ## Example
///
/// ```zig
/// if (formData.get("upload")) |entry| {
///     switch (entry) {
///         .file => |file| {
///             defer file.free();
///             const name = file.name();       // "document.pdf"
///             const size = file.size();       // 12345
///             const mime = file.contentType(); // "application/pdf"
///             const content = file.text();    // file contents as string
///         },
///         .field => |_| {},
///     }
/// }
/// ```
pub const File = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) File {
        return File{ .id = ptr };
    }

    /// Create a new File from data and a filename.
    ///
    /// ## Example
    /// ```zig
    /// const data = "Hello, World!";
    /// const file = File.new(data, "hello.txt", .{});
    /// defer file.free();
    /// ```
    pub fn new(data: []const u8, filename: []const u8, options: FileOptions) File {
        // File constructor: new File(bits, name, options)
        // bits is an array of data parts
        const jsData = String.new(data);
        defer jsData.free();

        const bits = Array.new();
        defer bits.free();
        bits.push(&jsData);

        const jsName = String.new(filename);
        defer jsName.free();

        const args = Array.new();
        defer args.free();
        args.push(&bits);
        args.push(&jsName);

        // Add options if provided
        if (options.contentType != null or options.lastModified != null) {
            const opts = object.Object.new();
            defer opts.free();
            if (options.contentType) |ct| {
                opts.setText("type", ct);
            }
            if (options.lastModified) |lm| {
                opts.setNum("lastModified", f64, @floatFromInt(lm));
            }
            args.push(&opts);
        }

        return File{ .id = jsCreateClass(Classes.File.toInt(), args.id) };
    }

    /// Create a new File from bytes.
    ///
    /// ## Example
    /// ```zig
    /// const bytes = [_]u8{ 0x48, 0x65, 0x6c, 0x6c, 0x6f };
    /// const file = File.fromBytes(&bytes, "hello.bin", .{});
    /// defer file.free();
    /// ```
    pub fn fromBytes(data: []const u8, filename: []const u8, options: FileOptions) File {
        // Create Uint8Array from bytes
        const bufId = common.jsToBuffer(data.ptr, data.len);
        defer jsFree(bufId);

        const uint8Args = Array.new();
        defer uint8Args.free();
        uint8Args.pushID(bufId);

        const uint8ArrayId = jsCreateClass(Classes.Uint8Array.toInt(), uint8Args.id);
        defer jsFree(uint8ArrayId);

        // bits array containing the Uint8Array
        const bits = Array.new();
        defer bits.free();
        bits.pushID(uint8ArrayId);

        const jsName = String.new(filename);
        defer jsName.free();

        const args = Array.new();
        defer args.free();
        args.push(&bits);
        args.push(&jsName);

        if (options.contentType != null or options.lastModified != null) {
            const opts = object.Object.new();
            defer opts.free();
            if (options.contentType) |ct| {
                opts.setText("type", ct);
            }
            if (options.lastModified) |lm| {
                opts.setNum("lastModified", f64, @floatFromInt(lm));
            }
            args.push(&opts);
        }

        return File{ .id = jsCreateClass(Classes.File.toInt(), args.id) };
    }

    /// Free the File object from the JavaScript heap.
    pub fn free(self: *const File) void {
        jsFree(self.id);
    }

    /// Get the name of the file.
    ///
    /// ## Example
    /// ```zig
    /// const filename = file.name();  // "photo.jpg"
    /// ```
    pub fn name(self: *const File) []const u8 {
        return getStringProperty(self.id, "name");
    }

    /// Get the size of the file in bytes.
    ///
    /// ## Example
    /// ```zig
    /// const bytes = file.size();  // 1024
    /// ```
    pub fn size(self: *const File) u64 {
        const ptr = getObjectValue(self.id, "size");
        if (ptr <= common.DefaultValueSize) {
            return 0;
        }
        return common.getNum(ptr, u64);
    }

    /// Get the MIME type of the file.
    ///
    /// Returns an empty string if the type is unknown.
    ///
    /// ## Example
    /// ```zig
    /// const mime = file.contentType();  // "image/jpeg"
    /// ```
    pub fn contentType(self: *const File) []const u8 {
        return getStringProperty(self.id, "type");
    }

    /// Get the last modified timestamp (milliseconds since Unix epoch).
    ///
    /// ## Example
    /// ```zig
    /// const ts = file.lastModified();  // 1704067200000
    /// ```
    pub fn lastModified(self: *const File) u64 {
        const ptr = getObjectValue(self.id, "lastModified");
        if (ptr <= common.DefaultValueSize) {
            return 0;
        }
        return common.getNum(ptr, u64);
    }

    /// Read the file contents as text.
    ///
    /// Note: This is a synchronous operation in the Workers runtime.
    ///
    /// ## Example
    /// ```zig
    /// const content = file.text();
    /// ```
    pub fn text(self: *const File) []const u8 {
        const func = Function.init(getObjectValue(self.id, "text"));
        defer func.free();

        const result = func.call();
        if (result <= common.DefaultValueSize) {
            return "";
        }
        const str = String.init(result);
        defer str.free();
        return str.value();
    }

    /// Read the file contents as bytes.
    ///
    /// Returns a pointer to the byte array. The caller should copy the data
    /// if it needs to persist beyond the current scope.
    ///
    /// ## Example
    /// ```zig
    /// const data = file.bytes();
    /// ```
    pub fn bytes(self: *const File) []const u8 {
        const func = Function.init(getObjectValue(self.id, "arrayBuffer"));
        defer func.free();

        const result = func.call();
        if (result <= common.DefaultValueSize) {
            return "";
        }
        const len = common.jsSize(result);
        const ptr = common.jsToBytes(result);
        jsFree(result);
        return ptr[0..len];
    }
};

/// Represents a form entry that can be either a string field or a File.
///
/// Used as the return type for `FormData.get()`.
pub const FormEntry = union(enum) {
    /// A text field value.
    field: []const u8,
    /// A file upload.
    file: File,

    /// Check if this entry is a text field.
    pub fn isField(self: *const FormEntry) bool {
        return self.* == .field;
    }

    /// Check if this entry is a file.
    pub fn isFile(self: *const FormEntry) bool {
        return self.* == .file;
    }
};

/// FormData provides a way to construct key/value pairs for form submissions.
///
/// This is a binding to the JavaScript FormData class.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/FormData
///
/// ## Example
///
/// ```zig
/// const form = FormData.new();
/// defer form.free();
///
/// form.append("username", "alice");
/// form.append("tags", "zig");
/// form.append("tags", "wasm");  // multiple values for same key
///
/// if (form.get("username")) |entry| {
///     switch (entry) {
///         .field => |value| {
///             // value == "alice"
///         },
///         .file => |_| {},
///     }
/// }
///
/// if (form.has("email")) {
///     // email field exists
/// }
/// ```
pub const FormData = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) FormData {
        return FormData{ .id = ptr };
    }

    /// Create a new empty FormData instance.
    ///
    /// ## Example
    /// ```zig
    /// const form = FormData.new();
    /// defer form.free();
    /// form.append("key", "value");
    /// ```
    pub fn new() FormData {
        return FormData{ .id = jsCreateClass(Classes.FormData.toInt(), Undefined) };
    }

    /// Free the FormData object from the JavaScript heap.
    pub fn free(self: *const FormData) void {
        jsFree(self.id);
    }

    /// Append a new value onto an existing key, or add the key if it doesn't exist.
    ///
    /// Unlike `set()`, this does not replace existing values with the same name.
    ///
    /// ## Example
    /// ```zig
    /// form.append("tags", "zig");
    /// form.append("tags", "wasm");  // both values are kept
    /// ```
    pub fn append(self: *const FormData, name: []const u8, value: []const u8) void {
        const jsName = String.new(name);
        defer jsName.free();
        const jsValue = String.new(value);
        defer jsValue.free();

        const func = Function.init(getObjectValue(self.id, "append"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&jsName);
        args.push(&jsValue);

        const res = JSValue.init(func.callArgs(&args));
        defer res.free();
    }

    /// Get the first value for a given form field name.
    ///
    /// Returns `null` if the field doesn't exist.
    /// The return value is a `FormEntry` which can be either a string field or a File.
    ///
    /// ## Example
    /// ```zig
    /// if (form.get("username")) |entry| {
    ///     switch (entry) {
    ///         .field => |value| {
    ///             // use the string value
    ///         },
    ///         .file => |file| {
    ///             defer file.free();
    ///             // use the file
    ///         },
    ///     }
    /// }
    /// ```
    pub fn get(self: *const FormData, name: []const u8) ?FormEntry {
        const jsName = String.new(name);
        defer jsName.free();

        const func = Function.init(getObjectValue(self.id, "get"));
        defer func.free();

        const result = func.callArgs(&jsName);
        if (result <= common.DefaultValueSize) {
            return null;
        }

        // Check if the result is a File by looking for the "name" property
        // (Files have a name property, strings don't)
        if (object.hasObject(result, "name") and object.hasObject(result, "size")) {
            return FormEntry{ .file = File.init(result) };
        }

        // It's a string field
        const str = String.init(result);
        defer str.free();
        return FormEntry{ .field = str.value() };
    }

    /// Get all values for a given form field name.
    ///
    /// Returns an Array containing the values. The caller must free the returned Array.
    ///
    /// ## Example
    /// ```zig
    /// const values = form.getAll("tags");
    /// defer values.free();
    /// ```
    pub fn getAll(self: *const FormData, name: []const u8) Array {
        const jsName = String.new(name);
        defer jsName.free();

        const func = Function.init(getObjectValue(self.id, "getAll"));
        defer func.free();

        const result = func.callArgs(&jsName);
        return Array.init(result);
    }

    /// Check if a form field exists.
    ///
    /// ## Example
    /// ```zig
    /// if (form.has("email")) {
    ///     // email field exists
    /// }
    /// ```
    pub fn has(self: *const FormData, name: []const u8) bool {
        const jsName = String.new(name);
        defer jsName.free();

        const func = Function.init(getObjectValue(self.id, "has"));
        defer func.free();

        const result = func.callArgs(&jsName);
        return result == True;
    }

    /// Set a form field to the given value.
    ///
    /// If the field already exists, this replaces all existing values.
    /// If it doesn't exist, it creates a new field.
    ///
    /// ## Example
    /// ```zig
    /// form.set("email", "alice@example.com");
    /// form.set("email", "bob@example.com");  // replaces, not appends
    /// ```
    pub fn set(self: *const FormData, name: []const u8, value: []const u8) void {
        const jsName = String.new(name);
        defer jsName.free();
        const jsValue = String.new(value);
        defer jsValue.free();

        const func = Function.init(getObjectValue(self.id, "set"));
        defer func.free();

        const args = Array.new();
        defer args.free();
        args.push(&jsName);
        args.push(&jsValue);

        const res = JSValue.init(func.callArgs(&args));
        defer res.free();
    }

    /// Delete a form field and all its values.
    ///
    /// ## Example
    /// ```zig
    /// form.delete("obsolete");
    /// ```
    pub fn delete(self: *const FormData, name: []const u8) void {
        const jsName = String.new(name);
        defer jsName.free();

        const func = Function.init(getObjectValue(self.id, "delete"));
        defer func.free();

        const res = JSValue.init(func.callArgs(&jsName));
        defer res.free();
    }

    /// Get all keys in the FormData.
    ///
    /// Returns an iterator-like struct for iterating over field names.
    ///
    /// ## Example
    /// ```zig
    /// var keys = form.keys();
    /// defer keys.free();
    /// while (keys.next()) |key| {
    ///     // use key
    /// }
    /// ```
    pub fn keys(self: *const FormData) FormDataIterator {
        const func = Function.init(getObjectValue(self.id, "keys"));
        defer func.free();

        // Convert iterator to array via Array.from()
        const iterResult = func.call();
        const arrayClass = common.jsGetClass(Classes.Array.toInt());
        defer jsFree(arrayClass);

        const fromFunc = Function.init(getObjectValue(arrayClass, "from"));
        defer fromFunc.free();

        const arr = Array.init(iterResult);
        defer arr.free();

        const arrayResult = fromFunc.callArgs(&arr);
        return FormDataIterator.init(arrayResult);
    }

    /// Get all values in the FormData.
    ///
    /// Returns an iterator-like struct for iterating over values.
    pub fn values(self: *const FormData) FormDataIterator {
        const func = Function.init(getObjectValue(self.id, "values"));
        defer func.free();

        const iterResult = func.call();
        const arrayClass = common.jsGetClass(Classes.Array.toInt());
        defer jsFree(arrayClass);

        const fromFunc = Function.init(getObjectValue(arrayClass, "from"));
        defer fromFunc.free();

        const arr = Array.init(iterResult);
        defer arr.free();

        const arrayResult = fromFunc.callArgs(&arr);
        return FormDataIterator.initWithMode(arrayResult, .values);
    }

    /// Get an iterator over all form entries (name/value pairs).
    ///
    /// Use `nextEntry()` on the returned iterator to get `FormDataEntry` structs.
    /// The caller must free the returned iterator.
    ///
    /// ## Example
    /// ```zig
    /// var entries = form.entries();
    /// defer entries.free();
    /// while (entries.nextEntry()) |entry| {
    ///     // entry.name == "username"
    ///     switch (entry.value) {
    ///         .field => |text| {
    ///             // text value
    ///         },
    ///         .file => |file| {
    ///             defer file.free();
    ///             // file value
    ///         },
    ///     }
    /// }
    /// ```
    pub fn entries(self: *const FormData) FormDataIterator {
        const func = Function.init(getObjectValue(self.id, "entries"));
        defer func.free();

        const iterResult = func.call();
        const arrayClass = common.jsGetClass(Classes.Array.toInt());
        defer jsFree(arrayClass);

        const fromFunc = Function.init(getObjectValue(arrayClass, "from"));
        defer fromFunc.free();

        const iterWrapper = JSValue.init(iterResult);
        const arrayResult = fromFunc.callArgs(&iterWrapper);
        jsFree(iterResult);

        return FormDataIterator.initWithMode(arrayResult, .entries);
    }
};

/// Iterator for FormData keys, values, or entries.
///
/// ## Example
///
/// ```zig
/// // Iterate over field names
/// var keys = form.keys();
/// defer keys.free();
/// while (keys.next()) |key| {
///     // key == "name", "email", etc.
/// }
///
/// // Iterate over entries (name/value pairs)
/// var entries = form.entries();
/// defer entries.free();
/// while (entries.nextEntry()) |entry| {
///     // entry.name == "username"
///     // entry.value is FormEntry (either .field or .file)
/// }
/// ```
pub const FormDataIterator = struct {
    arr: Array,
    pos: u32 = 0,
    len: u32,
    mode: IteratorMode = .keys,

    pub const IteratorMode = enum {
        keys,
        values,
        entries,
    };

    pub fn init(jsPtr: u32) FormDataIterator {
        const arr = Array.init(jsPtr);
        return FormDataIterator{
            .arr = arr,
            .len = arr.length(),
        };
    }

    pub fn initWithMode(jsPtr: u32, mode: IteratorMode) FormDataIterator {
        const arr = Array.init(jsPtr);
        return FormDataIterator{
            .arr = arr,
            .len = arr.length(),
            .mode = mode,
        };
    }

    pub fn free(self: *const FormDataIterator) void {
        self.arr.free();
    }

    /// Get the next string value (for keys mode).
    pub fn next(self: *FormDataIterator) ?[]const u8 {
        if (self.pos >= self.len) return null;
        const itemPtr = self.arr.get(self.pos);
        self.pos += 1;

        if (itemPtr <= common.DefaultValueSize) {
            return null;
        }

        if (self.mode == .entries) {
            // For entries, return the key (first element)
            const entryArr = Array.init(itemPtr);
            defer entryArr.free();
            const keyPtr = entryArr.get(0);
            if (keyPtr <= common.DefaultValueSize) {
                return null;
            }
            const keyStr = String.init(keyPtr);
            defer keyStr.free();
            return keyStr.value();
        }

        const str = String.init(itemPtr);
        defer str.free();
        return str.value();
    }

    /// Get the next entry as a FormDataEntry (for entries mode).
    ///
    /// Note: The FormEntry value should be checked - if it's a File,
    /// the caller is responsible for freeing it.
    pub fn nextEntry(self: *FormDataIterator) ?FormDataEntry {
        if (self.pos >= self.len) return null;
        const itemPtr = self.arr.get(self.pos);
        self.pos += 1;

        if (itemPtr <= common.DefaultValueSize) {
            return null;
        }

        // Each entry is a [key, value] array
        const entryArr = Array.init(itemPtr);
        defer entryArr.free();

        const keyPtr = entryArr.get(0);
        const valuePtr = entryArr.get(1);

        if (keyPtr <= common.DefaultValueSize or valuePtr <= common.DefaultValueSize) {
            return null;
        }

        const keyStr = String.init(keyPtr);
        defer keyStr.free();

        // Check if value is a File
        if (object.hasObject(valuePtr, "name") and object.hasObject(valuePtr, "size")) {
            return FormDataEntry{
                .name = keyStr.value(),
                .value = FormEntry{ .file = File.init(valuePtr) },
            };
        }

        // It's a string
        const valueStr = String.init(valuePtr);
        defer valueStr.free();
        return FormDataEntry{
            .name = keyStr.value(),
            .value = FormEntry{ .field = valueStr.value() },
        };
    }

    /// Reset the iterator to the beginning.
    pub fn reset(self: *FormDataIterator) void {
        self.pos = 0;
    }

    /// Get the total count of items.
    pub fn count(self: *const FormDataIterator) u32 {
        return self.len;
    }
};

/// Represents a FormData entry with name and value.
pub const FormDataEntry = struct {
    name: []const u8,
    value: FormEntry,
};

// Helper functions

fn getStringProperty(objId: u32, property: []const u8) []const u8 {
    const ptr = getObjectValue(objId, property);
    if (ptr <= common.DefaultValueSize) {
        return "";
    }
    const str = String.init(ptr);
    defer str.free();
    return str.value();
}
