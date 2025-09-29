const std = @import("std");
const Client = @import("../client.zig").Client;
const Server = @import("../server.zig").Server;
const Store = @import("../store.zig").Store;
const Value = @import("../parser.zig").Value;
const resp = @import("resp.zig");

// PING command implementation
pub fn ping(writer: *std.Io.Writer, args: []const Value) !void {
    if (args.len == 1) {
        try resp.writeBulkString(writer, "PONG");
    } else {
        try resp.writeBulkString(writer, args[1].asSlice());
    }
}

// ECHO command implementation
pub fn echo(writer: *std.Io.Writer, args: []const Value) !void {
    try resp.writeBulkString(writer, args[1].asSlice());
}

// QUIT command implementation
pub fn quit(writer: *std.Io.Writer, args: []const Value) !void {
    _ = args; // Unused parameter
    _ = try writer.write("+OK\r\n");
    return error.ClientQuit;
}

// AUTH command implementation
pub fn auth(client: *Client, args: []const Value) !void {
    const password = args[1].asSlice();
    const writer = &client.writer.interface;

    if (!client.server.config.requiresAuth()) {
        return resp.writeError(writer, "ERR Client sent AUTH, but no password is set");
    }

    if (std.mem.eql(u8, password, client.server.config.requirepass.?)) {
        client.authenticated = true;
        try resp.writeBulkString(writer, "OK");
    } else {
        client.authenticated = false;
        try resp.writeError(writer, "ERR invalid password");
    }
}

// HELP command implementation
pub fn help(writer: *std.Io.Writer, args: []const Value) !void {
    _ = args; // Unused parameter
    const help_text =
        \\Zedis Server Commands:
        \\
        \\Connection Commands:
        \\  PING [message]     - Ping the server
        \\  ECHO <message>     - Echo the given string
        \\  QUIT               - Close the connection
        \\  HELP               - Show this help message
        \\
        \\String Commands:
        \\  SET <key> <value>  - Set string value of a key
        \\  GET <key>          - Get string value of a key
        \\  INCR <key>         - Increment the value of a key
        \\  DECR <key>         - Decrement the value of a key
    ;

    try resp.writeBulkString(writer, help_text);
}
