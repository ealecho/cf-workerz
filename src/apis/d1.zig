//! Cloudflare D1 - Serverless SQLite database.
//!
//! D1 is Cloudflare's native serverless SQL database built on SQLite.
//! It provides familiar SQL semantics with global distribution and
//! automatic replication.
//!
//! ## Quick Start
//!
//! ```zig
//! fn handleDB(ctx: *FetchContext) void {
//!     const db = ctx.env.d1("MY_DB") orelse {
//!         ctx.throw(500, "D1 not configured");
//!         return;
//!     };
//!     defer db.free();
//!
//!     // Ergonomic API (recommended)
//!     const User = struct { id: u32, name: []const u8, email: []const u8 };
//!
//!     // Query multiple rows
//!     var users = db.query(User, "SELECT * FROM users WHERE active = ?", .{true});
//!     defer users.deinit();
//!     while (users.next()) |user| {
//!         // user.id, user.name, user.email - fully typed!
//!     }
//!
//!     // Query single row
//!     if (db.one(User, "SELECT * FROM users WHERE id = ?", .{123})) |user| {
//!         ctx.json(.{ .id = user.id, .name = user.name }, 200);
//!         return;
//!     }
//!
//!     // Execute INSERT/UPDATE/DELETE
//!     const affected = db.execute("DELETE FROM users WHERE active = ?", .{false});
//!     ctx.json(.{ .deleted = affected }, 200);
//! }
//! ```
//!
//! ## Configuration
//!
//! Add to your `wrangler.toml`:
//!
//! ```toml
//! [[d1_databases]]
//! binding = "MY_DB"
//! database_id = "your-database-id"
//! database_name = "my-database"
//! ```
//!
//! ## Supported Parameter Types
//!
//! | Zig Type | SQL Type |
//! |----------|----------|
//! | `i32`, `u32`, `i64`, `u64` | INTEGER |
//! | `f32`, `f64` | REAL |
//! | `bool` | INTEGER (0/1) |
//! | `[]const u8` | TEXT |
//! | `null` | NULL |
//! | `?T` (optionals) | NULL or T |

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

