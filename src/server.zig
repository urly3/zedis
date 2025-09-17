const std = @import("std");
const Allocator = std.mem.Allocator;
const Client = @import("client.zig").Client;
const CommandRegistry = @import("./commands/registry.zig").CommandRegistry;
const connection_commands = @import("./commands/connection.zig");
const Reader = @import("./rdb/zdb.zig").Reader;
const Store = @import("store.zig").Store;
const time = std.time;
const t_string = @import("./commands/t_string.zig");
const rdb = @import("./commands//rdb.zig");

pub const Server = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,
    listener: std.net.Server,
    store: Store,
    registry: CommandRegistry,

    // Metadata
    redisVersion: ?[]u8 = undefined,
    createdTime: i64,

    // Initializes the server, binding it to a specific host and port.
    pub fn init(allocator: Allocator, host: []const u8, port: u16) !Server {
        const address = try std.net.Address.parseIp(host, port);
        const listener = try address.listen(.{ .reuse_address = true });

        const store = Store.init(allocator);

        const registry = try Server.initRegistry(allocator);

        var server: Server = .{
            .allocator = allocator,
            .address = address,
            .listener = listener,
            .store = store,
            .createdTime = time.timestamp(),
            .registry = registry,
        };

        const file_exists = Reader.rdbFileExists();
        if (file_exists) {
            const reader = try Reader.init(allocator, @constCast(&store));
            errdefer reader.deinit();
            defer reader.deinit();

            if (reader.readFile()) |data| {
                std.log.debug("output rdb {any}", .{data});
                server.createdTime = data.ctime;
            } else |err| {
                std.log.err("Failed to load rdb: {s}", .{@errorName(err)});
            }
        }

        return server;
    }

    pub fn deinit(self: *Server) void {
        self.listener.deinit();
        self.store.deinit();
    }

    pub fn initRegistry(allocator: Allocator) !CommandRegistry {
        var registry = CommandRegistry.init(allocator);

        try registry.register(.{
            .name = "PING",
            .handler = connection_commands.ping,
            .min_args = 1,
            .max_args = 2,
            .description = "Ping the server",
        });

        try registry.register(.{
            .name = "ECHO",
            .handler = connection_commands.echo,
            .min_args = 2,
            .max_args = 2,
            .description = "Echo the given string",
        });

        try registry.register(.{
            .name = "QUIT",
            .handler = connection_commands.quit,
            .min_args = 1,
            .max_args = 1,
            .description = "Close the connection",
        });

        try registry.register(.{
            .name = "SET",
            .handler = t_string.set,
            .min_args = 3,
            .max_args = 3,
            .description = "Set string value of a key",
        });

        try registry.register(.{
            .name = "GET",
            .handler = t_string.get,
            .min_args = 2,
            .max_args = 2,
            .description = "Get string value of a key",
        });

        try registry.register(.{
            .name = "INCR",
            .handler = t_string.incr,
            .min_args = 2,
            .max_args = 2,
            .description = "Increment the value of a key",
        });

        try registry.register(.{
            .name = "DECR",
            .handler = t_string.decr,
            .min_args = 2,
            .max_args = 2,
            .description = "Decrement the value of a key",
        });

        try registry.register(.{
            .name = "HELP",
            .handler = connection_commands.help,
            .min_args = 1,
            .max_args = 1,
            .description = "Show help message",
        });

        try registry.register(.{
            .name = "DEL",
            .handler = t_string.del,
            .min_args = 2,
            .max_args = null,
            .description = "Delete key",
        });

        try registry.register(.{
            .name = "SAVE",
            .handler = rdb.save,
            .min_args = 1,
            .max_args = 1,
            .description = "The SAVE commands performs a synchronous save of the dataset producing a point in time snapshot of all the data inside the Redis instance, in the form of an RDB file.",
        });

        return registry;
    }

    // The main server loop. It waits for incoming connections and
    // spawns a new async task (frame) to handle each client.
    pub fn listen(self: *Server) !void {
        while (true) {
            const conn = try self.listener.accept();

            // async call to handle the client connection concurrently
            self.handleConnection(conn) catch |err| {
                std.log.err("Error handling connection: {s}", .{@errorName(err)});
                conn.stream.close();
            };
        }
    }

    fn handleConnection(self: *Server, conn: std.net.Server.Connection) !void {
        var client = Client.init(self.allocator, conn, &self.store, &self.registry) catch |err| {
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
