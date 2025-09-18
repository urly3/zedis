const Client = @import("../client.zig").Client;
const Value = @import("../parser.zig").Value;

// pub fn subscribe(client: *Client, args: []const Value) !void {}

pub fn publish(client: *Client, args: []const Value) !void {
    const channel = args[1].asSlice();
    const value = args[2].asSlice();

    if (client.pub_sub_channels.get(channel)) |clients| {
        for (clients.items) |client_ptr| {
            var subscribed_client = client_ptr.*;

            subscribed_client.writeBulkString(value);
        }
    }
}