/// Cloudflare D1 Database handle.
///
/// D1Database provides access to Cloudflare's serverless SQLite database.
/// It supports both an ergonomic high-level API (`query`, `one`, `execute`)
/// and a lower-level prepared statement API.
///
/// ## Ergonomic API (Recommended)
///
/// ```zig
/// const User = struct { id: u32, name: []const u8, email: []const u8 };
///
/// // Query multiple rows -> iterator
/// var users = db.query(User, "SELECT * FROM users WHERE active = ?", .{true});
/// defer users.deinit();
/// while (users.next()) |user| {
///     // user.id, user.name, user.email - fully typed!
/// }
///
/// // Query single row -> ?T
/// if (db.one(User, "SELECT * FROM users WHERE id = ?", .{123})) |user| {
///     ctx.json(.{ .name = user.name }, 200);
/// }
///
/// // Execute INSERT/UPDATE/DELETE -> affected rows count
/// const deleted = db.execute("DELETE FROM users WHERE active = ?", .{false});
/// ```
///
/// ## Prepared Statement API (Lower-level)
///
/// ```zig
/// const stmt = db.prepare("SELECT * FROM users WHERE id = ?");
/// defer stmt.free();
///
/// const args = workers.Array.new();
/// defer args.free();
/// args.pushNum(u32, 123);
///
/// const bound = stmt.bind(&args);
/// const result = bound.all();
/// defer result.free();
/// ```
pub const D1Database = struct {
    id: u32,

    pub fn init(ptr: u32) D1Database {
        return D1Database{ .id = ptr };
    }

    pub fn free(self: *const D1Database) void {
        jsFree(self.id);
    }

    /// Create a prepared statement for the given SQL query.
    ///
    /// Prepared statements allow you to bind parameters and execute
    /// queries safely. For most use cases, prefer the ergonomic API
    /// (`query`, `one`, `execute`) instead.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const stmt = db.prepare("SELECT * FROM users WHERE role = ?");
    /// defer stmt.free();
    ///
    /// const args = workers.Array.new();
    /// defer args.free();
    /// args.pushText("admin");
    ///
    /// const bound = stmt.bind(&args);
    /// const result = bound.all();
    /// defer result.free();
    /// ```
    pub fn prepare(self: *const D1Database, text: []const u8) PreparedStatement {
        const str = String.new(text);
        defer str.free();
        const func = Function{ .id = getObjectValue(self.id, "prepare") };
        defer func.free();

        return PreparedStatement.init(func.callArgs(&str));
    }

    /// Dump the entire database as an ArrayBuffer.
    ///
    /// Returns a raw SQLite database file that can be used for backups
    /// or transferring to another D1 instance.
    ///
    /// Note: This is synchronous from Zig's perspective; the JS runtime
    /// handles the async operation via JSPI.
    pub fn dump(self: *const D1Database) ArrayBuffer {
        const func = AsyncFunction{ .id = getObjectValue(self.id, "dump") };
        defer func.free();

        return ArrayBuffer.init(func.call());
    }

    /// Execute raw SQL directly without parameter binding.
    ///
    /// Use this for running multiple statements or DDL commands.
    /// For parameterized queries, use `prepare()` or the ergonomic API instead.
    ///
    /// Note: This is synchronous from Zig's perspective; the JS runtime
    /// handles the async operation via JSPI.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const result = db.exec("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)");
    /// defer result.free();
    /// ```
    pub fn exec(self: *const D1Database, sql_query: []const u8) Object {
        const str = String.new(sql_query);
        defer str.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "exec") };
        defer func.free();

        return Object.init(func.callArgsID(str.id));
    }

    /// Execute multiple prepared statements in a single batch.
    ///
    /// Batching is more efficient than executing statements individually
    /// as it reduces round-trips to the database.
    ///
    /// Note: This is synchronous from Zig's perspective; the JS runtime
    /// handles the async operation via JSPI.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const stmts = [_]PreparedStatement{
    ///     db.prepare("INSERT INTO users (name) VALUES (?)"),
    ///     db.prepare("INSERT INTO users (name) VALUES (?)"),
    /// };
    /// const results = db.batch(&stmts);
    /// defer results.free();
    /// ```
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

    /// Query multiple rows and return a typed iterator.
    ///
    /// This is the recommended way to query data from D1. The result rows
    /// are automatically mapped to the specified struct type `T`.
    ///
    /// ## Parameters
    ///
    /// - `T`: The struct type to map each row to. Field names must match column names.
    /// - `sql`: The SQL query with `?` placeholders for parameters.
    /// - `params`: A tuple of parameter values to bind (supports int, float, bool, string, null, optional).
    ///
    /// ## Example
    ///
    /// ```zig
    /// const User = struct { id: u32, name: []const u8, email: []const u8, active: bool };
    ///
    /// var users = db.query(User, "SELECT * FROM users WHERE role = ?", .{"admin"});
    /// defer users.deinit();
    ///
    /// while (users.next()) |user| {
    ///     // user.id, user.name, user.email, user.active - all typed!
    /// }
    /// ```
    pub fn query(self: *const D1Database, comptime T: type, sql: []const u8, params: anytype) D1Query(T) {
        const stmt = self.prepare(sql);
        const bound = bindParams(&stmt, params);
        const result = bound.all();
        return D1Query(T){ .sql_success = result, .results = result.results() };
    }

    /// Query for a single row and return the mapped struct or null.
    ///
    /// This is a convenience method for queries that expect exactly one result,
    /// such as lookups by primary key.
    ///
    /// ## Parameters
    ///
    /// - `T`: The struct type to map the row to.
    /// - `sql`: The SQL query with `?` placeholders.
    /// - `params`: A tuple of parameter values to bind.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const User = struct { id: u32, name: []const u8, email: []const u8 };
    ///
    /// if (db.one(User, "SELECT * FROM users WHERE id = ?", .{user_id})) |user| {
    ///     ctx.json(.{ .name = user.name, .email = user.email }, 200);
    /// } else {
    ///     ctx.json(.{ .err = "User not found" }, 404);
    /// }
    /// ```
    pub fn one(self: *const D1Database, comptime T: type, sql: []const u8, params: anytype) ?T {
        var q = self.query(T, sql, params);
        defer q.deinit();
        return q.next();
    }

    /// Execute an INSERT, UPDATE, or DELETE statement and return affected row count.
    ///
    /// Use this for write operations that don't return data.
    ///
    /// ## Parameters
    ///
    /// - `sql`: The SQL statement with `?` placeholders.
    /// - `params`: A tuple of parameter values to bind.
    ///
    /// ## Returns
    ///
    /// The number of rows affected by the operation.
    ///
    /// ## Example
    ///
    /// ```zig
    /// // Insert a new user
    /// _ = db.execute("INSERT INTO users (name, email) VALUES (?, ?)", .{ name, email });
    ///
    /// // Update users
    /// const updated = db.execute("UPDATE users SET active = ? WHERE role = ?", .{ true, "admin" });
    ///
    /// // Delete inactive users
    /// const deleted = db.execute("DELETE FROM users WHERE active = ?", .{false});
    /// ctx.json(.{ .deleted = deleted }, 200);
    /// ```
    pub fn execute(self: *const D1Database, sql: []const u8, params: anytype) u64 {
        const stmt = self.prepare(sql);
        const bound = bindParams(&stmt, params);
        const result = bound.run();
        defer result.free();
        return result.changes();
    }
};

