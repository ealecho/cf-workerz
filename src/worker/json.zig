const std = @import("std");

/// Buffer size for JSON parsing (4KB should handle most request bodies)
pub const JSON_BUFFER_SIZE = 4096;

/// A wrapper around std.json.Value that provides ergonomic field extraction.
/// Inspired by Hono's `c.req.json()` API.
///
/// Example usage:
/// ```
/// var json = ctx.bodyJson() orelse return ctx.json(.{ .@"error" = "Invalid JSON" }, 400);
/// defer json.deinit();
///
/// const title = json.getString("title") orelse return ctx.json(.{ .@"error" = "Title required" }, 400);
/// const count = json.getInt("count", u32) orelse 0;
/// const price = json.getFloat("price", f64) orelse 0.0;
/// const enabled = json.getBool("enabled") orelse false;
/// ```
pub const JsonBody = struct {
    /// The parsed JSON value (must be an object for field access)
    parsed: std.json.Parsed(std.json.Value),

    /// Parse a JSON string into a JsonBody.
    /// Returns null if parsing fails or the result is not an object.
    pub fn parse(allocator: std.mem.Allocator, body: []const u8) ?JsonBody {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            body,
            .{},
        ) catch return null;

        // Ensure it's an object
        if (parsed.value != .object) {
            parsed.deinit();
            return null;
        }

        return JsonBody{
            .parsed = parsed,
        };
    }

    /// Free the parsed JSON.
    pub fn deinit(self: *const JsonBody) void {
        self.parsed.deinit();
    }

    /// Get the underlying object map for advanced access.
    pub fn object(self: *const JsonBody) std.json.ObjectMap {
        return self.parsed.value.object;
    }

    /// Check if a field exists.
    pub fn has(self: *const JsonBody, key: []const u8) bool {
        return self.parsed.value.object.get(key) != null;
    }

    /// Get a string field. Returns null if missing or not a string.
    pub fn getString(self: *const JsonBody, key: []const u8) ?[]const u8 {
        const value = self.parsed.value.object.get(key) orelse return null;
        return switch (value) {
            .string => |s| s,
            else => null,
        };
    }

    /// Get a string field with a default value.
    pub fn getStringOr(self: *const JsonBody, key: []const u8, default: []const u8) []const u8 {
        return self.getString(key) orelse default;
    }

    /// Get an integer field. Returns null if missing or not a number.
    pub fn getInt(self: *const JsonBody, key: []const u8, comptime T: type) ?T {
        const value = self.parsed.value.object.get(key) orelse return null;
        return switch (value) {
            .integer => |i| @intCast(i),
            .float => |f| @intFromFloat(f),
            else => null,
        };
    }

    /// Get an integer field with a default value.
    pub fn getIntOr(self: *const JsonBody, key: []const u8, comptime T: type, default: T) T {
        return self.getInt(key, T) orelse default;
    }

    /// Get a float field. Returns null if missing or not a number.
    pub fn getFloat(self: *const JsonBody, key: []const u8, comptime T: type) ?T {
        const value = self.parsed.value.object.get(key) orelse return null;
        return switch (value) {
            .float => |f| @floatCast(f),
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }

    /// Get a float field with a default value.
    pub fn getFloatOr(self: *const JsonBody, key: []const u8, comptime T: type, default: T) T {
        return self.getFloat(key, T) orelse default;
    }

    /// Get a boolean field. Returns null if missing or not a boolean.
    pub fn getBool(self: *const JsonBody, key: []const u8) ?bool {
        const value = self.parsed.value.object.get(key) orelse return null;
        return switch (value) {
            .bool => |b| b,
            else => null,
        };
    }

    /// Get a boolean field with a default value.
    pub fn getBoolOr(self: *const JsonBody, key: []const u8, default: bool) bool {
        return self.getBool(key) orelse default;
    }

    /// Get a nested object. Returns null if missing or not an object.
    pub fn getObject(self: *const JsonBody, key: []const u8) ?std.json.ObjectMap {
        const value = self.parsed.value.object.get(key) orelse return null;
        return switch (value) {
            .object => |o| o,
            else => null,
        };
    }

    /// Get an array field. Returns null if missing or not an array.
    pub fn getArray(self: *const JsonBody, key: []const u8) ?std.json.Array {
        const value = self.parsed.value.object.get(key) orelse return null;
        return switch (value) {
            .array => |a| a,
            else => null,
        };
    }

    /// Get the raw JSON value for a field (for advanced usage).
    pub fn get(self: *const JsonBody, key: []const u8) ?std.json.Value {
        return self.parsed.value.object.get(key);
    }
};

// ============================================================================
// Unit Tests
// ============================================================================

test "JsonBody.parse valid object" {
    const allocator = std.testing.allocator;
    const body = JsonBody.parse(allocator, "{\"name\":\"Alice\",\"age\":30}");
    try std.testing.expect(body != null);
    const json = body.?;
    defer json.deinit();

    try std.testing.expectEqualStrings("Alice", json.getString("name").?);
    try std.testing.expectEqual(@as(u32, 30), json.getInt("age", u32).?);
}

