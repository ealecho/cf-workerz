// Re-export worker types explicitly (Zig 0.11+ removed usingnamespace)
// These modules have been updated to work without Zig's async/await.
// The JS runtime handles async operations via Promises.

// Fetch handler types
const fetch = @import("fetch.zig");
pub const HandlerFn = fetch.HandlerFn;
pub const Route = fetch.Route;
pub const FetchContext = fetch.FetchContext;
pub const createRoute = fetch.createRoute;
pub const all = fetch.all;
pub const get = fetch.get;
pub const head = fetch.head;
pub const post = fetch.post;
pub const put = fetch.put;
pub const delete = fetch.delete;
pub const connect = fetch.connect;
pub const options = fetch.options;
pub const trace = fetch.trace;
pub const patch = fetch.patch;
pub const custom = fetch.custom;

// Response helpers
pub const HttpError = fetch.HttpError;
pub const getErrorStatus = fetch.getErrorStatus;
pub const isStringType = fetch.isStringType;
pub const isComptimeString = fetch.isComptimeString;

// Schedule handler types
const schedule = @import("schedule.zig");
pub const ScheduleFn = schedule.ScheduleFn;
pub const ScheduledEvent = schedule.ScheduledEvent;
pub const ScheduledContext = schedule.ScheduledContext;

// Import tests
test {
    _ = fetch;
}
