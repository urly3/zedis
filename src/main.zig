const std = @import("std");
const server = @import("server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const host = "127.0.0.1";
    const port = 6379;

    // Create and start the server.
    var redis_server = try server.Server.init(allocator, host, port);
    defer redis_server.deinit();

    std.log.info("Zig Redis server listening on {s}:{d}", .{ host, port });

    try redis_server.listen();
}
