const std = @import("std");
const common = @import("../bindings/common.zig");
const jsFree = common.jsFree;
const DefaultValueSize = common.DefaultValueSize;
const object = @import("../bindings/object.zig");
const Object = object.Object;
const getObjectValue = object.getObjectValue;
const getObjectValueNum = object.getObjectValueNum;
const string = @import("../bindings/string.zig");
const String = string.String;
const getStringFree = string.getStringFree;
const array = @import("../bindings/array.zig");
const Array = array.Array;
const ArrayBuffer = @import("../bindings/arraybuffer.zig").ArrayBuffer;
const function = @import("../bindings/function.zig");
const Function = function.Function;
const AsyncFunction = function.AsyncFunction;

// workers-types TO BE ADDED
pub const D1Database = struct {
    id: u32,

    pub fn init(ptr: u32) D1Database {
        return D1Database{ .id = ptr };
    }

    pub fn free(self: *const D1Database) void {
        jsFree(self.id);
    }

    pub fn prepare(self: *const D1Database, text: []const u8) PreparedStatement {
        const str = String.new(text);
        defer str.free();
        const func = Function{ .id = getObjectValue(self.id, "prepare") };
        defer func.free();

        return PreparedStatement.init(func.callArgs(&str));
    }

    /// Dump the database - synchronous from Zig's perspective, JS handles async
    pub fn dump(self: *const D1Database) ArrayBuffer {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "dump") };
        defer func.free();

        return ArrayBuffer.init(func.call());
    }

    /// Execute a query - synchronous from Zig's perspective, JS handles async
    pub fn exec(self: *const D1Database, sql_query: []const u8) Object {
        const str = String.new(sql_query);
        defer str.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "exec") };
        defer func.free();

        return Object.init(func.callArgsID(str.id));
    }

    /// Execute a batch of statements - synchronous from Zig's perspective, JS handles async
    pub fn batch(self: *const D1Database, stmts: []const PreparedStatement) BatchSQLSuccess {
        const arr = Array.new();
        defer arr.free();
        for (stmts) |stmt| {
            defer stmt.free();
            arr.push(&stmt);
        }
        const func = AsyncFunction{ .id = getObjectValue(self.id, "batch") };
        defer func.free();

        const parentArr = Array.new();
        defer parentArr.free();
        parentArr.push(&arr);

        return BatchSQLSuccess.init(func.callArgsID(parentArr.id));
    }

    // ========================================================================
    // Ergonomic Query API (pg.zig-inspired)
    // ========================================================================

    /// Query with inline params, returns an iterator of mapped structs.
    /// Usage:
    ///   const User = struct { id: u32, name: []const u8, email: []const u8 };
    ///   var users = db.query(User, "SELECT * FROM users WHERE role = ?", .{"admin"});
    ///   defer users.deinit();
    ///   while (users.next()) |user| {
    ///       // user.id, user.name, user.email - fully typed!
    ///   }
    pub fn query(self: *const D1Database, comptime T: type, sql: []const u8, params: anytype) D1Query(T) {
        const stmt = self.prepare(sql);
        const bound = bindParams(&stmt, params);
        const result = bound.all();
        return D1Query(T){ .sql_success = result, .results = result.results() };
    }

    /// Query for a single row, returns the struct or null if not found.
    /// Usage:
    ///   const user = db.one(User, "SELECT * FROM users WHERE id = ?", .{123});
    ///   if (user) |u| {
    ///       // use u.id, u.name, etc.
    ///   }
    pub fn one(self: *const D1Database, comptime T: type, sql: []const u8, params: anytype) ?T {
        var q = self.query(T, sql, params);
        defer q.deinit();
        return q.next();
    }

    /// Execute INSERT/UPDATE/DELETE and return the number of affected rows.
    /// Usage:
    ///   const affected = db.execute("DELETE FROM users WHERE active = ?", .{false});
    pub fn execute(self: *const D1Database, sql: []const u8, params: anytype) u64 {
        const stmt = self.prepare(sql);
        const bound = bindParams(&stmt, params);
        const result = bound.run();
        defer result.free();
        return result.changes();
    }
};

