const std = @import("std");
const Client = @import("client.zig").Client;
const Store = @import("store.zig").Store;

pub const Server = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,
    listener: std.net.Server,
    store: Store,

    // Initializes the server, binding it to a specific host and port.
    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !Server {
        const address = try std.net.Address.parseIp(host, port);
        const listener = try address.listen(.{ .reuse_address = true });

        return Server{
            .allocator = allocator,
            .address = address,
            .listener = listener,
            .store = Store.init(allocator),
        };
    }

    // Cleans up resources when the server is shut down.
    pub fn deinit(self: *Server) void {
        self.listener.deinit();
        self.store.deinit();
    }

    // The main server loop. It waits for incoming connections and
    // spawns a new async task (frame) to handle each client.
    pub fn listen(self: *Server) !void {
        while (true) {
            const conn = try self.listener.accept();
            std.log.info("Accepted connection from: {}", .{conn.address});

            // async call to handle the client connection concurrently
            self.handleConnection(conn) catch |err| {
                std.log.err("Error handling connection: {s}", .{@errorName(err)});
                conn.stream.close();
            };
        }
    }

    // This function is executed for each connected client.
    // It creates a new Client instance and lets it handle the request/response cycle.
    fn handleConnection(self: *Server, conn: std.net.Server.Connection) !void {
        var client = Client.init(self.allocator, conn, &self.store) catch |err| {
            std.log.err("Failed to initialize client: {s}", .{@errorName(err)});
            conn.stream.close();
            return;
        };
        defer client.deinit();
        // log how long it took to handle the client
        const start_time = std.time.nanoTimestamp();
        try client.handle();
        const end_time = std.time.nanoTimestamp();
        const runtime = std.math.divCeil(i128, (end_time - start_time), 1_000_000);
        std.log.info("Handled client in {any} ms", .{runtime});
    }
};
