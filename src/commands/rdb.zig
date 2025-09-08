const std = @import("std");
const store = @import("../store.zig");
const Store = store.Store;
const ZedisObject = store.ZedisObject;
const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;
const ZDB = @import("../zdb.zig").ZDB;

pub fn save(client: *Client, args: []const Value) !void {
    _ = args;

    var zdb = try ZDB.init(client.allocator, client.store, "dump.rdb");
    defer zdb.deinit();
    try zdb.writeFile();

    try client.writeBulkString("OK");
}
