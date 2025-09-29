const std = @import("std");
const Server = @import("../server.zig").Server;
const Parser = @import("../parser.zig").Parser;
const Command = @import("../parser.zig").Command;

const DEFAULT_NAME = "test.aof";

pub const Writer = struct {
    enabled: bool,
    file_writer: ?std.fs.File.Writer,

    // take path when ready to
    pub fn init(enabled: bool) !Writer {
        var fw: std.fs.File.Writer = undefined;
        if (enabled) {
            const file = try std.fs.cwd().openFile(DEFAULT_NAME, .{ .mode = .write_only });
            fw = file.writer(&.{});
            try fw.seekTo(try file.getEndPos());
        }
        return .{
            .enabled = enabled,
            .file_writer = if (enabled) fw else null,
        };
    }

    pub fn deinit(self: *Writer) void {
        if (self.file_writer) |fw| {
            fw.file.close();
        }
    }

    // only to be called if enabled
    // could return an error too
    // probably should
    pub fn writer(self: *Writer) *std.Io.Writer {
        return &self.file_writer.?.interface;
    }
};

pub const Reader = struct {
    file_reader: std.fs.File.Reader,
    allocator: std.mem.Allocator,

    // take path when ready to
    pub fn init(allocator: std.mem.Allocator) !Reader {
        const file = try std.fs.cwd().openFile(DEFAULT_NAME, .{ .mode = .read_only });
        const reader = file.reader(&.{});
        return .{
            .file_reader = reader,
            .allocator = allocator,
        };
    }

    pub fn read(self: *Reader, server: *Server) !void {
        const allocator = server.temp_arena.allocator();
        var parser = Parser.init(self.allocator);
        // FIXME:  magic number as initial cap
        var commands = try std.ArrayList(Command).initCapacity(allocator, 128);
        defer commands.deinit(allocator);
        const registry = &server.registry;

        var writer = std.Io.Writer.Discarding.init(&.{});

        while (parser.parse(&self.file_reader.interface)) |command| {
            try commands.append(allocator, command);
        } else |_| {}

        for (commands.items) |command| {
            try registry.executeCommand(&writer.writer, null, &server.store, command.args.items);
        }
    }
};
