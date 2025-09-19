comptime {
    // String commands tests
    _ = @import("commands/string.zig");

    // Core functionality tests
    _ = @import("store.zig");
    _ = @import("parser.zig");
    _ = @import("client.zig");
    _ = @import("server.zig");

    // Pub/Sub tests
    _ = @import("pubsub/pubsub.zig");

    // RDB tests - checksum utility
    _ = @import("rdb/checksum.zig");
    _ = @import("rdb/zdb.zig");

    // Test utilities
    _ = @import("test_utils.zig");

    // Test runner framework
    _ = @import("test_runner.zig");
}
