const std = @import("std");
const storeModule = @import("../store.zig");
const Store = storeModule.Store;
const ZedisObject = storeModule.ZedisObject;
const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;

pub const StringCommandError = error{
    WrongType,
    ValueNotInteger,
    KeyNotFound,
};

fn getErrorMessage(err: StringCommandError) []const u8 {
    return switch (err) {
        StringCommandError.WrongType => "WRONGTYPE Operation against a key holding the wrong kind of value",
        StringCommandError.ValueNotInteger => "ERR value is not an integer or out of range",
        StringCommandError.KeyNotFound => "ERR key not found",
    };
}

pub fn set(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const value = args[2].asSlice();

    const maybe_int = std.fmt.parseInt(i64, value, 10);

    if (maybe_int) |int_value| {
        try client.store.setInt(key, int_value);
    } else |_| {
        try client.store.setString(key, value);
    }

    _ = try client.writer.interface.write("+OK\r\n");
}

pub fn get(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const value = client.store.get(key);

    if (value) |v| {
        switch (v.value) {
            .string => |s| try client.writeBulkString(s),
            .int => |i| {
                const int_str = try std.fmt.allocPrint(client.allocator, "{d}", .{i});
                defer client.allocator.free(int_str);
                try client.writeBulkString(int_str);
            },
            .list => |*list| {
                var current = list.list.first;
                while (current) |node| {
                    const list_node: *const @import("../store.zig").ZedisListNode = @fieldParentPtr("node", node);
                    const entry = list_node.data;

                    switch (entry) {
                        .string => |str| try client.writeBulkString(str),
                        .int => |i| {
                            const int_str = try std.fmt.allocPrint(client.allocator, "{d}", .{i});
                            defer client.allocator.free(int_str);
                            try client.writeBulkString(int_str);
                        },
                    }

                    current = node.next;
                }
            },
        }
    } else {
        try client.writeNull();
    }
}

pub fn incr(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const new_value = incrDecr(client.store, key, 1) catch |err| switch (err) {
        StringCommandError.WrongType => |e| {
            return client.writeError(getErrorMessage(e));
        },
        StringCommandError.ValueNotInteger => |e| {
            return client.writeError(getErrorMessage(e));
        },
        StringCommandError.KeyNotFound => {
            // For INCR on non-existent key, Redis creates it with value 0 then increments
            try client.store.setInt(key, 1);
            const result_str = try std.fmt.allocPrint(client.allocator, "{d}", .{1});
            defer client.allocator.free(result_str);
            try client.writeBulkString(result_str);
            return;
        },
        else => return err,
    };

    const result_str = try std.fmt.allocPrint(client.allocator, "{d}", .{new_value});
    defer client.allocator.free(result_str);
    try client.writeBulkString(result_str);
}

pub fn decr(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const new_value = incrDecr(client.store, key, -1) catch |err| switch (err) {
        StringCommandError.WrongType => {
            return client.writeError("ERR value is not an integer or out of range");
        },
        StringCommandError.ValueNotInteger => {
            return client.writeError("ERR value is not an integer or out of range");
        },
        StringCommandError.KeyNotFound => {
            // For DECR on non-existent key, Redis creates it with value 0 then decrements
            try client.store.setInt(key, -1);
            const result_str = try std.fmt.allocPrint(client.allocator, "{d}", .{-1});
            defer client.allocator.free(result_str);
            try client.writeBulkString(result_str);
            return;
        },
        else => return err,
    };

    const result_str = try std.fmt.allocPrint(client.allocator, "{d}", .{new_value});
    defer client.allocator.free(result_str);
    try client.writeBulkString(result_str);
}

fn incrDecr(store_ptr: *Store, key: []const u8, value: i64) !i64 {
    const current_value = store_ptr.map.get(key);
    if (current_value) |v| {
        var new_value: i64 = undefined;

        switch (v.value) {
            .string => |_| {
                const intValue = std.fmt.parseInt(i64, v.value.string, 10) catch {
                    return StringCommandError.ValueNotInteger;
                };
                new_value = std.math.add(i64, intValue, value) catch {
                    return StringCommandError.ValueNotInteger;
                };
            },
            .int => |_| {
                new_value = std.math.add(i64, v.value.int, value) catch {
                    return StringCommandError.ValueNotInteger;
                };
            },
            else => return StringCommandError.ValueNotInteger,
        }

        const int_object = ZedisObject{ .value = .{ .int = new_value } };
        try store_ptr.setObject(key, int_object);

        return new_value;
    } else {
        return StringCommandError.KeyNotFound;
    }
}

pub fn del(client: *Client, args: []const Value) !void {
    var deleted: u32 = 0;
    for (args[1..]) |key| {
        if (client.store.delete(key.asSlice())) {
            deleted += 1;
        }
    }

    try client.writeInt(deleted);
}

pub fn expire(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const expiration_seconds = args[2].asInt() catch {
        return client.writeInt(0);
    };

    const result = if (expiration_seconds < 0)
        client.store.delete(key)
    else
        client.store.expire(key, std.time.milliTimestamp() + (expiration_seconds * 1000)) catch false;

    try client.writeInt(if (result) 1 else 0);
}

const testing = std.testing;

test "incrDecr helper function with string integer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    try store.setString("key1", "100");

    const result = try incrDecr(&store, "key1", 50);
    try testing.expectEqual(@as(i64, 150), result);

    const stored_value = store.get("key1");
    try testing.expect(stored_value != null);
    try testing.expectEqual(@as(i64, 150), stored_value.?.value.int);
}

test "incrDecr helper function with integer overflow" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    try store.setInt("key1", std.math.maxInt(i64));

    const result = incrDecr(&store, "key1", 1);
    try testing.expectError(StringCommandError.ValueNotInteger, result);
}

test "incrDecr helper function with non-existent key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    const result = incrDecr(&store, "nonexistent", 1);
    try testing.expectError(StringCommandError.KeyNotFound, result);
}
