//! URL and URLSearchParams bindings for the Web URL API.
//!
//! These provide Zig bindings to the standard JavaScript URL and URLSearchParams
//! classes available in the Cloudflare Workers runtime.
//!
//! ## Example Usage
//!
//! ```zig
//! // Parse a URL
//! const url = URL.new("https://example.com/path?foo=bar");
//! defer url.free();
//!
//! const host = url.hostname();  // "example.com"
//! const path = url.pathname();  // "/path"
//!
//! // Work with query parameters
//! const params = url.searchParams();
//! defer params.free();
//! const foo = params.get("foo"); // "bar"
//!
//! // Or create URLSearchParams directly
//! const params2 = URLSearchParams.new();
//! defer params2.free();
//! params2.append("key", "value");
//! const qs = params2.toString(); // "key=value"
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

/// URLSearchParams provides methods to work with the query string of a URL.
///
/// This is a binding to the JavaScript URLSearchParams class.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams
///
/// ## Example
///
/// ```zig
/// const params = URLSearchParams.new();
/// defer params.free();
///
/// params.append("name", "Alice");
/// params.append("age", "30");
/// params.set("name", "Bob");  // replaces existing
///
/// if (params.get("name")) |name| {
///     // name == "Bob"
/// }
///
/// const qs = params.toString();  // "name=Bob&age=30"
/// ```
pub const URLSearchParams = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) URLSearchParams {
        return URLSearchParams{ .id = ptr };
    }

    /// Create a new empty URLSearchParams instance.
    ///
    /// ## Example
    /// ```zig
    /// const params = URLSearchParams.new();
    /// defer params.free();
    /// params.append("key", "value");
    /// ```
    pub fn new() URLSearchParams {
        return URLSearchParams{ .id = jsCreateClass(Classes.URLSearchParams.toInt(), Undefined) };
    }

    /// Create a new URLSearchParams from a query string.
    ///
    /// The leading `?` is optional - it will be stripped if present.
    ///
    /// ## Example
    /// ```zig
    /// const params = URLSearchParams.fromString("?foo=bar&baz=qux");
    /// defer params.free();
    /// // params.get("foo") -> "bar"
    /// ```
    pub fn fromString(queryString: []const u8) URLSearchParams {
        const jsStr = String.new(queryString);
        defer jsStr.free();
        return URLSearchParams{ .id = jsCreateClass(Classes.URLSearchParams.toInt(), jsStr.id) };
    }

    /// Free the URLSearchParams object from the JavaScript heap.
    /// Always call this when done to prevent memory leaks.
    pub fn free(self: *const URLSearchParams) void {
        jsFree(self.id);
    }

    /// Append a new name/value pair to the query string.
    ///
    /// Unlike `set()`, this does not remove existing values with the same name.
    ///
    /// ## Example
    /// ```zig
    /// params.append("tag", "zig");
    /// params.append("tag", "wasm");  // both values are kept
    /// ```
    pub fn append(self: *const URLSearchParams, name: []const u8, value: []const u8) void {
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

    /// Get the first value for a given search parameter.
    ///
    /// Returns `null` if the parameter doesn't exist.
    ///
    /// ## Example
    /// ```zig
    /// if (params.get("name")) |name| {
    ///     // use name
    /// }
    /// ```
    pub fn get(self: *const URLSearchParams, name: []const u8) ?[]const u8 {
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

    /// Get all values for a given search parameter.
    ///
    /// Returns an Array of strings. The caller must free the returned Array.
    ///
    /// ## Example
    /// ```zig
    /// const values = params.getAll("tag");
    /// defer values.free();
    /// // iterate over values...
    /// ```
    pub fn getAll(self: *const URLSearchParams, name: []const u8) Array {
        const jsName = String.new(name);
        defer jsName.free();

        const func = Function.init(getObjectValue(self.id, "getAll"));
        defer func.free();

        const result = func.callArgs(&jsName);
        return Array.init(result);
    }

    /// Check if a search parameter exists.
    ///
    /// ## Example
    /// ```zig
    /// if (params.has("debug")) {
    ///     // debug mode enabled
    /// }
    /// ```
    pub fn has(self: *const URLSearchParams, name: []const u8) bool {
        const jsName = String.new(name);
        defer jsName.free();

        const func = Function.init(getObjectValue(self.id, "has"));
        defer func.free();

        const result = func.callArgs(&jsName);
        return result == True;
    }

    /// Set a search parameter to the given value.
    ///
    /// If the parameter already exists, this replaces all existing values.
    /// If it doesn't exist, it creates a new parameter.
    ///
    /// ## Example
    /// ```zig
    /// params.set("page", "1");
    /// params.set("page", "2");  // replaces, not appends
    /// ```
    pub fn set(self: *const URLSearchParams, name: []const u8, value: []const u8) void {
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

    /// Delete a search parameter and all its values.
    ///
    /// ## Example
    /// ```zig
    /// params.delete("obsolete");
    /// ```
    pub fn delete(self: *const URLSearchParams, name: []const u8) void {
        const jsName = String.new(name);
        defer jsName.free();

        const func = Function.init(getObjectValue(self.id, "delete"));
        defer func.free();

        const res = JSValue.init(func.callArgs(&jsName));
        defer res.free();
    }

    /// Returns a string containing a query string suitable for use in a URL.
    ///
    /// Does not include the leading `?`.
    ///
    /// ## Example
    /// ```zig
    /// const qs = params.toString();  // "foo=bar&baz=qux"
    /// ```
    pub fn toString(self: *const URLSearchParams) []const u8 {
        const func = Function.init(getObjectValue(self.id, "toString"));
        defer func.free();

        const result = func.call();
        const str = String.init(result);
        defer str.free();
        return str.value();
    }

    /// Returns the number of search parameter entries.
    ///
    /// ## Example
    /// ```zig
    /// const count = params.size();
    /// ```
    pub fn size(self: *const URLSearchParams) u32 {
        const sizePtr = getObjectValue(self.id, "size");
        if (sizePtr <= common.DefaultValueSize) {
            return 0;
        }
        return common.getNum(sizePtr, u32);
    }

    /// Sort all key/value pairs by their keys.
    pub fn sort(self: *const URLSearchParams) void {
        const func = Function.init(getObjectValue(self.id, "sort"));
        defer func.free();

        const res = JSValue.init(func.call());
        defer res.free();
    }
};

/// URL represents a parsed URL with access to its components.
///
/// This is a binding to the JavaScript URL class.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/URL
///
/// ## Example
///
/// ```zig
/// const url = URL.new("https://user:pass@example.com:8080/path?query=1#hash");
/// defer url.free();
///
/// url.protocol();  // "https:"
/// url.hostname();  // "example.com"
/// url.port();      // "8080"
/// url.pathname();  // "/path"
/// url.search();    // "?query=1"
/// url.hash();      // "#hash"
/// url.origin();    // "https://example.com:8080"
/// url.href();      // the full URL
/// ```
pub const URL = struct {
    id: u32,

    /// Initialize from an existing JavaScript heap pointer.
    pub fn init(ptr: u32) URL {
        return URL{ .id = ptr };
    }

    /// Create a new URL by parsing the given URL string.
    ///
    /// ## Example
    /// ```zig
    /// const url = URL.new("https://example.com/path");
    /// defer url.free();
    /// ```
    pub fn new(urlString: []const u8) URL {
        const jsUrl = String.new(urlString);
        defer jsUrl.free();
        return URL{ .id = jsCreateClass(Classes.URL.toInt(), jsUrl.id) };
    }

    /// Create a new URL by resolving a relative URL against a base URL.
    ///
    /// ## Example
    /// ```zig
    /// const url = URL.newWithBase("/path", "https://example.com");
    /// defer url.free();
    /// // url.href() -> "https://example.com/path"
    /// ```
    pub fn newWithBase(urlString: []const u8, baseUrl: []const u8) URL {
        const jsUrl = String.new(urlString);
        defer jsUrl.free();
        const jsBase = String.new(baseUrl);
        defer jsBase.free();

        const args = Array.new();
        defer args.free();
        args.push(&jsUrl);
        args.push(&jsBase);

        return URL{ .id = jsCreateClass(Classes.URL.toInt(), args.id) };
    }

    /// Free the URL object from the JavaScript heap.
    pub fn free(self: *const URL) void {
        jsFree(self.id);
    }

    /// Get the full URL as a string.
    ///
    /// ## Example
    /// ```zig
    /// const full = url.href();  // "https://example.com/path?q=1"
    /// ```
    pub fn href(self: *const URL) []const u8 {
        return getStringProperty(self.id, "href");
    }

    /// Get the protocol scheme (including the trailing colon).
    ///
    /// ## Example
    /// ```zig
    /// const proto = url.protocol();  // "https:"
    /// ```
    pub fn protocol(self: *const URL) []const u8 {
        return getStringProperty(self.id, "protocol");
    }

    /// Get the username specified before the domain name.
    pub fn username(self: *const URL) []const u8 {
        return getStringProperty(self.id, "username");
    }

    /// Get the password specified before the domain name.
    pub fn password(self: *const URL) []const u8 {
        return getStringProperty(self.id, "password");
    }

    /// Get the host (hostname:port).
    ///
    /// ## Example
    /// ```zig
    /// const h = url.host();  // "example.com:8080"
    /// ```
    pub fn host(self: *const URL) []const u8 {
        return getStringProperty(self.id, "host");
    }

    /// Get the domain name (without port).
    ///
    /// ## Example
    /// ```zig
    /// const h = url.hostname();  // "example.com"
    /// ```
    pub fn hostname(self: *const URL) []const u8 {
        return getStringProperty(self.id, "hostname");
    }

    /// Get the port number as a string (empty if default port).
    ///
    /// ## Example
    /// ```zig
    /// const p = url.port();  // "8080" or ""
    /// ```
    pub fn port(self: *const URL) []const u8 {
        return getStringProperty(self.id, "port");
    }

    /// Get the path section of the URL.
    ///
    /// ## Example
    /// ```zig
    /// const p = url.pathname();  // "/path/to/resource"
    /// ```
    pub fn pathname(self: *const URL) []const u8 {
        return getStringProperty(self.id, "pathname");
    }

    /// Get the query string (including the leading `?`).
    ///
    /// ## Example
    /// ```zig
    /// const s = url.search();  // "?foo=bar"
    /// ```
    pub fn search(self: *const URL) []const u8 {
        return getStringProperty(self.id, "search");
    }

    /// Get the fragment identifier (including the leading `#`).
    ///
    /// ## Example
    /// ```zig
    /// const h = url.hash();  // "#section"
    /// ```
    pub fn hash(self: *const URL) []const u8 {
        return getStringProperty(self.id, "hash");
    }

    /// Get the origin of the URL (scheme + host + port).
    ///
    /// ## Example
    /// ```zig
    /// const o = url.origin();  // "https://example.com:8080"
    /// ```
    pub fn origin(self: *const URL) []const u8 {
        return getStringProperty(self.id, "origin");
    }

    /// Get the URLSearchParams object for this URL's query string.
    ///
    /// The returned URLSearchParams is a live view - modifications will
    /// affect the URL's search property.
    ///
    /// ## Example
    /// ```zig
    /// const params = url.searchParams();
    /// defer params.free();
    /// if (params.get("page")) |page| {
    ///     // use page
    /// }
    /// ```
    pub fn searchParams(self: *const URL) URLSearchParams {
        const ptr = getObjectValue(self.id, "searchParams");
        return URLSearchParams.init(ptr);
    }

    /// Returns the URL as a string (same as `href()`).
    pub fn toString(self: *const URL) []const u8 {
        const func = Function.init(getObjectValue(self.id, "toString"));
        defer func.free();

        const result = func.call();
        const str = String.init(result);
        defer str.free();
        return str.value();
    }

    /// Returns the URL as a JSON string (same as `href()`).
    pub fn toJSON(self: *const URL) []const u8 {
        const func = Function.init(getObjectValue(self.id, "toJSON"));
        defer func.free();

        const result = func.call();
        const str = String.init(result);
        defer str.free();
        return str.value();
    }

    // Setters

    /// Set the full URL.
    pub fn setHref(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "href", value);
    }

    /// Set the protocol scheme.
    pub fn setProtocol(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "protocol", value);
    }

    /// Set the username.
    pub fn setUsername(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "username", value);
    }

    /// Set the password.
    pub fn setPassword(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "password", value);
    }

    /// Set the host (hostname:port).
    pub fn setHost(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "host", value);
    }

    /// Set the hostname (without port).
    pub fn setHostname(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "hostname", value);
    }

    /// Set the port.
    pub fn setPort(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "port", value);
    }

    /// Set the pathname.
    pub fn setPathname(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "pathname", value);
    }

    /// Set the search/query string.
    pub fn setSearch(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "search", value);
    }

    /// Set the hash/fragment.
    pub fn setHash(self: *const URL, value: []const u8) void {
        setStringProperty(self.id, "hash", value);
    }
};

/// URLPattern for pattern matching against URLs.
///
/// This is a binding to the JavaScript URLPattern class.
/// See: https://developer.mozilla.org/en-US/docs/Web/API/URLPattern
///
/// Note: This is a stub - full implementation coming soon.
pub const URLPattern = struct {
    id: u32,

    pub fn init(ptr: u32) URLPattern {
        return URLPattern{ .id = ptr };
    }

    pub fn free(self: *const URLPattern) void {
        jsFree(self.id);
    }
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

fn setStringProperty(objId: u32, property: []const u8, value: []const u8) void {
    const jsValue = String.new(value);
    defer jsValue.free();
    object.setObjectValue(objId, property, jsValue.id);
}