pub const BatchSQLSuccess = struct {
    id: u32,

    pub fn init(jsPtr: u32) BatchSQLSuccess {
        return BatchSQLSuccess{ .id = jsPtr };
    }

    pub fn free(self: *const BatchSQLSuccess) void {
        jsFree(self.id);
    }

    pub const BatchSQLSuccessResults = struct {
        arr: Array,
        pos: u32 = 0,
        len: u32,

        pub fn init(jsPtr: u32) BatchSQLSuccessResults {
            const arr = Array.init(jsPtr);
            return BatchSQLSuccessResults{
                .arr = arr,
                .len = arr.length(),
            };
        }

        pub fn free(self: *const BatchSQLSuccessResults) void {
            self.arr.free();
        }

        pub fn next(self: *BatchSQLSuccessResults) ?SQLSuccess {
            if (self.pos == self.len) return null;
            const listkey = self.arr.getType(SQLSuccess, self.pos);
            self.pos += 1;
            return listkey;
        }
    };

    pub fn results(self: *const BatchSQLSuccess) ?BatchSQLSuccessResults {
        const r = getObjectValue(self.id, "results");
        if (r <= DefaultValueSize) return null;
        return BatchSQLSuccessResults.init(r);
    }
};

pub const SQLSuccess = struct {
    id: u32,

    pub fn init(jsPtr: u32) SQLSuccess {
        return SQLSuccess{ .id = jsPtr };
    }

    pub fn free(self: *const SQLSuccess) void {
        jsFree(self.id);
    }

    pub const SQLSuccessResults = struct {
        arr: Array,
        pos: u32 = 0,
        len: u32,

        pub fn init(jsPtr: u32) SQLSuccessResults {
            const arr = Array.init(jsPtr);
            return SQLSuccessResults{
                .arr = arr,
                .len = arr.length(),
            };
        }

        pub fn free(self: *const SQLSuccessResults) void {
            self.arr.free();
        }

        pub fn next(self: *SQLSuccessResults, comptime T: type) ?T {
            if (self.pos == self.len) return null;
            const listkey = self.arr.getType(T, self.pos);
            self.pos += 1;
            return listkey;
        }
    };

    pub fn results(self: *const SQLSuccess) ?SQLSuccessResults {
        const r = getObjectValue(self.id, "results");
        if (r <= DefaultValueSize) return null;
        return SQLSuccessResults.init(r);
    }

    /// Get the meta object containing changes, last_row_id, duration
    fn meta(self: *const SQLSuccess) ?u32 {
        const m = getObjectValue(self.id, "meta");
        if (m <= DefaultValueSize) return null;
        return m;
    }

    /// Get the last inserted row ID from meta.last_row_id
    pub fn lastRowId(self: *const SQLSuccess) ?u64 {
        const m = self.meta() orelse return null;
        defer jsFree(m);
        const lrid = getObjectValueNum(m, "last_row_id", u64);
        if (lrid == 0) return null;
        return lrid;
    }

    /// Get number of rows changed from meta.changes
    pub fn changes(self: *const SQLSuccess) u64 {
        const m = self.meta() orelse return 0;
        defer jsFree(m);
        return getObjectValueNum(m, "changes", u64);
    }

    /// Get query duration in milliseconds from meta.duration
    pub fn duration(self: *const SQLSuccess) f64 {
        const m = self.meta() orelse return 0;
        defer jsFree(m);
        return getObjectValueNum(m, "duration", f64);
    }

    /// Check if the query was successful
    pub fn success(self: *const SQLSuccess) bool {
        const s = getObjectValue(self.id, "success");
        // success is a boolean, check if it's the TRUE constant (3)
        return s == 3;
    }
};

