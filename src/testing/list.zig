const std = @import("std");
const Store = @import("../store.zig").Store;
const Value = @import("../parser.zig").Value;
const testing = std.testing;
const MockClient = @import("../test_utils.zig").MockClient;

// LPUSH Tests
test "LPUSH single element to new list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "world" },
    };

    try client.testLpush(&args);

    try testing.expectEqualStrings(":1\r\n", client.getOutput());

    // Verify the list was created and contains the element
    const list = try store.getList("mylist");
    try testing.expect(list != null);
    try testing.expectEqual(@as(usize, 1), list.?.len());
}

test "LPUSH multiple elements to new list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "three" },
        .{ .data = "two" },
        .{ .data = "one" },
    };

    try client.testLpush(&args);

    try testing.expectEqualStrings(":3\r\n", client.getOutput());

    // Verify the list has 3 elements
    const list = try store.getList("mylist");
    try testing.expect(list != null);
    try testing.expectEqual(@as(usize, 3), list.?.len());
}

test "LPUSH to existing list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // First, add some elements
    const args1 = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "initial" },
    };
    try client.testLpush(&args1);
    client.clearOutput();

    // Then add more elements
    const args2 = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "second" },
        .{ .data = "first" },
    };
    try client.testLpush(&args2);

    try testing.expectEqualStrings(":3\r\n", client.getOutput());

    const list = try store.getList("mylist");
    try testing.expect(list != null);
    try testing.expectEqual(@as(usize, 3), list.?.len());
}

// RPUSH Tests
test "RPUSH single element to new list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "hello" },
    };

    try client.testRpush(&args);

    try testing.expectEqualStrings(":1\r\n", client.getOutput());

    const list = try store.getList("mylist");
    try testing.expect(list != null);
    try testing.expectEqual(@as(usize, 1), list.?.len());
}

test "RPUSH multiple elements to new list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
        .{ .data = "two" },
        .{ .data = "three" },
    };

    try client.testRpush(&args);

    try testing.expectEqualStrings(":3\r\n", client.getOutput());

    const list = try store.getList("mylist");
    try testing.expect(list != null);
    try testing.expectEqual(@as(usize, 3), list.?.len());
}

// LPOP Tests
test "LPOP from list with single element" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // First create a list with one element
    const push_args = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "hello" },
    };
    try client.testLpush(&push_args);
    client.clearOutput();

    // Then pop the element
    const pop_args = [_]Value{
        .{ .data = "LPOP" },
        .{ .data = "mylist" },
    };
    try client.testLpop(&pop_args);

    try testing.expectEqualStrings("$5\r\nhello\r\n", client.getOutput());

    // List should be empty now
    const list = try store.getList("mylist");
    try testing.expect(list == null or list.?.len() == 0);
}

test "LPOP from non-existing list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "LPOP" },
        .{ .data = "nonexistent" },
    };

    try client.testLpop(&args);

    try testing.expectEqualStrings("$-1\r\n", client.getOutput());
}

test "LPOP with count from list with multiple elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create a list with multiple elements
    const push_args = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "three" },
        .{ .data = "two" },
        .{ .data = "one" },
    };
    try client.testLpush(&push_args);
    client.clearOutput();

    // Pop 2 elements
    const pop_args = [_]Value{
        .{ .data = "LPOP" },
        .{ .data = "mylist" },
        .{ .data = "2" },
    };
    try client.testLpop(&pop_args);

    // Should return an array with 2 elements
    try testing.expectEqualStrings("*2\r\n$3\r\none\r\n$3\r\ntwo\r\n", client.getOutput());

    // List should have 1 element left
    const list = try store.getList("mylist");
    try testing.expect(list != null);
    try testing.expectEqual(@as(usize, 1), list.?.len());
}

test "LPOP with count of 0" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create a list with elements
    const push_args = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "hello" },
    };
    try client.testLpush(&push_args);
    client.clearOutput();

    // Pop 0 elements
    const pop_args = [_]Value{
        .{ .data = "LPOP" },
        .{ .data = "mylist" },
        .{ .data = "0" },
    };
    try client.testLpop(&pop_args);

    try testing.expectEqualStrings("$-1\r\n", client.getOutput());
}

