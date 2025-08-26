const std = @import("std");

// Represents a value in the RESP protocol, which is a bulk string.
pub const Value = struct {
    data: []const u8,

    pub fn asSlice(self: Value) []const u8 {
        return self.data;
    }
};

// Represents a parsed command, which is an array of values.
pub const Command = struct {
    args: std.ArrayList(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Command {
        return Command{
            .args = std.ArrayList(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Command) void {
        self.args.clearAndFree();
    }

    pub fn append(self: *Command, value: Value) !void {
        try self.args.append(value);
    }
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    reader: std.net.Stream.Reader,
    line_buf: [1024 * 2]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, reader: std.net.Stream.Reader) Parser {
        return .{ .allocator = allocator, .reader = reader };
    }

    // Main parsing function. It expects a command to be a RESP array of bulk strings:
    // *<num>\r\n$<len>\r\n<data>\r\n ...
    pub fn parse(self: *Parser) !Command {
        const line = try self.readLine();
        if (line.len == 0 or line[0] != '*') {
            return error.InvalidProtocol;
        }

        const num_args = try std.fmt.parseInt(usize, line[1..], 10);
        var command = try Command.init(self.allocator);
        errdefer command.deinit();

        var i: usize = 0;
        while (i < num_args) : (i += 1) {
            const value = try self.parseValue();
            try command.append(value);
        }

        return command;
    }

    // Parses a single RESP value, currently only handling bulk strings ($)
    // Future RESP types (Simple Strings '+', Errors '-', Integers ':', Arrays '*') can be added here.
    fn parseValue(self: *Parser) !Value {
        const line = try self.readLine();
        if (line.len == 0 or line[0] != '$') {
            return error.InvalidProtocol;
        }

        const len = try std.fmt.parseInt(isize, line[1..], 10);
        if (len < 0) {
            // This represents a null bulk string. We'll treat it as empty.
            return Value{ .data = "" };
        }

        const ulen: usize = @intCast(len);
        const data = try self.allocator.alloc(u8, ulen);
        errdefer self.allocator.free(data);

        var read_total: usize = 0;
        while (read_total < ulen) {
            const n = try self.reader.read(data[read_total..]);
            if (n == 0) return error.EndOfStream;
            read_total += n;
        }

        // Expect trailing CRLF after the bulk string payload
        var crlf: [2]u8 = undefined;
        try self.reader.readNoEof(&crlf);
        if (crlf[0] != '\r' or crlf[1] != '\n') return error.InvalidProtocol;

        return Value{ .data = data };
    }

    // Reads a RESP line terminated by CRLF. Returns slice of internal buffer (valid until next call).
    fn readLine(self: *Parser) ![]const u8 {
        var i: usize = 0;
        while (true) {
            const b = self.reader.readByte() catch |err| {
                if (err == error.EndOfStream and i == 0) return error.EndOfStream;
                return err;
            };
            switch (b) {
                '\r' => {
                    const next = self.reader.readByte() catch |err| {
                        if (err == error.EndOfStream) return error.InvalidProtocol; // incomplete CRLF
                        return err;
                    };
                    if (next != '\n') return error.InvalidProtocol;
                    return self.line_buf[0..i];
                },
                '\n' => return error.InvalidProtocol, // bare LF not allowed
                else => {
                    if (i >= self.line_buf.len) return error.LineTooLong;
                    self.line_buf[i] = b;
                    i += 1;
                },
            }
        }
    }
};