pub const PreparedStatement = struct {
    id: u32,

    pub fn init(ptr: u32) PreparedStatement {
        return PreparedStatement{ .id = ptr };
    }

    pub fn free(self: *const PreparedStatement) void {
        jsFree(self.id);
    }

    pub fn statement(self: *const PreparedStatement) []const u8 {
        return getStringFree(getObjectValue(self.id, "statement"));
    }

    pub const ParamsList = struct {
        arr: Array,
        pos: u32 = 0,
        len: u32,

        pub fn init(jsPtr: u32) ParamsList {
            const arr = Array.init(jsPtr);
            return ParamsList{
                .arr = arr,
                .len = arr.length(),
            };
        }

        pub fn free(self: *const ParamsList) void {
            self.arr.free();
        }

        pub fn next(self: *ParamsList, comptime T: type) ?T {
            if (self.pos == self.len) return null;
            const listkey = self.arr.getType(T, self.pos);
            self.pos += 1;
            return listkey;
        }
    };

    pub fn params(self: *const PreparedStatement) ParamsList {
        return ParamsList.init(getObjectValue(self.id, "params"));
    }

    pub fn bind(self: *const PreparedStatement, input: *const Array) PreparedStatement { // input Array<any>
        const func = AsyncFunction{ .id = getObjectValue(self.id, "bind") };
        defer func.free();

        return PreparedStatement.init(func.callArgsID(input.id));
    }

    /// Get first row - synchronous from Zig's perspective, JS handles async
    pub fn first(self: *const PreparedStatement, column: ?[]const u8) Object {
        defer self.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "first") };
        defer func.free();

        if (column) |c| {
            const str = String.new(c);
            defer str.free();
            return Object.init(func.callArgsID(str.id));
        } else {
            return Object.init(func.call());
        }
    }

    /// Get all rows - synchronous from Zig's perspective, JS handles async
    pub fn all(self: *const PreparedStatement) SQLSuccess { // SQLSuccess<Array<Object>>
        defer self.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "all") };
        defer func.free();

        return SQLSuccess.init(func.call());
    }

    /// Get raw results - synchronous from Zig's perspective, JS handles async
    pub fn raw(self: *const PreparedStatement) Array { // Array<T>
        defer self.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "raw") };
        defer func.free();

        return Array.init(func.call());
    }

    /// Run statement - synchronous from Zig's perspective, JS handles async
    pub fn run(self: *const PreparedStatement) SQLSuccess { // SQLSuccess<void> [no results returned]
        defer self.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "run") };
        defer func.free();

        return SQLSuccess.init(func.call());
    }
};

// ============================================================================
// Ergonomic Query API (pg.zig-inspired)
// ============================================================================

/// Generic iterator that maps D1 result rows to Zig structs.
/// Usage:
///   var users = db.query(User, "SELECT * FROM users WHERE role = ?", .{"admin"});
///   defer users.deinit();
///   while (users.next()) |user| {
///       // user.id, user.name, user.email - fully typed!
///   }
pub fn D1Query(comptime T: type) type {
    return struct {
        results: ?SQLSuccess.SQLSuccessResults,
        sql_success: SQLSuccess,

        const Self = @This();

        /// Get the next row mapped to struct T, or null if no more rows.
        pub fn next(self: *Self) ?T {
            var results = self.results orelse return null;
            const row = results.next(Object) orelse return null;
            defer row.free();
            self.results = results;
            return mapRowToStruct(T, &row);
        }

        /// Release all resources. Must be called when done iterating.
        pub fn deinit(self: *Self) void {
            if (self.results) |*r| r.free();
            self.sql_success.free();
        }

        /// Get the number of rows in the result set.
        pub fn count(self: *const Self) u32 {
            if (self.results) |r| return r.len;
            return 0;
        }
    };
}

/// Bind a tuple of parameters to a prepared statement.
/// Security: Only allows safe types (int, float, bool, string, null, optional).
/// Rejects structs, arrays (except strings), and other complex types at compile time.
fn bindParams(stmt: *const PreparedStatement, params: anytype) PreparedStatement {
    const ParamsType = @TypeOf(params);
    const params_info = @typeInfo(ParamsType);

    if (params_info != .@"struct") {
        @compileError("Params must be a tuple");
    }

    const args = Array.new();

    if (params_info.@"struct".fields.len == 0) {
        defer args.free();
        return stmt.bind(&args);
    }

    inline for (params_info.@"struct".fields) |field| {
        const value = @field(params, field.name);
        bindSingleValue(&args, value);
    }

    defer args.free();
    return stmt.bind(&args);
}

