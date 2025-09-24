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
const MockClient = @import("../test_utils.zig").MockClient;

test "SET command with string value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        Value{ .data = "SET" },
        Value{ .data = "key1" },
        Value{ .data = "hello" },
    };

    try client.testSet(&args);

    try testing.expectEqualStrings("+OK\r\n", client.getOutput());

    const stored_value = store.get("key1");
    try testing.expect(stored_value != null);
    try testing.expectEqualStrings("hello", stored_value.?.value.string);
}

test "SET command with integer value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        Value{ .data = "SET" },
        Value{ .data = "key1" },
        Value{ .data = "42" },
    };

    try client.testSet(&args);

    try testing.expectEqualStrings("+OK\r\n", client.getOutput());

    const stored_value = store.get("key1");
    try testing.expect(stored_value != null);
    try testing.expectEqual(@as(i64, 42), stored_value.?.value.int);
}

test "GET command with existing string value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    try store.setString("key1", "hello");

    const args = [_]Value{
        Value{ .data = "GET" },
        Value{ .data = "key1" },
    };

    try client.testGet(&args);

    try testing.expectEqualStrings("$5\r\nhello\r\n", client.getOutput());
}

test "GET command with existing integer value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    try store.setInt("key1", 42);

    const args = [_]Value{
        Value{ .data = "GET" },
        Value{ .data = "key1" },
    };

    try client.testGet(&args);

    try testing.expectEqualStrings("$2\r\n42\r\n", client.getOutput());
}

test "GET command with non-existing key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        Value{ .data = "GET" },
        Value{ .data = "nonexistent" },
    };

    try client.testGet(&args);

    try testing.expectEqualStrings("$-1\r\n", client.getOutput());
}

test "INCR command on non-existing key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        Value{ .data = "INCR" },
        Value{ .data = "counter" },
    };

    try client.testIncr(&args);

    try testing.expectEqualStrings("$1\r\n1\r\n", client.getOutput());

    const stored_value = store.get("counter");
    try testing.expect(stored_value != null);
    try testing.expectEqual(@as(i64, 1), stored_value.?.value.int);
}

test "INCR command on existing integer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    try store.setInt("counter", 5);

    const args = [_]Value{
        Value{ .data = "INCR" },
        Value{ .data = "counter" },
    };

    try client.testIncr(&args);

    try testing.expectEqualStrings("$1\r\n6\r\n", client.getOutput());

    const stored_value = store.get("counter");
    try testing.expect(stored_value != null);
    try testing.expectEqual(@as(i64, 6), stored_value.?.value.int);
}

test "INCR command on string that represents integer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    try store.setString("counter", "10");

    const args = [_]Value{
        Value{ .data = "INCR" },
        Value{ .data = "counter" },
    };

    try client.testIncr(&args);

    try testing.expectEqualStrings("$2\r\n11\r\n", client.getOutput());

    const stored_value = store.get("counter");
    try testing.expect(stored_value != null);
    try testing.expectEqual(@as(i64, 11), stored_value.?.value.int);
}

test "INCR command on non-integer string" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    try store.setString("key1", "hello");

    const args = [_]Value{
        Value{ .data = "INCR" },
        Value{ .data = "key1" },
    };

    try client.testIncr(&args);

    try testing.expectEqualStrings("-ERR value is not an integer or out of range\r\n", client.getOutput());
}

test "DECR command on non-existing key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        Value{ .data = "DECR" },
        Value{ .data = "counter" },
    };

    try client.testDecr(&args);

    try testing.expectEqualStrings("$2\r\n-1\r\n", client.getOutput());

    const stored_value = store.get("counter");
    try testing.expect(stored_value != null);
    try testing.expectEqual(@as(i64, -1), stored_value.?.value.int);
}

test "DECR command on existing integer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    try store.setInt("counter", 10);

    const args = [_]Value{
        Value{ .data = "DECR" },
        Value{ .data = "counter" },
    };

    try client.testDecr(&args);

    try testing.expectEqualStrings("$1\r\n9\r\n", client.getOutput());

    const stored_value = store.get("counter");
    try testing.expect(stored_value != null);
    try testing.expectEqual(@as(i64, 9), stored_value.?.value.int);
}

test "DEL command with single existing key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    try store.setString("key1", "value1");

    const args = [_]Value{
        Value{ .data = "DEL" },
        Value{ .data = "key1" },
    };

    try client.testDel(&args);

    try testing.expectEqualStrings(":1\r\n", client.getOutput());

    const stored_value = store.get("key1");
    try testing.expect(stored_value == null);
}

test "DEL command with multiple keys" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    try store.setString("key1", "value1");
    try store.setString("key2", "value2");
    try store.setInt("key3", 42);

    const args = [_]Value{
        Value{ .data = "DEL" },
        Value{ .data = "key1" },
        Value{ .data = "key2" },
        Value{ .data = "key3" },
        Value{ .data = "nonexistent" },
    };

    try client.testDel(&args);

    try testing.expectEqualStrings(":3\r\n", client.getOutput());

    try testing.expect(store.get("key1") == null);
    try testing.expect(store.get("key2") == null);
    try testing.expect(store.get("key3") == null);
}

test "DEL command with non-existing key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        Value{ .data = "DEL" },
        Value{ .data = "nonexistent" },
    };

    try client.testDel(&args);

    try testing.expectEqualStrings(":0\r\n", client.getOutput());
}

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
