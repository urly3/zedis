const std = @import("std");
const Store = @import("store.zig").Store;

pub const RdbWriteError = error{ StringTooLarge, NumberTooLarge };

const ValueType = enum {
    int,
    string,
};
const WriteType = union(ValueType) { int: u32, string: []const u8 };

pub const ZDB = struct {
    allocator: std.mem.Allocator,
    store: *Store,
    buffer: *[1024]u8,
    writer: std.Io.Writer,
    file: std.fs.File,

    pub fn init(allocator: std.mem.Allocator, store: *Store, fileName: []const u8) !ZDB {
        std.fs.cwd().deleteFile(fileName) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        const file = try std.fs.cwd().createFile(fileName, .{ .truncate = true });
        const buffer = try allocator.create([1024]u8);
        const writer = file.writer(buffer);

        return .{
            .allocator = allocator,
            .buffer = buffer,
            .file = file,
            .store = store,
            .writer = writer.interface,
        };
    }

    pub fn deinit(self: *ZDB) void {
        self.file.close();
        self.allocator.destroy(self.buffer);
    }

    pub fn writeFile(self: *ZDB) !void {
        try self.writeHeader();
        try self.writer.flush();
    }

    fn writeHeader(self: *ZDB) !void {
        _ = try self.writer.write("REDIS");
        _ = try self.writer.write("0012");
        // Auxiliary fields (key,value)
        try self.writeMetadata("redis-ver", .{ .string = "255.255.255" });
        const bits = if (@sizeOf(usize) == 8) 64 else 32;
        try self.writeMetadata("redis-bits", .{ .int = bits });

        // SELECTDB
        _ = try self.writer.writeByte(0xFE);
        // db number
        _ = try self.writer.writeByte(0x00);
        // RESIZEDB
        _ = try self.writer.writeByte(0xFB);
        // Database hash table size (truncated to one byte for now)
        _ = try self.writer.writeByte(@intCast(@as(u8, @truncate(self.store.size()))));
        // Expiry hash table size
        // Set as 0 for now
        _ = try self.writer.writeByte(0x00);
    }

    fn writeMetadata(self: *ZDB, key: []const u8, value: WriteType) !void {
        // 0xFA indicates auxiliary field; we encode key then value as length-prefixed strings.
        try self.writer.writeByte(0xFA);
        try self.genericWrite(.{ .string = key });
        try self.genericWrite(value);
    }

    pub fn genericWrite(self: *ZDB, payload: WriteType) !void {
        switch (payload) {
            .int => |number| {
                if (number <= 63) {
                    // Bits: 00
                    // The length fits in the lower 6 bits of a single byte.
                    const byte = @as(u8, @truncate(number));
                    try self.writer.writeByte(byte);
                } else if (number <= 16383) {
                    // Bits: 01
                    // The length fits in 14 bits, spread across two bytes.
                    const first_byte = 0b01000000 | @as(u8, @truncate(number >> 8));
                    const second_byte = @as(u8, @truncate(number));
                    try self.writer.writeByte(first_byte);
                    try self.writer.writeByte(second_byte);
                } else {
                    // Bits: 10
                    // The length requires a 4-byte representation.
                    try self.writer.writeByte(0b10000000);
                    try self.writer.writeInt(u32, number, .big);
                }
            },
            .string => |str| {
                const len = str.len;
                if (len > 255) return RdbWriteError.NumberTooLarge;
                try self.writer.writeByte(@intCast(len));
                _ = try self.writer.writeAll(str);
            },
        }
    }
};

const testing = std.testing;

test "ZDB init and deinit" {
    const allocator = testing.allocator;

    var store = Store.init(allocator);
    const test_file = "test_db.rdb";

    var zdb = try ZDB.init(allocator, &store, test_file);
    defer zdb.deinit();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    try testing.expect(zdb.allocator.ptr == allocator.ptr);
    try testing.expect(zdb.store == &store);
}

test "ZDB writeFile creates valid RDB header" {
    const allocator = testing.allocator;

    var store = Store.init(allocator);
    const test_file = "test_header.rdb";

    var zdb = try ZDB.init(allocator, &store, test_file);
    defer zdb.deinit();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    try zdb.writeFile();

    const file_content = try std.fs.cwd().readFileAlloc(allocator, test_file, 1024);
    defer allocator.free(file_content);

    try testing.expect(std.mem.startsWith(u8, file_content, "REDIS0012"));
    try testing.expect(file_content[9] == 0xFA); // metadata marker
}

test "ZDB writeString writes correct format" {
    const allocator = testing.allocator;

    var store = Store.init(allocator);
    const test_file = "test_string.rdb";

    var zdb = try ZDB.init(allocator, &store, test_file);
    defer zdb.deinit();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    try zdb.genericWrite(.{ .string = "test" });
    try zdb.writer.flush();

    const file_content = try std.fs.cwd().readFileAlloc(allocator, test_file, 1024);
    defer allocator.free(file_content);

    try testing.expectEqual(@as(u8, 4), file_content[0]);
    try testing.expect(std.mem.eql(u8, file_content[1..5], "test"));
}

test "ZDB writeMetadata writes correct format" {
    const allocator = testing.allocator;

    var store = Store.init(allocator);
    const test_file = "test_string.rdb";

    var zdb = try ZDB.init(allocator, &store, test_file);
    defer zdb.deinit();
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const key = "test";
    const value = "random";
    try zdb.writeMetadata(key, value);
    try zdb.writer.flush();

    const file_content = try std.fs.cwd().readFileAlloc(allocator, test_file, 1024);
    defer allocator.free(file_content);

    try testing.expectEqual(0xFA, file_content[0]);
    // Key
    try testing.expectEqual(key.len, file_content[1]);
    try testing.expect(std.mem.eql(u8, file_content[2..6], key));

    // Value
    try testing.expectEqual(value.len, file_content[key.len + 2]);

    const valueStart = 3 + key.len;
    const valueEnd = valueStart + value.len;
    try testing.expect(std.mem.eql(u8, file_content[valueStart..valueEnd], value));
}
