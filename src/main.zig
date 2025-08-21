const std = @import("std");
const server = @import("server.zig");

// The main function is the starting point of execution.
// It initializes an allocator and starts the server.
pub fn main() !void {
    // We use a GeneralPurposeAllocator to manage memory.
    // It's important to handle potential memory leaks by checking at the end.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define the host and port for the server to listen on.
    const host = "127.0.0.1";
    const port = 6379;

    // Create and start the server.
    var redis_server = try server.Server.init(allocator, host, port);
    defer redis_server.deinit();

    std.log.info("Zig Redis server listening on {s}:{d}", .{ host, port });

    // This will start the server's event loop and begin accepting connections.
    try redis_server.listen();
}
