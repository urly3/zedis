const std = @import("std");
const Connection = std.net.Server.Connection;
const posix = std.posix;
const pollfd = posix.pollfd;
const Parser = @import("parser.zig").Parser;
const store_mod = @import("store.zig");
const Store = store_mod.Store;
const ZedisObject = store_mod.ZedisObject;
const ZedisValue = store_mod.ZedisValue;
const Command = @import("parser.zig").Command;
const CommandRegistry = @import("./commands/registry.zig").CommandRegistry;
const zedis_types = @import("./zedis_types.zig");
const Server = @import("./server.zig").Server;
const PubSubContext = @import("./pubsub/pubsub.zig").PubSubContext;

var next_client_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

pub const Client = struct {
    client_id: u64,
    allocator: std.mem.Allocator,
    connection: Connection,
    store: *Store,
    command_registry: *CommandRegistry,
    pubsub_context: *PubSubContext,

    pub fn init(
        allocator: std.mem.Allocator,
        connection: Connection,
        store: *Store,
        registry: *CommandRegistry,
        pubsub_context: *PubSubContext,
    ) Client {
        const id = next_client_id.fetchAdd(1, .monotonic);
        return .{
            .client_id = id,
            .allocator = allocator,
            .connection = connection,
            .store = store,
            .command_registry = registry,
            .pubsub_context = pubsub_context,
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
                self.writeError("ERR protocol error") catch {};
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

    pub fn writeArray(self: *Client, values: []const ZedisValue) !void {
        try self.connection.stream.writer().print("*{d}\r\n", .{values.len});

        // 2. Iterate over each element and write it to the stream.
        for (values) |value| {
            switch (value) {
                .string => |s| try self.writeBulkString(s),
                .int => |i| try self.writeInt(i),
            }
        }
    }
    pub fn writeTupleAsArray(self: *Client, items: anytype) !void {
        const T = @TypeOf(items);
        const info = @typeInfo(T);

        // 2. At compile time, verify the input is a tuple.
        //    A tuple in Zig is an anonymous struct.
        comptime {
            switch (info) {
                .@"struct" => |struct_info| {
                    if (!struct_info.is_tuple) {
                        @compileError("This function only accepts a tuple. Received: " ++ @typeName(T));
                    }
                },
                else => @compileError("This function only accepts a tuple. Received: " ++ @typeName(T)),
            }
        }

        const struct_info = info.@"struct";

        const formatted = try std.fmt.allocPrint(self.allocator, "*{d}\r\n", .{struct_info.fields.len});
        _ = try self.connection.stream.write(formatted);

        // 4. Use 'inline for' to iterate over the tuple's elements at compile time.
        //    This loop is "unrolled" by the compiler, generating specific code
        //    for each element's type with no runtime overhead.
        inline for (items) |item| {
            // Check the type of the current item and call the correct serializer.
            const ItemType = @TypeOf(item);
            if (ItemType == []const u8) {
                try self.writeBulkString(item);
            } else if (ItemType == i64) {
                try self.writeInt(item);
            } else {
                // Handle string literals and other pointer-to-array types by checking if they can be coerced to []const u8
                const item_as_slice: []const u8 = item;
                try self.writeBulkString(item_as_slice);
            }
        }
    }

    pub fn writeNull(self: *Client) !void {
        _ = try self.connection.stream.write("$-1\r\n");
    }
};
