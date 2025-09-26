const std = @import("std");
const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;

// PING command implementation
pub fn ping(client: *Client, args: []const Value) !void {
    if (args.len == 1) {
        try client.writeBulkString("PONG");
    } else {
        try client.writeBulkString(args[1].asSlice());
    }
}

// ECHO command implementation
pub fn echo(client: *Client, args: []const Value) !void {
    try client.writeBulkString(args[1].asSlice());
}

// QUIT command implementation
pub fn quit(client: *Client, args: []const Value) !void {
    _ = args; // Unused parameter
    _ = try client.writer.interface.write("+OK\r\n");
    client.connection.stream.close();
}

pub fn auth(client: *Client, args: []const Value) !void {
    const password = args[1].asSlice();

    if (!client.server.config.requiresAuth()) {
        return client.writeError("ERR Client sent AUTH, but no password is set");
    }

    if (std.mem.eql(u8, password, client.server.config.requirepass.?)) {
        client.authenticated = true;
        try client.writeBulkString("OK");
    } else {
        client.authenticated = false;
        try client.writeError("ERR invalid password");
    }
}

// HELP command implementation
pub fn help(client: *Client, args: []const Value) !void {
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

    try client.writeBulkString(help_text);
}
