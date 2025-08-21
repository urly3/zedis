const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Store = @import("store.zig").Store;
const Command = @import("parser.zig").Command;
const Value = @import("parser.zig").Value;

pub const Client = struct {
    allocator: std.mem.Allocator,
    connection: std.net.Server.Connection,
    reader: std.net.Stream.Reader,
    writer: std.net.Stream.Writer,
    store: *Store,

    // Initializes a new client handler.
    pub fn init(allocator: std.mem.Allocator, connection: std.net.Server.Connection, store: *Store) Client {
        return .{
            .allocator = allocator,
            .connection = connection,
            .reader = connection.stream.reader(),
            .writer = connection.stream.writer(),
            .store = store,
        };
    }

    // Cleans up client resources.
    pub fn deinit(self: *Client) void {
        self.connection.stream.close();
    }

    // Main loop for a client. It continuously reads and processes commands.
    pub fn handle(self: *Client) !void {
        while (true) {
            // Parse the incoming command from the client's stream.
            var parser = Parser.init(self.allocator, self.reader);
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
        if (command.args.items.len == 0) {
            return try self.writeError("ERR empty command");
        }

        const command_name = command.args.items[0].asSlice();

        if (std.ascii.eqlIgnoreCase(command_name, "PING")) {
            try self.handlePing(command.args.items);
        } else if (std.ascii.eqlIgnoreCase(command_name, "ECHO")) {
            try self.handleEcho(command.args.items);
        } else if (std.ascii.eqlIgnoreCase(command_name, "SET")) {
            try self.handleSet(command.args.items);
        } else if (std.ascii.eqlIgnoreCase(command_name, "GET")) {
            try self.handleGet(command.args.items);
        } else {
            try self.writeError("ERR unknown command");
        }
    }

    // --- Command Handlers ---

    fn handlePing(self: *Client, args: []const Value) !void {
        if (args.len > 2) return try self.writeError("ERR wrong number of arguments for 'ping'");
        if (args.len == 1) {
            try self.writer.writeAll("+PONG\r\n");
        } else {
            try self.writeBulkString(args[1].asSlice());
        }
    }

    fn handleEcho(self: *Client, args: []const Value) !void {
        if (args.len != 2) return try self.writeError("ERR wrong number of arguments for 'echo'");
        try self.writeBulkString(args[1].asSlice());
    }

    fn handleSet(self: *Client, args: []const Value) !void {
        if (args.len != 3) return try self.writeError("ERR wrong number of arguments for 'set'");
        const key = args[1].asSlice();
        const value = args[2].asSlice();
        try self.store.set(key, value);
        try self.writer.writeAll("+OK\r\n");
    }

    fn handleGet(self: *Client, args: []const Value) !void {
        if (args.len != 2) return try self.writeError("ERR wrong number of arguments for 'get'");
        const key = args[1].asSlice();
        const value = self.store.get(key);
        if (value) |v| {
            try self.writeBulkString(v);
        } else {
            try self.writeNull();
        }
    }

    // --- RESP Writing Helpers ---

    fn writeError(self: *Client, msg: []const u8) !void {
        try self.writer.print("-{s}\r\n", .{msg});
    }

    fn writeBulkString(self: *Client, str: []const u8) !void {
        try self.writer.print("${d}\r\n{s}\r\n", .{ str.len, str });
    }

    fn writeNull(self: *Client) !void {
        try self.writer.writeAll("$-1\r\n");
    }
};
