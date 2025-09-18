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
const PubSubChannelMap = zedis_types.PubSubChannelMap;
var next_client_id: std.atomic.Value(u64) = std.atomic.Value(u64).init(1);

pub const Client = struct {
    client_id: u64,
    allocator: std.mem.Allocator,
    connection: Connection,
    store: *Store,
    command_registry: *CommandRegistry,
    server: *opaque{}, // Use opaque pointer to break circular dependency

    pub fn init(
        allocator: std.mem.Allocator,
        connection: Connection,
        store: *Store,
        registry: *CommandRegistry,
        server: anytype,
    ) Client {
        const id = next_client_id.fetchAdd(1, .monotonic);
        return .{
            .client_id = id,
            .allocator = allocator,
            .connection = connection,
            .store = store,
            .command_registry = registry,
            .server = @ptrCast(server),
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

    // Server method wrappers using function pointers to avoid circular dependency
    // These will be set during client initialization
    pub fn findOrCreateChannel(self: *Client, channel_name: []const u8) ?u32 {
        // TODO: Implement via function pointer to avoid circular dependency
        _ = self;
        _ = channel_name;
        return null;
    }

    pub fn subscribeToChannel(self: *Client, channel_id: u32, client_id: u64) !void {
        // TODO: Implement via function pointer to avoid circular dependency
        _ = self;
        _ = channel_id;
        _ = client_id;
    }

    pub fn unsubscribeFromChannel(self: *Client, channel_id: u32, client_id: u64) void {
        // TODO: Implement via function pointer to avoid circular dependency
        _ = self;
        _ = channel_id;
        _ = client_id;
    }

    pub fn getChannelSubscribers(self: *Client, channel_id: u32) []const u64 {
        // TODO: Implement via function pointer to avoid circular dependency
        _ = self;
        _ = channel_id;
        return &[_]u64{};
    }

    pub fn getChannelCount(self: *Client) u32 {
        // TODO: Implement via function pointer to avoid circular dependency
        _ = self;
        return 0;
    }

    pub fn getChannelNames(self: *Client) []const ?[]const u8 {
        // TODO: Implement via function pointer to avoid circular dependency
        _ = self;
        return &[_]?[]const u8{};
    }
};