/// Result from a batch of SQL statements.
///
/// Contains an array of `SQLSuccess` results, one for each statement
/// in the batch. Use `results()` to iterate over individual statement results.
///
/// ## Example
///
/// ```zig
/// const batch_result = db.batch(&statements);
/// defer batch_result.free();
///
/// if (batch_result.results()) |results| {
///     defer results.free();
///     while (results.next()) |sql_result| {
///         const changes = sql_result.changes();
///         // process each statement's result
///     }
/// }
/// ```
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

/// Result from a single SQL statement execution.
///
/// Contains the query results (for SELECT), metadata about affected rows,
/// last inserted row ID, and query duration.
///
/// ## Accessing Results
///
/// ```zig
/// const result = stmt.all();
/// defer result.free();
///
/// // Check if query succeeded
/// if (result.success()) {
///     // Get metadata
///     const changes = result.changes();       // rows affected
///     const last_id = result.lastRowId();     // last INSERT rowid
///     const duration = result.duration();     // query time in ms
///
///     // Iterate over result rows
///     if (result.results()) |rows| {
///         defer rows.free();
///         while (rows.next(Object)) |row| {
///             defer row.free();
///             // process row
///         }
///     }
/// }
/// ```
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

/// A prepared SQL statement ready for parameter binding and execution.
///
/// Prepared statements allow you to safely bind parameters and execute
/// queries. They provide protection against SQL injection.
///
/// For most use cases, prefer the ergonomic API on `D1Database`
/// (`query`, `one`, `execute`) which handles binding automatically.
///
/// ## Workflow
///
/// 1. Create with `db.prepare(sql)`
/// 2. Bind parameters with `stmt.bind(&args)`
/// 3. Execute with `first()`, `all()`, `raw()`, or `run()`
/// 4. Process results and free resources
///
/// ## Example
///
/// ```zig
/// const stmt = db.prepare("SELECT * FROM users WHERE role = ? AND active = ?");
/// defer stmt.free();
///
/// const args = workers.Array.new();
/// defer args.free();
/// args.pushText("admin");
/// args.pushNum(i64, 1); // boolean as 0/1
///
/// const bound = stmt.bind(&args);
/// const result = bound.all();
/// defer result.free();
///
/// if (result.results()) |rows| {
///     defer rows.free();
///     while (rows.next(Object)) |row| {
///         defer row.free();
///         // process row
///     }
/// }
/// ```
pub const PreparedStatement = struct {
    id: u32,

    pub fn init(ptr: u32) PreparedStatement {
        return PreparedStatement{ .id = ptr };
    }

    pub fn free(self: *const PreparedStatement) void {
        jsFree(self.id);
    }

    /// Get the SQL statement text.
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

    /// Bind parameters to the prepared statement.
    ///
    /// Returns a new `PreparedStatement` with the bound parameters,
    /// ready for execution.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const args = workers.Array.new();
    /// defer args.free();
    /// args.pushText("admin");
    /// args.pushNum(u32, 123);
    ///
    /// const bound = stmt.bind(&args);
    /// const result = bound.all();
    /// ```
    pub fn bind(self: *const PreparedStatement, input: *const Array) PreparedStatement { // input Array<any>
        const func = AsyncFunction{ .id = getObjectValue(self.id, "bind") };
        defer func.free();

        return PreparedStatement.init(func.callArgsID(input.id));
    }

    /// Execute the query and return only the first row.
    ///
    /// Optionally specify a column name to return just that column's value.
    /// If no rows match, the returned Object will be empty.
    ///
    /// Note: This frees the PreparedStatement after execution.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const row = bound.first(null);
    /// defer row.free();
    /// // Access row fields...
    ///
    /// // Or get a specific column:
    /// const name = bound.first("name");
    /// defer name.free();
    /// ```
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

    /// Execute the query and return all matching rows.
    ///
    /// Returns a `SQLSuccess` containing the result set and metadata.
    /// Use `results()` on the returned value to iterate over rows.
    ///
    /// Note: This frees the PreparedStatement after execution.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const result = bound.all();
    /// defer result.free();
    ///
    /// if (result.results()) |rows| {
    ///     defer rows.free();
    ///     while (rows.next(Object)) |row| {
    ///         defer row.free();
    ///         // process row
    ///     }
    /// }
    /// ```
    pub fn all(self: *const PreparedStatement) SQLSuccess { // SQLSuccess<Array<Object>>
        defer self.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "all") };
        defer func.free();

        return SQLSuccess.init(func.call());
    }

    /// Execute the query and return raw array results.
    ///
    /// Returns results as arrays rather than objects, which can be
    /// more efficient when you know the column order.
    ///
    /// Note: This frees the PreparedStatement after execution.
    pub fn raw(self: *const PreparedStatement) Array { // Array<T>
        defer self.free();
        const func = AsyncFunction{ .id = getObjectValue(self.id, "raw") };
        defer func.free();

        return Array.init(func.call());
    }

    /// Execute an INSERT, UPDATE, or DELETE statement.
    ///
    /// Use this for write operations that don't need to return data rows.
    /// The returned `SQLSuccess` contains metadata like `changes()` and `lastRowId()`.
    ///
    /// Note: This frees the PreparedStatement after execution.
    ///
    /// ## Example
    ///
    /// ```zig
    /// const result = bound.run();
    /// defer result.free();
    ///
    /// const rows_affected = result.changes();
    /// const inserted_id = result.lastRowId();
    /// ```
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

/// Typed iterator for D1 query results.
///
/// Maps D1 result rows to Zig structs automatically. Created by
/// `D1Database.query()`.
///
/// ## Example
///
/// ```zig
/// const User = struct { id: u32, name: []const u8, email: []const u8 };
///
/// var users = db.query(User, "SELECT * FROM users WHERE active = ?", .{true});
/// defer users.deinit();
///
/// // Get total count
/// const total = users.count();
///
/// // Iterate over results
/// while (users.next()) |user| {
///     // user.id, user.name, user.email - fully typed!
/// }
/// ```
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
