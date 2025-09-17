const std = @import("std");
const store = @import("../store.zig");
const Store = store.Store;
const ZedisObject = store.ZedisObject;
const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;

pub const StringCommandError = error{
    WrongType,
    ValueNotInteger,
    KeyNotFound,
};

pub fn set(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const value = args[2].asSlice();

    const maybe_int = std.fmt.parseInt(i64, value, 10);

    if (maybe_int) |int_value| {
        try client.store.setInt(key, int_value);
    } else |_| {
        try client.store.setString(key, value);
    }

    _ = try client.connection.stream.write("+OK\r\n");
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
        }
    } else {
        try client.writeNull();
    }
}

pub fn incr(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const new_value = incrDecr(client.store, key, 1) catch |err| switch (err) {
        StringCommandError.WrongType => {
            return client.writeError("ERR value is not an integer or out of range");
        },
        StringCommandError.ValueNotInteger => {
            return client.writeError("ERR value is not an integer or out of range");
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
        }

        // Use the unsafe method since we already have the lock
        const int_object = ZedisObject{ .value = .{ .int = new_value } };
        try store_ptr.setObjectUnsafe(key, int_object);

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
