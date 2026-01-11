// Re-export HTTP common types explicitly (Zig 0.11+ removed usingnamespace)

const common = @import("common.zig");
pub const StatusCode = common.StatusCode;
pub const Method = common.Method;
pub const Version = common.Version;
