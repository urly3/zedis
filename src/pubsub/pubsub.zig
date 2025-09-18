const std = @import("std");
const Client = @import("../client.zig").Client;
const store = @import("../store.zig");
const ZedisValue = store.ZedisValue;
const Value = @import("../parser.zig").Value;

pub fn subscribe(client: *Client, args: []const Value) !void {
    var i: i64 = 0;
    for (args[1..]) |item| {
        const channel_name = item.asSlice();

        // Find or create channel in the server's fixed matrix
        const channel_id = client.findOrCreateChannel(channel_name) orelse {
            try client.writeError("ERR maximum number of channels reached");
            continue;
        };

        // Subscribe client to channel
        client.subscribeToChannel(channel_id, client.client_id) catch |err| switch (err) {
            error.ChannelFull => {
                try client.writeError("ERR maximum subscribers per channel reached");
                continue;
            },
            error.InvalidChannel => {
                try client.writeError("ERR invalid channel");
                continue;
            },
        };

        const subscription_count = i + 1;

        const response_tuple = .{
            "subscribe",
            channel_name,
            subscription_count,
        };

        // Use a generic writer to send the tuple as a RESP array.
        try client.writeTupleAsArray(response_tuple);
        i += 1;
    }
}

pub fn publish(client: *Client, args: []const Value) !void {
    const channel_name = args[1].asSlice();
    _ = args[2].asSlice(); // value - unused due to circular dependency fix
    const messages_sent: i64 = 0; // Temporarily hardcoded due to circular dependency

    // Find channel in server's matrix
    var channel_id: ?u32 = null;
    for (client.getChannelNames(), 0..) |existing_name, i| {
        if (existing_name) |name| {
            if (std.mem.eql(u8, name, channel_name)) {
                channel_id = @intCast(i);
                break;
            }
        }
    }

    if (channel_id) |cid| {
        const subscribers = client.getChannelSubscribers(cid);
        var i: u32 = 0;
        while (i < subscribers.len) {
            const client_id = subscribers[i];
            _ = client_id; // Avoid unused variable warning

            // TODO: Implement proper publish functionality after resolving circular dependency
            // For now, just skip to avoid build issues

            i += 1;
        }
    }

    try client.writeInt(messages_sent);
}
