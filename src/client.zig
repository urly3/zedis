const std = @import("std");
const Parser = @import("parser.zig").Parser;
const store_mod = @import("store.zig");
const Store = store_mod.Store;
const ZedisObject = store_mod.ZedisObject;
const Command = @import("parser.zig").Command;
const Value = @import("parser.zig").Value;
const t_string = @import("./commands/t_string.zig");
const rdb = @import("./commands//rdb.zig");
const connection_commands = @import("./commands/connection.zig");
const CommandRegistry = @import("./commands/registry.zig").CommandRegistry;
const CommandInfo = @import("./commands/registry.zig").CommandInfo;

pub const Client = struct {
    allocator: std.mem.Allocator,
    connection: std.net.Server.Connection,
    store: *Store,
    command_registry: CommandRegistry,

    // Initializes a new client handler.
    pub fn init(allocator: std.mem.Allocator, connection: std.net.Server.Connection, store: *Store) !Client {
        var registry = CommandRegistry.init(allocator);

        // Register all commands
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
            .name = "SAVE",
            .handler = rdb.save,
            .min_args = 1,
            .max_args = 1,
            .description = "The SAVE commands performs a synchronous save of the dataset producing a point in time snapshot of all the data inside the Redis instance, in the form of an RDB file.",
        });

        return .{
            .allocator = allocator,
            .connection = connection,
            .store = store,
            .command_registry = registry,
        };
    }

    // Cleans up client resources.
    pub fn deinit(self: *Client) void {
        self.command_registry.deinit();
        self.connection.stream.close();
    }

    // Main loop for a client. It continuously reads and processes commands.
    pub fn handle(self: *Client) !void {
        while (true) {
            // Parse the incoming command from the client's stream.
            var parser = Parser.init(self.allocator, self.connection.stream);
            var command = parser.parse() catch |err| {
                // If there's an error (like a closed connection), we stop handling this client.
                if (err == error.EndOfStream) return;
                std.log.err("Parse error: {s}", .{@errorName(err)});
                try self.writeError("ERR protocol error");
                continue;
            };
            defer command.deinit();

            // Execute the parsed command.
            try self.executeCommand(command);
        }
    }

    // Dispatches the parsed command to the appropriate handler function.
    fn executeCommand(self: *Client, command: Command) !void {
        try self.command_registry.executeCommand(self, command.args.items);
    }

    // --- RESP Writing Helpers ---

    pub fn writeError(self: *Client, msg: []const u8) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, "-{s}\r\n", .{msg});
        defer self.allocator.free(formatted);
        _ = try self.connection.stream.write(formatted);
    }

    pub fn writeBulkString(self: *Client, str: []const u8) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, "${d}\r\n{s}\r\n", .{ str.len, str });
        defer self.allocator.free(formatted);
        _ = try self.connection.stream.write(formatted);
    }

    pub fn writeInt(self: *Client, value: i64) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, ":{d}\r\n", .{value});
        defer self.allocator.free(formatted);
        _ = try self.connection.stream.write(formatted);
    }

    pub fn writeNull(self: *Client) !void {
        _ = try self.connection.stream.write("$-1\r\n");
    }
};
