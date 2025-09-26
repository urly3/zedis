const std = @import("std");
const Store = @import("../store.zig").Store;
const Value = @import("../parser.zig").Value;
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
