//! Headers bindings for the Web Fetch API.
//!
//! Headers provides methods to work with HTTP request and response headers.
//!
//! ## Example Usage
//!
//! ```zig
//! const headers = Headers.new();
//! defer headers.free();
//!
//! headers.setText("Content-Type", "application/json");
//! headers.setText("X-Custom", "value");
//!
//! // Check if header exists
//! if (headers.has("Content-Type")) {
//!     const ct = headers.getText("Content-Type");
//! }
//!
//! // Iterate over all headers
//! var entries = headers.entries();
//! defer entries.free();
//! while (entries.nextEntry()) |entry| {
//!     // entry.name, entry.value
//! }
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

/// Represents a header name/value pair.
///
/// Used as the return type for `HeadersIterator.nextEntry()`.
pub const HeaderEntry = struct {
    name: []const u8,
    value: []const u8,
};

/// Iterator for Headers keys, values, or entries.
///
/// ## Example
///
/// ```zig
/// // Iterate over header names
/// var keys = headers.keys();
/// defer keys.free();
/// while (keys.next()) |key| {
///     // key == "content-type", "x-custom", etc.
/// }
///
/// // Iterate over header values
/// var values = headers.values();
/// defer values.free();
/// while (values.next()) |value| {
///     // value == "application/json", etc.
/// }
///
/// // Iterate over entries (name/value pairs)
/// var entries = headers.entries();
/// defer entries.free();
/// while (entries.nextEntry()) |entry| {
///     // entry.name == "content-type"
///     // entry.value == "application/json"
/// }
/// ```
pub const HeadersIterator = struct {
    arr: Array,
    pos: u32 = 0,
    len: u32,
    mode: IteratorMode,

    pub const IteratorMode = enum {
        keys,
        values,
        entries,
    };

    pub fn init(jsPtr: u32, mode: IteratorMode) HeadersIterator {
        const arr = Array.init(jsPtr);
        return HeadersIterator{
            .arr = arr,
            .len = arr.length(),
            .mode = mode,
        };
    }

    /// Free the iterator resources.
    pub fn free(self: *const HeadersIterator) void {
        self.arr.free();
    }

    /// Get the next string value (for keys or values mode).
    ///
    /// For entries mode, this returns only the key portion.
    ///
    /// ## Example
    /// ```zig
    /// var keys = headers.keys();
    /// defer keys.free();
    /// while (keys.next()) |key| {
    ///     // key == "content-type"
    /// }
    /// ```
    pub fn next(self: *HeadersIterator) ?[]const u8 {
        if (self.pos >= self.len) return null;
        const itemPtr = self.arr.get(self.pos);
        self.pos += 1;

        if (itemPtr <= common.DefaultValueSize) {
            return null;
        }

        if (self.mode == .entries) {
            // For entries, return the key (first element of the [key, value] array)
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

    /// Get the next entry as a HeaderEntry (for entries mode).
    ///
    /// ## Example
    /// ```zig
    /// var entries = headers.entries();
    /// defer entries.free();
    /// while (entries.nextEntry()) |entry| {
    ///     // entry.name == "content-type"
    ///     // entry.value == "application/json"
    /// }
    /// ```
    pub fn nextEntry(self: *HeadersIterator) ?HeaderEntry {
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
        const valueStr = String.init(valuePtr);
        defer valueStr.free();

        return HeaderEntry{
            .name = keyStr.value(),
            .value = valueStr.value(),
        };
    }

    /// Reset the iterator to the beginning.
    pub fn reset(self: *HeadersIterator) void {
        self.pos = 0;
    }

    /// Get the total count of items.
    pub fn count(self: *const HeadersIterator) u32 {
        return self.len;
    }
};

/// HTTP Headers object for working with request and response headers.
///
/// This is a binding to the JavaScript Headers class.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/Headers
///
/// ## Example
///
/// ```zig
/// const headers = Headers.new();
/// defer headers.free();
///
/// // Set headers
/// headers.setText("Content-Type", "application/json");
/// headers.appendText("Set-Cookie", "session=abc");
/// headers.appendText("Set-Cookie", "user=xyz");
///
/// // Get headers
/// if (headers.getText("Content-Type")) |ct| {
///     // ct == "application/json"
/// }
///
/// // Check existence
/// if (headers.has("Authorization")) {
///     // ...
/// }
///
/// // Iterate over header names
/// var keys = headers.keys();
/// defer keys.free();
/// while (keys.next()) |key| {
///     // key is lowercase header name
/// }
///
/// // Iterate over entries
/// var entries = headers.entries();
/// defer entries.free();
/// while (entries.nextEntry()) |entry| {
///     // entry.name, entry.value
/// }
/// ```
pub const Headers = struct {
    id: u32,

    /// Initialize Headers from an existing JavaScript heap pointer.
    pub fn init(jsPtr: u32) Headers {
        return Headers{ .id = jsPtr };
    }

    /// Create a new empty Headers object.
    ///
    /// ## Example
    /// ```zig
    /// const headers = Headers.new();
    /// defer headers.free();
    /// headers.setText("Content-Type", "application/json");
    /// ```
    pub fn new() Headers {
        return Headers{ .id = jsCreateClass(Classes.Headers.toInt(), Undefined) };
    }

    /// Free the Headers object from the JavaScript heap.
    pub fn free(self: *const Headers) void {
        jsFree(self.id);
    }

    /// Append a value to an existing header, or create a new one.
    ///
    /// Unlike `set()`, this does not replace existing values.
    /// Multiple values for the same header are combined with ", ".
    ///
    /// ## Example
    /// ```zig
    /// headers.appendText("Set-Cookie", "session=abc");
    /// headers.appendText("Set-Cookie", "user=xyz");
    /// // Get returns: "session=abc, user=xyz"
    /// ```
    pub fn append(self: *const Headers, name: []const u8, value: anytype) void {
        const jsName = String.new(name);
        defer jsName.free();
        const func = Function.init(getObjectValue(self.id, "append"));
        defer func.free();
        const jsArray = Array.new();
        defer jsArray.free();
        jsArray.push(&jsName);
        jsArray.push(&value);
        const res = JSValue.init(func.callArgs(&jsArray));
        defer res.free();
    }

    /// Append a text value to a header.
    ///
    /// ## Example
    /// ```zig
    /// headers.appendText("Accept", "text/html");
    /// headers.appendText("Accept", "application/json");
    /// ```
    pub fn appendText(self: *const Headers, name: []const u8, value: []const u8) void {
        const jsName = String.new(name);
        defer jsName.free();
        const jsValue = String.new(value);
        defer jsValue.free();
        const func = Function.init(getObjectValue(self.id, "append"));
        defer func.free();
        const jsArray = Array.new();
        defer jsArray.free();
        jsArray.push(&jsName);
        jsArray.push(&jsValue);
        const res = JSValue.init(func.callArgs(&jsArray));
        defer res.free();
    }

    /// Get the value of a header as a String object.
    ///
    /// Returns null if the header doesn't exist.
    /// The caller must free the returned String.
    ///
    /// ## Example
    /// ```zig
    /// if (headers.get("Content-Type")) |str| {
    ///     defer str.free();
    ///     const value = str.value();
    /// }
    /// ```
    pub fn get(self: *const Headers, name: []const u8) ?String {
        const jsName = String.new(name);
        defer jsName.free();
        const func = Function.init(getObjectValue(self.id, "get"));
        defer func.free();
        const result = func.callArgs(&jsName);
        if (result <= common.DefaultValueSize) {
            return null;
        }
        return String.init(result);
    }

    /// Get the value of a header as a string slice.
    ///
    /// Returns null if the header doesn't exist.
    /// This is a convenience method that handles freeing the String.
    ///
    /// ## Example
    /// ```zig
    /// if (headers.getText("Content-Type")) |ct| {
    ///     // ct == "application/json"
    /// }
    /// ```
    pub fn getText(self: *const Headers, name: []const u8) ?[]const u8 {
        const jsName = String.new(name);
        defer jsName.free();
        const func = Function.init(getObjectValue(self.id, "get"));
        defer func.free();
        const result = func.callArgs(&jsName);
        if (result <= common.DefaultValueSize) {
            return null;
        }
        const str = String.init(result);
        defer str.free();
        return str.value();
    }

    /// Check if a header exists.
    ///
    /// ## Example
    /// ```zig
    /// if (headers.has("Authorization")) {
    ///     // header exists
    /// }
    /// ```
    pub fn has(self: *const Headers, name: []const u8) bool {
        const jsName = String.new(name);
        defer jsName.free();
        const func = Function.init(getObjectValue(self.id, "has"));
        defer func.free();
        const result = func.callArgs(&jsName);
        return result == True;
    }

    /// Set a header to a value, replacing any existing values.
    ///
    /// ## Example
    /// ```zig
    /// headers.set("Content-Type", &contentTypeString);
    /// ```
    pub fn set(self: *const Headers, name: []const u8, value: anytype) void {
        const jsName = String.new(name);
        defer jsName.free();
        const func = Function.init(getObjectValue(self.id, "set"));
        defer func.free();
        const jsArray = Array.new();
        defer jsArray.free();
        jsArray.push(&jsName);
        jsArray.push(&value);
        const res = JSValue.init(func.callArgs(&jsArray));
        defer res.free();
    }

    /// Set a header to a text value, replacing any existing values.
    ///
    /// ## Example
    /// ```zig
    /// headers.setText("Content-Type", "application/json");
    /// headers.setText("X-Custom-Header", "my-value");
    /// ```
    pub fn setText(self: *const Headers, name: []const u8, value: []const u8) void {
        const jsName = String.new(name);
        defer jsName.free();
        const jsValue = String.new(value);
        defer jsValue.free();
        const func = Function.init(getObjectValue(self.id, "set"));
        defer func.free();
        const jsArray = Array.new();
        defer jsArray.free();
        jsArray.push(&jsName);
        jsArray.push(&jsValue);
        const res = JSValue.init(func.callArgs(&jsArray));
        defer res.free();
    }

    /// Delete a header.
    ///
    /// ## Example
    /// ```zig
    /// headers.delete("X-Unwanted-Header");
    /// ```
    pub fn delete(self: *const Headers, name: []const u8) void {
        const jsName = String.new(name);
        defer jsName.free();
        const func = Function.init(getObjectValue(self.id, "delete"));
        defer func.free();
        const res = JSValue.init(func.callArgs(&jsName));
        defer res.free();
    }

    /// Get an iterator over all header names.
    ///
    /// Header names are returned in lowercase.
    /// The caller must free the returned iterator.
    ///
    /// ## Example
    /// ```zig
    /// var keys = headers.keys();
    /// defer keys.free();
    /// while (keys.next()) |key| {
    ///     // key == "content-type", "x-custom", etc.
    /// }
    /// ```
    pub fn keys(self: *const Headers) HeadersIterator {
        const func = Function.init(getObjectValue(self.id, "keys"));
        defer func.free();

        // Convert iterator to array via Array.from()
        const iterResult = func.call();
        const arrayClass = common.jsGetClass(Classes.Array.toInt());
        defer jsFree(arrayClass);

        const fromFunc = Function.init(getObjectValue(arrayClass, "from"));
        defer fromFunc.free();

        const iterWrapper = JSValue.init(iterResult);
        const arrayResult = fromFunc.callArgs(&iterWrapper);
        jsFree(iterResult);

        return HeadersIterator.init(arrayResult, .keys);
    }

    /// Get an iterator over all header values.
    ///
    /// The caller must free the returned iterator.
    ///
    /// ## Example
    /// ```zig
    /// var values = headers.values();
    /// defer values.free();
    /// while (values.next()) |value| {
    ///     // value == "application/json", etc.
    /// }
    /// ```
    pub fn values(self: *const Headers) HeadersIterator {
        const func = Function.init(getObjectValue(self.id, "values"));
        defer func.free();

        const iterResult = func.call();
        const arrayClass = common.jsGetClass(Classes.Array.toInt());
        defer jsFree(arrayClass);

        const fromFunc = Function.init(getObjectValue(arrayClass, "from"));
        defer fromFunc.free();

        const iterWrapper = JSValue.init(iterResult);
        const arrayResult = fromFunc.callArgs(&iterWrapper);
        jsFree(iterResult);

        return HeadersIterator.init(arrayResult, .values);
    }

    /// Get an iterator over all header entries (name/value pairs).
    ///
    /// Use `nextEntry()` on the returned iterator to get `HeaderEntry` structs.
    /// The caller must free the returned iterator.
    ///
    /// ## Example
    /// ```zig
    /// var entries = headers.entries();
    /// defer entries.free();
    /// while (entries.nextEntry()) |entry| {
    ///     // entry.name == "content-type"
    ///     // entry.value == "application/json"
    /// }
    /// ```
    pub fn entries(self: *const Headers) HeadersIterator {
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

        return HeadersIterator.init(arrayResult, .entries);
    }
};