// RPOP Tests
test "RPOP from list with single element" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // First create a list with one element
    const push_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "hello" },
    };
    try client.testRpush(&push_args);
    client.clearOutput();

    // Then pop the element
    const pop_args = [_]Value{
        .{ .data = "RPOP" },
        .{ .data = "mylist" },
    };
    try client.testRpop(&pop_args);

    try testing.expectEqualStrings("$5\r\nhello\r\n", client.getOutput());
}

test "RPOP with count from list with multiple elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create a list with multiple elements
    const push_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
        .{ .data = "two" },
        .{ .data = "three" },
    };
    try client.testRpush(&push_args);
    client.clearOutput();

    // Pop 2 elements from the right
    const pop_args = [_]Value{
        .{ .data = "RPOP" },
        .{ .data = "mylist" },
        .{ .data = "2" },
    };
    try client.testRpop(&pop_args);

    // Should return an array with 2 elements (in reverse order from LPOP)
    try testing.expectEqualStrings("*2\r\n$5\r\nthree\r\n$3\r\ntwo\r\n", client.getOutput());

    // List should have 1 element left
    const list = try store.getList("mylist");
    try testing.expect(list != null);
    try testing.expectEqual(@as(usize, 1), list.?.len());
}

// LLEN Tests
test "LLEN on existing list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create a list with elements
    const push_args = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
        .{ .data = "two" },
        .{ .data = "three" },
    };
    try client.testLpush(&push_args);
    client.clearOutput();

    // Check length
    const llen_args = [_]Value{
        .{ .data = "LLEN" },
        .{ .data = "mylist" },
    };
    try client.testLlen(&llen_args);

    try testing.expectEqualStrings(":3\r\n", client.getOutput());
}

test "LLEN on non-existing list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "LLEN" },
        .{ .data = "nonexistent" },
    };

    try client.testLlen(&args);

    try testing.expectEqualStrings(":0\r\n", client.getOutput());
}

test "LLEN on empty list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create a list and then pop all elements
    const push_args = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "temp" },
    };
    try client.testLpush(&push_args);

    const pop_args = [_]Value{
        .{ .data = "LPOP" },
        .{ .data = "mylist" },
    };
    try client.testLpop(&pop_args);
    client.clearOutput();

    // Check length of now-empty list
    const llen_args = [_]Value{
        .{ .data = "LLEN" },
        .{ .data = "mylist" },
    };
    try client.testLlen(&llen_args);

    try testing.expectEqualStrings(":0\r\n", client.getOutput());
}

// Integration Tests
test "Mixed LPUSH and RPUSH operations" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // LPUSH "middle"
    const lpush_args = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "middle" },
    };
    try client.testLpush(&lpush_args);
    client.clearOutput();

    // LPUSH "left"
    const lpush_args2 = [_]Value{
        .{ .data = "LPUSH" },
        .{ .data = "mylist" },
        .{ .data = "left" },
    };
    try client.testLpush(&lpush_args2);
    client.clearOutput();

    // RPUSH "right"
    const rpush_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "right" },
    };
    try client.testRpush(&rpush_args);
    client.clearOutput();

    // Should have 3 elements in order: left, middle, right
    const llen_args = [_]Value{
        .{ .data = "LLEN" },
        .{ .data = "mylist" },
    };
    try client.testLlen(&llen_args);

    try testing.expectEqualStrings(":3\r\n", client.getOutput());
}

test "LPOP and RPOP from the same list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create list with: one, two, three
    const push_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
        .{ .data = "two" },
        .{ .data = "three" },
    };
    try client.testRpush(&push_args);
    client.clearOutput();

    // LPOP should get "one"
    const lpop_args = [_]Value{
        .{ .data = "LPOP" },
        .{ .data = "mylist" },
    };
    try client.testLpop(&lpop_args);
    try testing.expectEqualStrings("$3\r\none\r\n", client.getOutput());
    client.clearOutput();

    // RPOP should get "three"
    const rpop_args = [_]Value{
        .{ .data = "RPOP" },
        .{ .data = "mylist" },
    };
    try client.testRpop(&rpop_args);
    try testing.expectEqualStrings("$5\r\nthree\r\n", client.getOutput());
    client.clearOutput();

    // Should have 1 element left ("two")
    const llen_args = [_]Value{
        .{ .data = "LLEN" },
        .{ .data = "mylist" },
    };
    try client.testLlen(&llen_args);
    try testing.expectEqualStrings(":1\r\n", client.getOutput());
}
