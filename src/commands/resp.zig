const std = @import("std");
const storeModule = @import("../store.zig");
const Store = storeModule.Store;
const ZedisObject = storeModule.ZedisObject;
const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;
const ZedisValue = storeModule.ZedisValue;

// --- RESP Writing Helpers ---

pub fn writeError(writer: *std.Io.Writer, msg: []const u8) !void {
    try writer.print("-{s}\r\n", .{msg});
}

pub fn writeBulkString(writer: *std.Io.Writer, str: []const u8) !void {
    try writer.print("${d}\r\n{s}\r\n", .{ str.len, str });
}

// no need for any allocating/logic, just write 1 and the int
pub fn writeBulkSingleIntString(writer: *std.Io.Writer, int: comptime_int) !void {
    try writer.print("${d}\r\n{d}\r\n", .{ 1, int });
}

pub fn writeBulkIntString(writer: *std.Io.Writer, int: i64) !void {
    var buf: [19]u8 = undefined;
    const len = std.fmt.printInt(&buf, int, 10, .upper, .{}) + 1;
    try writer.print("${d}\r\n{s}\r\n", .{ 1, buf[0..len] });
}

pub fn writeInt(writer: *std.Io.Writer, value: i64) !void {
    try writer.print(":{d}\r\n", .{value});
}

pub fn writeArray(writer: *std.Io.Writer, values: []const ZedisValue) !void {
    try writer.print("*{d}\r\n", .{values.len});

    // 2. Iterate over each element and write it to the stream.
    for (values) |value| {
        switch (value) {
            .string => |s| try writeBulkString(writer, s),
            .int => |i| try writeInt(writer, i),
        }
    }
}
pub fn writeTupleAsArray(writer: *std.Io.Writer, items: anytype) !void {
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

    try writer.print("*{d}\r\n", .{struct_info.fields.len});
    // 4. Use 'inline for' to iterate over the tuple's elements at compile time.
    //    This loop is "unrolled" by the compiler, generating specific code
    //    for each element's type with no runtime overhead.
    inline for (items) |item| {
        // Check the type of the current item and call the correct serializer.
        const ItemType = @TypeOf(item);
        if (ItemType == []const u8) {
            try writeBulkString(writer, item);
        } else if (ItemType == i64) {
            try writeInt(writer, item);
        } else {
            // Handle string literals and other pointer-to-array types by checking if they can be coerced to []const u8
            const item_as_slice: []const u8 = item;
            try writeBulkString(writer, item_as_slice);
        }
    }
}

pub fn writeNull(writer: *std.Io.Writer) !void {
    _ = try writer.write("$-1\r\n");
}