test "JsonBody.parse invalid JSON returns null" {
    const allocator = std.testing.allocator;
    const body = JsonBody.parse(allocator, "not valid json");
    try std.testing.expect(body == null);
}

test "JsonBody.parse array returns null (must be object)" {
    const allocator = std.testing.allocator;
    const body = JsonBody.parse(allocator, "[1, 2, 3]");
    try std.testing.expect(body == null);
}

test "JsonBody.parse empty object" {
    const allocator = std.testing.allocator;
    const body = JsonBody.parse(allocator, "{}");
    try std.testing.expect(body != null);
    const json = body.?;
    defer json.deinit();

    try std.testing.expect(json.getString("missing") == null);
}

test "JsonBody.getString" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"title\":\"Hello\",\"count\":42}").?;
    defer json.deinit();

    // Existing string field
    try std.testing.expectEqualStrings("Hello", json.getString("title").?);

    // Missing field
    try std.testing.expect(json.getString("missing") == null);

    // Wrong type (number, not string)
    try std.testing.expect(json.getString("count") == null);
}

test "JsonBody.getStringOr" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"title\":\"Hello\"}").?;
    defer json.deinit();

    try std.testing.expectEqualStrings("Hello", json.getStringOr("title", "default"));
    try std.testing.expectEqualStrings("default", json.getStringOr("missing", "default"));
}

test "JsonBody.getInt" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"count\":42,\"price\":3.14,\"name\":\"test\"}").?;
    defer json.deinit();

    // Integer field
    try std.testing.expectEqual(@as(u32, 42), json.getInt("count", u32).?);
    try std.testing.expectEqual(@as(i64, 42), json.getInt("count", i64).?);

    // Float field (truncated to int)
    try std.testing.expectEqual(@as(u32, 3), json.getInt("price", u32).?);

    // Missing field
    try std.testing.expect(json.getInt("missing", u32) == null);

    // Wrong type (string)
    try std.testing.expect(json.getInt("name", u32) == null);
}

test "JsonBody.getIntOr" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"count\":42}").?;
    defer json.deinit();

    try std.testing.expectEqual(@as(u32, 42), json.getIntOr("count", u32, 0));
    try std.testing.expectEqual(@as(u32, 100), json.getIntOr("missing", u32, 100));
}

test "JsonBody.getFloat" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"price\":3.14,\"count\":42,\"name\":\"test\"}").?;
    defer json.deinit();

    // Float field
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), json.getFloat("price", f64).?, 0.001);

    // Integer field (converted to float)
    try std.testing.expectEqual(@as(f64, 42.0), json.getFloat("count", f64).?);

    // Missing field
    try std.testing.expect(json.getFloat("missing", f64) == null);

    // Wrong type (string)
    try std.testing.expect(json.getFloat("name", f64) == null);
}

test "JsonBody.getBool" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"enabled\":true,\"disabled\":false,\"count\":1}").?;
    defer json.deinit();

    try std.testing.expectEqual(true, json.getBool("enabled").?);
    try std.testing.expectEqual(false, json.getBool("disabled").?);

    // Missing field
    try std.testing.expect(json.getBool("missing") == null);

    // Wrong type (number)
    try std.testing.expect(json.getBool("count") == null);
}

test "JsonBody.getBoolOr" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"enabled\":true}").?;
    defer json.deinit();

    try std.testing.expectEqual(true, json.getBoolOr("enabled", false));
    try std.testing.expectEqual(false, json.getBoolOr("missing", false));
}

test "JsonBody.has" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"title\":\"Hello\",\"count\":null}").?;
    defer json.deinit();

    try std.testing.expect(json.has("title"));
    try std.testing.expect(json.has("count")); // null is still "has"
    try std.testing.expect(!json.has("missing"));
}

test "JsonBody.getObject nested" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"user\":{\"name\":\"Alice\",\"age\":30}}").?;
    defer json.deinit();

    const user = json.getObject("user");
    try std.testing.expect(user != null);

    // Access nested field via raw object map
    const name = user.?.get("name");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("Alice", name.?.string);
}

test "JsonBody.getArray" {
    const allocator = std.testing.allocator;
    const json = JsonBody.parse(allocator, "{\"tags\":[\"a\",\"b\",\"c\"]}").?;
    defer json.deinit();

    const tags = json.getArray("tags");
    try std.testing.expect(tags != null);
    try std.testing.expectEqual(@as(usize, 3), tags.?.items.len);
}

test "JsonBody complex example" {
    const allocator = std.testing.allocator;
    const input =
        \\{"title":"Buy groceries","description":"Milk, eggs, bread","priority":"high","completed":false,"count":5}
    ;
    const json = JsonBody.parse(allocator, input).?;
    defer json.deinit();

    const title = json.getString("title") orelse "untitled";
    const description = json.getStringOr("description", "");
    const priority = json.getStringOr("priority", "medium");
    const completed = json.getBoolOr("completed", false);
    const count = json.getIntOr("count", u32, 1);

    try std.testing.expectEqualStrings("Buy groceries", title);
    try std.testing.expectEqualStrings("Milk, eggs, bread", description);
    try std.testing.expectEqualStrings("high", priority);
    try std.testing.expectEqual(false, completed);
    try std.testing.expectEqual(@as(u32, 5), count);
}