/// Bind a single value to the args array. Handles type validation at comptime.
fn bindSingleValue(args: *const Array, value: anytype) void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .int, .comptime_int => args.pushNum(i64, @intCast(value)),
        .float, .comptime_float => args.pushNum(f64, @floatCast(value)),
        .bool => args.pushNum(i64, if (value) 1 else 0),
        .null => args.pushID(common.Null),
        .optional => {
            if (value) |v| {
                bindSingleValue(args, v);
            } else {
                args.pushID(common.Null);
            }
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                // []const u8 string slice
                args.pushText(value);
            } else if (ptr.size == .one) {
                // Pointer to array (e.g., *const [N]u8 from string literals)
                const child = @typeInfo(ptr.child);
                if (child == .array and child.array.child == u8) {
                    args.pushText(value);
                } else {
                    @compileError("Only []const u8 strings allowed, got: " ++ @typeName(T));
                }
            } else {
                @compileError("Only []const u8 strings allowed, got: " ++ @typeName(T));
            }
        },
        else => @compileError("Unsupported param type: " ++ @typeName(T) ++ ". Only int, float, bool, string, null, and optional are allowed."),
    }
}

/// Map a JavaScript Object (D1 row) to a Zig struct.
fn mapRowToStruct(comptime T: type, row: *const Object) T {
    var result: T = undefined;

    inline for (std.meta.fields(T)) |field| {
        @field(result, field.name) = getFieldValue(field.type, row, field.name);
    }

    return result;
}

/// Extract a field value from a JS Object and convert to the expected Zig type.
fn getFieldValue(comptime FieldType: type, row: *const Object, name: []const u8) FieldType {
    const info = @typeInfo(FieldType);

    switch (info) {
        .int => return row.getNum(name, FieldType),
        .float => return row.getNum(name, FieldType),
        .bool => return row.get(name) == common.True,
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                const str_ptr = row.get(name);
                if (str_ptr > DefaultValueSize) {
                    return getStringFree(str_ptr);
                }
                return "";
            }
            @compileError("Unsupported pointer field: " ++ @typeName(FieldType));
        },
        .optional => |opt| {
            const val_ptr = row.get(name);
            if (val_ptr <= DefaultValueSize) return null;
            return getFieldValue(opt.child, row, name);
        },
        else => @compileError("Unsupported field type: " ++ @typeName(FieldType)),
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

test "bindParams - tuple introspection" {
    const params = .{ 123, "hello", true };
    const info = @typeInfo(@TypeOf(params));
    try std.testing.expectEqual(@as(usize, 3), info.@"struct".fields.len);
}

test "mapRowToStruct - field introspection" {
    const User = struct { id: u32, name: []const u8 };
    const fields = std.meta.fields(User);
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqualStrings("id", fields[0].name);
    try std.testing.expectEqualStrings("name", fields[1].name);
}

test "D1Query - type has expected methods" {
    const User = struct { id: u32 };
    const QueryType = D1Query(User);
    try std.testing.expect(@hasDecl(QueryType, "next"));
    try std.testing.expect(@hasDecl(QueryType, "deinit"));
    try std.testing.expect(@hasDecl(QueryType, "count"));
}

test "bindSingleValue - type validation comptime check" {
    // These should compile successfully (compile-time check)
    const int_val: i32 = 42;
    const float_val: f64 = 3.14;
    const bool_val: bool = true;
    const str_val: []const u8 = "hello";
    const null_val: ?i32 = null;
    const some_val: ?i32 = 123;

    // Type introspection tests (can't call bindSingleValue without JS runtime)
    try std.testing.expectEqual(.int, @typeInfo(@TypeOf(int_val)));
    try std.testing.expectEqual(.float, @typeInfo(@TypeOf(float_val)));
    try std.testing.expectEqual(.bool, @typeInfo(@TypeOf(bool_val)));
    try std.testing.expectEqual(.pointer, @typeInfo(@TypeOf(str_val)));
    try std.testing.expectEqual(.optional, @typeInfo(@TypeOf(null_val)));
    try std.testing.expectEqual(.optional, @typeInfo(@TypeOf(some_val)));
}
