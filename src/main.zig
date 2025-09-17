const std = @import("std");
const server = @import("server.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const host = "127.0.0.1";
    const port = 6379;

    // Create and start the server.
    if (server.Server.init(allocator, host, port)) |redis_server_const| {
        var redis_server = @constCast(&redis_server_const);
        defer redis_server.deinit();
        errdefer redis_server.deinit();

        std.log.info("Zig Redis server listening on {s}:{d}", .{ host, port });

        redis_server.listen() catch |err| {
            std.log.err("Error on server {any}", .{@errorName(err)});
        };
    } else |err| {
        std.log.err("Error server init: {any}", .{@errorName(err)});
    }
}
