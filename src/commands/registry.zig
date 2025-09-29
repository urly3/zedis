const std = @import("std");
const Client = @import("../client.zig").Client;
const Store = @import("../store.zig").Store;
const Server = @import("../server.zig").Server;
const Value = @import("../parser.zig").Value;
const resp = @import("resp.zig");

pub const CommandError = error{
    WrongNumberOfArguments,
    InvalidArgument,
    UnknownCommand,
};

pub const Handler = union(enum) {
    default: DefaultHandler,
    client_handler: ClientHander,
    store_handler: StoreHandler,
};

// No side-effects
pub const DefaultHandler = *const fn (writer: *std.Io.Writer, args: []const Value) anyerror!void;
// Requires client
pub const ClientHander = *const fn (client: *Client, args: []const Value) anyerror!void;
// Requires store
pub const StoreHandler = *const fn (writer: *std.Io.Writer, store: *Store, args: []const Value) anyerror!void;

pub const CommandInfo = struct {
    name: []const u8,
    handler: Handler,
    min_args: usize,
    max_args: ?usize, // null means unlimited
    description: []const u8,
};

// Command registry that maps command names to their handlers
pub const CommandRegistry = struct {
    commands: std.StringHashMap(CommandInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandRegistry {
        return .{
            .commands = std.StringHashMap(CommandInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CommandRegistry) void {
        self.commands.deinit();
    }

    pub fn register(self: *CommandRegistry, info: CommandInfo) !void {
        try self.commands.put(info.name, info);
    }

    pub fn get(self: *CommandRegistry, name: []const u8) ?CommandInfo {
        return self.commands.get(name);
    }

    pub fn executeCommand(
        self: *CommandRegistry,
        writer: *std.Io.Writer,
        client: ?*Client,
        store: ?*Store,
        args: []const Value,
    ) !void {
        if (args.len == 0) {
            return resp.writeError(writer, "ERR empty command");
        }

        const command_name = args[0].asSlice();

        // Convert to uppercase for case-insensitive lookup
        var upper_name = try self.allocator.alloc(u8, command_name.len);
        defer self.allocator.free(upper_name);

        for (command_name, 0..) |c, i| {
            upper_name[i] = std.ascii.toUpper(c);
        }

        if (self.get(upper_name)) |cmd_info| {
            // Validate argument count
            if (args.len < cmd_info.min_args) {
                return resp.writeError(writer, "ERR wrong number of arguments");
            }
            if (cmd_info.max_args) |max_args| {
                if (args.len > max_args) {
                    return resp.writeError(writer, "ERR wrong number of arguments");
                }
            }

            switch (cmd_info.handler) {
                .client_handler => |handler| {
                    // If we haven't provided a client, this is an invariant failure
                    handler(client.?, args) catch |err| {
                        std.log.err("Handler for command '{s}' failed with error: {s}", .{
                            cmd_info.name,
                            @errorName(err),
                        });
                    };
                },
                .store_handler => |handler| {
                    // If we haven't provided a store, this is an invariant failure
                    handler(writer, store.?, args) catch |err| {
                        std.log.err("Handler for command '{s}' failed with error: {s}", .{
                            cmd_info.name,
                            @errorName(err),
                        });
                    };

                    // TODO: expire/expireat
                    if (store.?.aof_writer.enabled and !std.mem.eql(u8, cmd_info.name, "GET")) {
                        try resp.writeArrayString(store.?.aof_writer.writer(), args);
                    }
                },
                .default => |handler| {
                    handler(writer, args) catch |err| {
                        std.log.err("Handler for command '{s}' failed with error: {s}", .{
                            cmd_info.name,
                            @errorName(err),
                        });
                    };
                },
            }
        } else {
            return resp.writeError(writer, "ERR unknown command");
        }
    }
};
