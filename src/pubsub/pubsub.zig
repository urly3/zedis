const std = @import("std");
const Client = @import("../client.zig").Client;
const store = @import("../store.zig");
const ZedisValue = store.ZedisValue;
const Value = @import("../parser.zig").Value;
const Server = @import("../server.zig").Server;

pub const PubSubContext = struct {
    server: *Server,

    pub fn init(server: *Server) PubSubContext {
        return PubSubContext{ .server = server };
    }

    pub fn findOrCreateChannel(self: *PubSubContext, channel_name: []const u8) ?u32 {
        return self.server.findOrCreateChannel(channel_name);
    }

    pub fn subscribeToChannel(self: *PubSubContext, channel_id: u32, client_id: u64) !void {
        return self.server.subscribeToChannel(channel_id, client_id);
    }

    pub fn unsubscribeFromChannel(self: *PubSubContext, channel_id: u32, client_id: u64) void {
        self.server.unsubscribeFromChannel(channel_id, client_id);
    }

    pub fn getChannelSubscribers(self: *PubSubContext, channel_id: u32) []const u64 {
        return self.server.getChannelSubscribers(channel_id);
    }

    pub fn getChannelNames(self: *PubSubContext) []const ?[]const u8 {
        return self.server.getChannelNames();
    }

    pub fn getChannelCount(self: *PubSubContext) u32 {
        return self.server.getChannelCount();
    }

    pub fn findClientById(self: *PubSubContext, client_id: u64) ?*Client {
        return self.server.findClientById(client_id);
    }
};

pub fn subscribe(client: *Client, args: []const Value) !void {
    var pubsub_context = client.pubsub_context;
    var i: i64 = 0;
    for (args[1..]) |item| {
        const channel_name = item.asSlice();
        // Find or create channel in the server's fixed matrix
        const channel_id = pubsub_context.findOrCreateChannel(channel_name) orelse {
            try client.writeError("ERR maximum number of channels reached");
            continue;
        };

        // Subscribe client to channel
        pubsub_context.subscribeToChannel(channel_id, client.client_id) catch |err| switch (err) {
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
    var pubsub_context = client.pubsub_context;
    const channel_name = args[1].asSlice();
    const message = args[2].asSlice();
    var messages_sent: i64 = 0;

    // Find channel in server's matrix
    var channel_id: ?u32 = null;
    for (pubsub_context.getChannelNames(), 0..) |existing_name, i| {
        if (existing_name) |name| {
            if (std.mem.eql(u8, name, channel_name)) {
                channel_id = @intCast(i);
                break;
            }
        }
    }

    if (channel_id) |cid| {
        const subscribers = pubsub_context.getChannelSubscribers(cid);
        for (subscribers) |subscriber_id| {
            // Find the subscriber client and deliver the message
            if (pubsub_context.findClientById(subscriber_id)) |subscriber_client| {
                const message_tuple = .{
                    "message",
                    channel_name,
                    message,
                };

                // Try to deliver the message, but don't fail the entire publish if one delivery fails
                subscriber_client.writeTupleAsArray(message_tuple) catch |err| {
                    std.log.warn("Failed to deliver message to client {}: {s}", .{ subscriber_id, @errorName(err) });
                    continue;
                };

                messages_sent += 1;
            }
        }
    }

    try client.writeInt(messages_sent);
}
