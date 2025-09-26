const std = @import("std");
const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;

pub const CommandError = error{
    WrongNumberOfArguments,
    InvalidArgument,
    UnknownCommand,
};

pub const CommandHandler = *const fn (client: *Client, args: []const Value) anyerror!void;

pub const CommandInfo = struct {
    name: []const u8,
    handler: CommandHandler,
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

    pub fn executeCommand(self: *CommandRegistry, client: *Client, args: []const Value) !void {
        if (args.len == 0) {
            return client.writeError("ERR empty command");
        }

        const command_name = args[0].asSlice();

        // Convert to uppercase for case-insensitive lookup
        var upper_name = try self.allocator.alloc(u8, command_name.len);
        defer self.allocator.free(upper_name);

        for (command_name, 0..) |c, i| {
            upper_name[i] = std.ascii.toUpper(c);
        }

        // Skip auth check for commands that don't need it
        if (!std.mem.eql(u8, upper_name, "AUTH") and
            !std.mem.eql(u8, upper_name, "PING") and
            !client.isAuthenticated()) {
            return client.writeError("NOAUTH Authentication required");
        }

        if (self.get(upper_name)) |cmd_info| {
            // Validate argument count
            if (args.len < cmd_info.min_args) {
                return client.writeError("ERR wrong number of arguments");
            }
            if (cmd_info.max_args) |max_args| {
                if (args.len > max_args) {
                    return client.writeError("ERR wrong number of arguments");
                }
            }

            cmd_info.handler(client, args) catch |err| {
                std.log.err("Handler for command '{s}' failed with error: {s}", .{
                    cmd_info.name,
                    @errorName(err),
                });
            };
        } else {
            return client.writeError("ERR unknown command");
        }
    }
};
