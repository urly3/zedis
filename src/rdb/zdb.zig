const std = @import("std");
const Store = @import("../store.zig").Store;
const CRC64 = @import("./checksum.zig").CRC64;

pub const RdbWriteError = error{ StringTooLarge, NumberTooLarge };

const WriteType = union(enum) {
    int: u64,
    string: []const u8,
};

const OPCODE_AUX = 0xFA;
const OPCODE_RESIZE_DB = 0xFB;
const OPCODE_EXPIRE_TIME_MS = 0xFC;
const OPCODE_EXPIRE_TIME = 0xFD;
const OPCODE_SELECT_DB = 0xFE;
const OPCODE_EOF = 0xFF;

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
        try self.writeHeader();
        try self.writer.flush();
    }

    fn writeHeader(self: *ZDB) !void {
        try self.writeAuxFields();

        try self.writer.writeByte(OPCODE_SELECT_DB);
        try self.writeRdbLength(0x00);

        try self.writer.writeByte(OPCODE_RESIZE_DB);
        try self.writeRdbLength(self.store.size());
        // TODO Write the size of the expiry hash table
        try self.writeRdbLength(0);
    }

    fn writeEndOfFile(self: *ZDB) !void {
        try self.writer.writeByte(OPCODE_EOF);
        // TODO
        // const buffer = self.file.read
        // const checksum = CRC64.checksum(buffer);
        // try self.writer.writeInt(u64, checksum, .little);
    }

    fn writeAuxFields(self: *ZDB) !void {
        _ = try self.writer.write("REDIS");
        _ = try self.writer.write("0012");

        try self.writeMetadata("redis-ver", .{ .string = "255.255.255" });

        const bits = if (@sizeOf(usize) == 8) 64 else 32;
        try self.writeMetadata("redis-bits", .{ .int = bits });

        const now_timestamp: u64 = @intCast(std.time.timestamp());
        try self.writeMetadata("ctime", .{ .int = now_timestamp });

        try self.writeMetadata("used-mem", .{ .int = 100 });
    }

    fn writeMetadata(self: *ZDB, key: []const u8, value: WriteType) !void {
        // 0xFA indicates auxiliary field; we encode key then value as length-prefixed strings.
        try self.writer.writeByte(0xFA);
        try self.genericWrite(.{ .string = key });
        try self.genericWrite(value);
    }

    fn writeCache(self: *ZDB) !void {
        var it = self.store.map.iterator();
        while (it.next()) |entry| {
            // Write the expiry FIRST (if it exists).
            if (entry.value_ptr.*.expiry) |expiry| {
                try self.writer.writeByte(OPCODE_EXPIRE_TIME_MS);
                try self.writer.writeInt(u64, expiry, .little);
            }

            // Write the value type opcode.
            const typeOpCode = entry.value_ptr.valueType.toRdbOpcode();
            try self.writer.writeByte(typeOpCode);

            // Write the key.
            try self.writeRdbString(entry.key_ptr.*);

            // Write the value.
            switch (entry.value_ptr.*.value) {
                .int => |i| try self.writeRdbInteger(i),
                .string => |s| try self.writeRdbString(s),
            }
        }
    }

    fn writeRdbLength(self: *ZDB, len: u64) !void {
        if (len <= 63) { // 6-bit
            try self.writer.writeByte(@as(u8, @truncate(len)));
        } else if (len <= 16383) { // 14-bit
            const first_byte = 0b01000000 | @as(u8, @truncate(len >> 8));
            const second_byte = @as(u8, @truncate(len));
            try self.writer.writeByte(first_byte);
            try self.writer.writeByte(second_byte);
        } else if (len <= 0xFFFFFFFF) { // 32-bit
            try self.writer.writeByte(0b10000000);
            try self.writer.writeInt(u32, @intCast(len), .big);
        } else { // 64-bit
            try self.writer.writeByte(0b10000001);
            try self.writer.writeInt(u64, len, .big);
        }
    }

    fn writeRdbString(self: *ZDB, str: []const u8) !void {
        try self.writeRdbLength(str.len);
        try self.writer.writeAll(str);
    }

    fn writeRdbInteger(self: *ZDB, number: u64) !void {
        if (number <= 127) { // Can fit in i8
            try self.writer.writeByte(0b11000000); // 0xC0
            try self.writer.writeInt(i8, @intCast(number), .little);
        } else if (number <= 32767) { // Can fit in i16
            try self.writer.writeByte(0b11000001); // 0xC1
            try self.writer.writeInt(i16, @intCast(number), .little);
        } else if (number <= 2147483647) { // Can fit in i32
            try self.writer.writeByte(0b11000010); // 0xC2
            try self.writer.writeInt(i32, @intCast(number), .little);
        } else {
            // Fallback for larger numbers: write as a string.
            var buf: [20]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{}", .{number});
            try self.writeRdbString(str);
        }
    }

    fn genericWrite(self: *ZDB, payload: WriteType) !void {
        switch (payload) {
            .int => |number| try self.writeRdbInteger(number),
            .string => |str| try self.writeRdbString(str),
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
