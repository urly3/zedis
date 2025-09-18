const std = @import("std");
const Connection = std.net.Server.Connection;
const Allocator = std.mem.Allocator;
const time = std.time;
const Store = @import("store.zig").Store;
const CommandRegistry = @import("./commands/registry.zig").CommandRegistry;
const server_config = @import("server_config.zig");
const KeyValueAllocator = @import("kv_allocator.zig").KeyValueAllocator;

pub const ConnectionContext = struct {
    server_impl: *anyopaque, // Points to Server to avoid circular dependency
    connection: std.net.Server.Connection,
};


