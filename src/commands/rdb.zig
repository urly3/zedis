const std = @import("std");
const store = @import("../store.zig");
const Store = store.Store;
const ZedisObject = store.ZedisObject;
const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;
const ZDB_Writer = @import("../rdb/zdb_writer.zig").ZDB_Writer;

pub fn save(client: *Client, args: []const Value) !void {
    _ = args;

    var zdb = try ZDB_Writer.init(client.allocator, client.store, "test.rdb");
    defer zdb.deinit();
    try zdb.writeFile();

    try client.writeBulkString("OK");
}
