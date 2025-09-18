const std = @import("std");
const Parser = @import("parser.zig").Parser;
const store_mod = @import("store.zig");
const Store = store_mod.Store;
const ZedisObject = store_mod.ZedisObject;
const Command = @import("parser.zig").Command;
const CommandRegistry = @import("./commands/registry.zig").CommandRegistry;
const Connection = std.net.Server.Connection;
const zedis_types = @import("./zedis_types.zig");
const PubSubChannelMap = zedis_types.PubSubChannelMap;

pub const Client = struct {
    allocator: std.mem.Allocator,
    connection: Connection,
    store: *Store,
    command_registry: *CommandRegistry,
    pub_sub_channels: *PubSubChannelMap,

    pub fn init(
        allocator: std.mem.Allocator,
        connection: Connection,
        store: *Store,
        registry: *CommandRegistry,
        pub_sub_channels: *PubSubChannelMap,
    ) !Client {
        return .{
            .allocator = allocator,
            .connection = connection,
            .store = store,
            .command_registry = registry,
            .pub_sub_channels = pub_sub_channels,
        };
    }

    pub fn deinit(self: *Client) void {
        self.connection.stream.close();
    }

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
