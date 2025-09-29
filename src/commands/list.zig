const std = @import("std");
const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;
const PrimitiveValue = @import("../store.zig").PrimitiveValue;

pub fn lpush(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();

    const list = try client.store.getSetList(key);

    for (args[2..]) |arg| {
        try list.prepend(.{ .string = arg.asSlice() });
    }

    try client.writeInt(@intCast(list.len()));
}

pub fn rpush(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();

    const list = try client.store.getSetList(key);

    for (args[2..]) |arg| {
        try list.append(.{ .string = arg.asSlice() });
    }

    try client.writeInt(@intCast(list.len()));
}

pub fn lpop(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const list = try client.store.getList(key) orelse {
        try client.writeNull();
        return;
    };

    var count: usize = 1;

    if (args.len == 3) {
        count = try args[2].asUsize();
    }

    const list_len = list.len();
    const actual_count = @min(count, list_len);

    if (actual_count == 0) {
        try client.writeNull();
        return;
    }

    if (actual_count == 1) {
        const item = list.popFirst().?;
        switch (item) {
            .string => |str| try client.writeBulkString(str),
            .int => |i| try client.writeIntAsString(i),
        }
        return;
    }
    if (actual_count > 1) {
        try client.writeListLen(actual_count);
        for (0..actual_count) |_| {
            const item = list.popFirst().?;
            switch (item) {
                .string => |str| try client.writeBulkString(str),
                .int => |i| try client.writeIntAsString(i),
            }
        }
        return;
    }
}

pub fn llen(client: *Client, args: []const Value) !void {
    const key = args[1].asSlice();
    const list = try client.store.getList(key);

    if (list) |l| {
        try client.writeInt(@intCast(l.len()));
    } else {
        try client.writeInt(0);
    }
}
