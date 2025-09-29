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

// LINDEX Tests
test "LINDEX get first element" {
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

    // Get first element (index 0)
    const lindex_args = [_]Value{
        .{ .data = "LINDEX" },
        .{ .data = "mylist" },
        .{ .data = "0" },
    };
    try client.testLindex(&lindex_args);

    try testing.expectEqualStrings("$3\r\none\r\n", client.getOutput());
}

test "LINDEX get last element with negative index" {
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

    // Get last element (index -1)
    const lindex_args = [_]Value{
        .{ .data = "LINDEX" },
        .{ .data = "mylist" },
        .{ .data = "-1" },
    };
    try client.testLindex(&lindex_args);

    try testing.expectEqualStrings("$5\r\nthree\r\n", client.getOutput());
}

test "LINDEX with out of range index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create list with: one
    const push_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
    };
    try client.testRpush(&push_args);
    client.clearOutput();

    // Try to get element at index 10
    const lindex_args = [_]Value{
        .{ .data = "LINDEX" },
        .{ .data = "mylist" },
        .{ .data = "10" },
    };
    try client.testLindex(&lindex_args);

    try testing.expectEqualStrings("$-1\r\n", client.getOutput());
}

test "LINDEX on non-existing list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "LINDEX" },
        .{ .data = "nonexistent" },
        .{ .data = "0" },
    };

    try client.testLindex(&args);

    try testing.expectEqualStrings("$-1\r\n", client.getOutput());
}

// LSET Tests
test "LSET update element at index" {
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

    // Set element at index 1 to "TWO"
    const lset_args = [_]Value{
        .{ .data = "LSET" },
        .{ .data = "mylist" },
        .{ .data = "1" },
        .{ .data = "TWO" },
    };
    try client.testLset(&lset_args);

    try testing.expectEqualStrings("$2\r\nOK\r\n", client.getOutput());
    client.clearOutput();

    // Verify the element was updated
    const lindex_args = [_]Value{
        .{ .data = "LINDEX" },
        .{ .data = "mylist" },
        .{ .data = "1" },
    };
    try client.testLindex(&lindex_args);

    try testing.expectEqualStrings("$3\r\nTWO\r\n", client.getOutput());
}

test "LSET with negative index" {
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

    // Set last element using -1
    const lset_args = [_]Value{
        .{ .data = "LSET" },
        .{ .data = "mylist" },
        .{ .data = "-1" },
        .{ .data = "THREE" },
    };
    try client.testLset(&lset_args);

    try testing.expectEqualStrings("$2\r\nOK\r\n", client.getOutput());
    client.clearOutput();

    // Verify the last element was updated
    const lindex_args = [_]Value{
        .{ .data = "LINDEX" },
        .{ .data = "mylist" },
        .{ .data = "-1" },
    };
    try client.testLindex(&lindex_args);

    try testing.expectEqualStrings("$5\r\nTHREE\r\n", client.getOutput());
}

test "LSET on non-existing key" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "LSET" },
        .{ .data = "nonexistent" },
        .{ .data = "0" },
        .{ .data = "value" },
    };

    try client.testLset(&args);

    try testing.expectEqualStrings("-ERR no such key\r\n", client.getOutput());
}

test "LSET with out of range index" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create list with: one
    const push_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
    };
    try client.testRpush(&push_args);
    client.clearOutput();

    // Try to set element at index 10
    const lset_args = [_]Value{
        .{ .data = "LSET" },
        .{ .data = "mylist" },
        .{ .data = "10" },
        .{ .data = "value" },
    };
    try client.testLset(&lset_args);

    try testing.expectEqualStrings("-ERR no such key\r\n", client.getOutput());
}

// LRANGE Tests
test "LRANGE get all elements" {
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

    // Get all elements (0 to -1)
    const lrange_args = [_]Value{
        .{ .data = "LRANGE" },
        .{ .data = "mylist" },
        .{ .data = "0" },
        .{ .data = "-1" },
    };
    try client.testLrange(&lrange_args);

    try testing.expectEqualStrings("*3\r\n$3\r\none\r\n$3\r\ntwo\r\n$5\r\nthree\r\n", client.getOutput());
}

test "LRANGE get subset of elements" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create list with: one, two, three, four, five
    const push_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
        .{ .data = "two" },
        .{ .data = "three" },
        .{ .data = "four" },
        .{ .data = "five" },
    };
    try client.testRpush(&push_args);
    client.clearOutput();

    // Get elements from index 1 to 3
    const lrange_args = [_]Value{
        .{ .data = "LRANGE" },
        .{ .data = "mylist" },
        .{ .data = "1" },
        .{ .data = "3" },
    };
    try client.testLrange(&lrange_args);

    try testing.expectEqualStrings("*3\r\n$3\r\ntwo\r\n$5\r\nthree\r\n$4\r\nfour\r\n", client.getOutput());
}

test "LRANGE with negative indices" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create list with: one, two, three, four, five
    const push_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
        .{ .data = "two" },
        .{ .data = "three" },
        .{ .data = "four" },
        .{ .data = "five" },
    };
    try client.testRpush(&push_args);
    client.clearOutput();

    // Get last 2 elements (-2 to -1)
    const lrange_args = [_]Value{
        .{ .data = "LRANGE" },
        .{ .data = "mylist" },
        .{ .data = "-2" },
        .{ .data = "-1" },
    };
    try client.testLrange(&lrange_args);

    try testing.expectEqualStrings("*2\r\n$4\r\nfour\r\n$4\r\nfive\r\n", client.getOutput());
}

test "LRANGE on non-existing list" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    const args = [_]Value{
        .{ .data = "LRANGE" },
        .{ .data = "nonexistent" },
        .{ .data = "0" },
        .{ .data = "-1" },
    };

    try client.testLrange(&args);

    try testing.expectEqualStrings("*0\r\n", client.getOutput());
}

test "LRANGE with out of range indices" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var store = Store.init(allocator);
    defer store.deinit();

    var client = MockClient.initLegacy(allocator, &store);
    defer client.deinit();

    // Create list with: one, two
    const push_args = [_]Value{
        .{ .data = "RPUSH" },
        .{ .data = "mylist" },
        .{ .data = "one" },
        .{ .data = "two" },
    };
    try client.testRpush(&push_args);
    client.clearOutput();

    // Try to get elements from 10 to 20 (out of range)
    const lrange_args = [_]Value{
        .{ .data = "LRANGE" },
        .{ .data = "mylist" },
        .{ .data = "10" },
        .{ .data = "20" },
    };
    try client.testLrange(&lrange_args);

    try testing.expectEqualStrings("*0\r\n", client.getOutput());
}

test "LRANGE with reversed range" {
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

    // Try reversed range (start > stop)
    const lrange_args = [_]Value{
        .{ .data = "LRANGE" },
        .{ .data = "mylist" },
        .{ .data = "2" },
        .{ .data = "1" },
    };
    try client.testLrange(&lrange_args);

    try testing.expectEqualStrings("*0\r\n", client.getOutput());
}
