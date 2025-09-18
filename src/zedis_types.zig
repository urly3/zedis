const std = @import("std");
const Connection = std.net.Server.Connection;
const Client = @import("./client.zig");

pub const PubSubChannelMap = std.AutoHashMap([]const u8, std.ArrayList(*Client));
