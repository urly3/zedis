const std = @import("std");
const Allocator = std.mem.Allocator;
const Connection = std.net.Server.Connection;
const time = std.time;
const types = @import("types.zig");
const ConnectionContext = types.ConnectionContext;
const Client = @import("client.zig").Client;
const CommandRegistry = @import("./commands/registry.zig").CommandRegistry;
const connection_commands = @import("./commands/connection.zig");
const Reader = @import("./rdb/zdb.zig").Reader;
const Store = @import("store.zig").Store;
const string = @import("./commands/string.zig");
const rdb = @import("./commands/rdb.zig");
const zedis_types = @import("./zedis_types.zig");
const PubSubChannelMap = zedis_types.PubSubChannelMap;
const pubsub = @import("./pubsub/pubsub.zig");
const PubSubContext = pubsub.PubSubContext;
const server_config = @import("server_config.zig");
const KeyValueAllocator = @import("kv_allocator.zig").KeyValueAllocator;
const ExpirationJob = @import("./jobs/expiration.zig");

pub const Server = struct {
    // Configuration
    config: server_config.ServerConfig,

    // Base allocator (only for server initialization)
    base_allocator: std.mem.Allocator,

    // Network
    address: std.net.Address,
    listener: std.net.Server,

    // Fixed allocations (pre-allocated, never freed individually)
    client_pool: []Client,
    client_pool_bitmap: std.bit_set.IntegerBitSet(server_config.MAX_CLIENTS),

    // Map of channel_name -> array of client_id
    pubsub_map: std.StringHashMap([]u64),

    // Arena for temporary/short-lived allocations
    temp_arena: std.heap.ArenaAllocator,

    // Custom allocator for key-value store with eviction
    kv_allocator: KeyValueAllocator,
    store: Store,
    registry: CommandRegistry,
    pubsub_context: PubSubContext,

    // Metadata
    redisVersion: ?[]u8 = undefined,
    createdTime: i64,

    // Initializes the server with hybrid allocation strategy
    pub fn init(base_allocator: Allocator, host: []const u8, port: u16) !Server {
        return initWithConfig(base_allocator, host, port, server_config.ServerConfig{});
    }

    pub fn initWithConfig(base_allocator: Allocator, host: []const u8, port: u16, config: server_config.ServerConfig) !Server {
        const address = try std.net.Address.parseIp(host, port);
        const listener = try address.listen(.{
            .reuse_address = true,
        });

        // Initialize the KV allocator with eviction support
        var kv_allocator = try KeyValueAllocator.init(base_allocator, config.kv_memory_budget, config.eviction_policy);

        // Initialize store with the KV allocator
        const store = Store.init(kv_allocator.allocator());

        // Initialize command registry with temp arena (will be allocated)
        var temp_arena = std.heap.ArenaAllocator.init(base_allocator);
        const registry = try Server.initRegistry(temp_arena.allocator());

        // Allocate fixed memory pools on heap
        const client_pool = try base_allocator.alloc(Client, server_config.MAX_CLIENTS);
        @memset(client_pool, undefined);

        var server = Server{
            .config = config,
            .base_allocator = base_allocator,
            .address = address,
            .listener = listener,
            .pubsub_map = std.StringHashMap([]u64).init(base_allocator),

            // Fixed allocations - heap allocated
            .client_pool = client_pool,
            .client_pool_bitmap = std.bit_set.IntegerBitSet(server_config.MAX_CLIENTS).initFull(), // All slots initially free

            // Arena for temporary allocations
            .temp_arena = temp_arena,

            // KV allocator and store
            .kv_allocator = kv_allocator,
            .store = store,
            .registry = registry,
            .pubsub_context = undefined, // Will be initialized after server creation

            // Metadata
            .redisVersion = undefined,
            .createdTime = time.timestamp(),
        };

        server.pubsub_context = PubSubContext.init(&server);

        // Load RDB file if it exists
        const file_exists = Reader.rdbFileExists();
        if (file_exists) {
            const reader = try Reader.init(server.temp_arena.allocator(), @constCast(&server.store));
            errdefer reader.deinit();
            defer reader.deinit();

            if (reader.readFile()) |data| {
                std.log.debug("Loading RDB", .{});
                server.createdTime = data.ctime;
            } else |err| {
                std.log.err("Failed to load rdb: {s}", .{@errorName(err)});
            }
        }

        std.log.debug("Fixed Mem {any}", .{server_config.FIXED_MEMORY_SIZE});

        std.log.info("Server initialized with hybrid allocation - Fixed: {}MB, KV: {}MB, Arena: {}MB", .{
            server_config.FIXED_MEMORY_SIZE / (1024 * 1024),
            config.kv_memory_budget / (1024 * 1024),
            config.temp_arena_size / (1024 * 1024),
        });

        return server;
    }

    pub fn startBackgroundJobs(self: *Server) !void {
        // Start threads running background jobs
        try ExpirationJob.startExpirationJob(&self.store);
    }

    pub fn deinit(self: *Server) void {
        // Network cleanup
        self.listener.deinit();

        // Store cleanup (uses KV allocator)
        self.store.deinit();

        // Registry cleanup (uses temp arena)
        self.registry.deinit();

        // Clean up pubsub map
        var iterator = self.pubsub_map.iterator();
        while (iterator.next()) |entry| {
            self.base_allocator.free(entry.value_ptr.*);
        }
        self.pubsub_map.deinit();

        // Free heap allocated fixed memory pools
        self.base_allocator.free(self.client_pool);

        // Allocator cleanup
        self.kv_allocator.deinit();
        self.temp_arena.deinit();

        std.log.info("Server deinitialized - all memory freed", .{});
    }

    pub fn initRegistry(allocator: Allocator) !CommandRegistry {
        var registry = CommandRegistry.init(allocator);

        try registry.register(.{
            .name = "PING",
            .handler = connection_commands.ping,
            .min_args = 1,
            .max_args = 2,
            .description = "Ping the server",
        });

        try registry.register(.{
            .name = "ECHO",
            .handler = connection_commands.echo,
            .min_args = 2,
            .max_args = 2,
            .description = "Echo the given string",
        });

        try registry.register(.{
            .name = "QUIT",
            .handler = connection_commands.quit,
            .min_args = 1,
            .max_args = 1,
            .description = "Close the connection",
        });

        try registry.register(.{
            .name = "SET",
            .handler = string.set,
            .min_args = 3,
            .max_args = 3,
            .description = "Set string value of a key",
        });

        try registry.register(.{
            .name = "GET",
            .handler = string.get,
            .min_args = 2,
            .max_args = 2,
            .description = "Get string value of a key",
        });

        try registry.register(.{
            .name = "INCR",
            .handler = string.incr,
            .min_args = 2,
            .max_args = 2,
            .description = "Increment the value of a key",
        });

        try registry.register(.{
            .name = "DECR",
            .handler = string.decr,
            .min_args = 2,
            .max_args = 2,
            .description = "Decrement the value of a key",
        });

        try registry.register(.{
            .name = "HELP",
            .handler = connection_commands.help,
            .min_args = 1,
            .max_args = 1,
            .description = "Show help message",
        });

        try registry.register(.{
            .name = "DEL",
            .handler = string.del,
            .min_args = 2,
            .max_args = null,
            .description = "Delete key",
        });

        try registry.register(.{
            .name = "SAVE",
            .handler = rdb.save,
            .min_args = 1,
            .max_args = 1,
            .description = "The SAVE commands performs a synchronous save of the dataset producing a point in time snapshot of all the data inside the Redis instance, in the form of an RDB file.",
        });

        try registry.register(.{
            .name = "PUBLISH",
            .handler = pubsub.publish,
            .min_args = 3,
            .max_args = 3,
            .description = "Publish message",
        });

        try registry.register(.{
            .name = "SUBSCRIBE",
            .handler = pubsub.subscribe,
            .min_args = 2,
            .max_args = null,
            .description = "Subscribe to channels",
        });

        try registry.register(.{
            .name = "EXPIRE",
            .handler = string.expire,
            .min_args = 3,
            .max_args = null,
            .description = "Expire key",
        });

        return registry;
    }

    // The main server loop. It waits for incoming connections and
    // spawns a new thread pool task to handle each client.
    pub fn listen(self: *Server) !void {
        while (true) {
            const conn = self.listener.accept() catch |err| {
                std.log.err("Error accepting connection: {s}", .{@errorName(err)});
                continue;
            };

            const context = self.temp_arena.allocator().create(ConnectionContext) catch |err| {
                std.log.err("Failed to allocate connection context: {s}", .{@errorName(err)});
                conn.stream.close();
                continue;
            };

            context.* = ConnectionContext{
                .server = self,
                .connection = conn,
            };

            const thread = std.Thread.spawn(.{}, handleConnectionWrapper, .{context}) catch |err| {
                std.log.err("Failed to spawn thread for connection: {s}", .{@errorName(err)});
                // Context will be cleaned up with arena reset
                conn.stream.close();
                continue;
            };
            thread.detach();
        }
    }

    fn handleConnectionWrapper(context: *ConnectionContext) void {
        context.server.handleConnection(context.connection) catch |err| {
            std.log.err("Error handling connection: {s}", .{@errorName(err)});
        };
    }

    fn handleConnection(self: *Server, conn: std.net.Server.Connection) !void {
        // Allocate client from fixed pool
        const client_slot = self.allocateClient() orelse {
            std.log.warn("Maximum client connections reached, rejecting connection", .{});
            conn.stream.close();
            return;
        };

        // Initialize client in the allocated slot
        client_slot.* = Client.init(
            self.temp_arena.allocator(),
            conn,
            &self.store,
            &self.registry,
            &self.pubsub_context,
        );

        defer {
            // Clean up client and return slot to pool
            // For pubsub clients that disconnected, clean them up from all channels first
            if (client_slot.is_in_pubsub_mode) {
                // Remove this client from all channels
                self.cleanupDisconnectedPubSubClient(client_slot.client_id);
                std.log.debug("Client {} removed from all channels and deallocated", .{client_slot.client_id});
            }

            // Always clean up and deallocate when connection ends
            client_slot.deinit();
            self.deallocateClient(client_slot);
            std.log.debug("Client {} deallocated from pool", .{client_slot.client_id});
        }

        // log how long it took to handle the client
        const start_time = std.time.nanoTimestamp();
        try client_slot.handle();
        const end_time = std.time.nanoTimestamp();
        const runtime = std.math.divCeil(i128, (end_time - start_time), 1_000_000);
        std.log.info("Client {} handled in {any} ms", .{ client_slot.client_id, runtime });
    }

    // Client pool management methods
    pub fn allocateClient(self: *Server) ?*Client {
        const first_free = self.client_pool_bitmap.findFirstSet() orelse return null;
        self.client_pool_bitmap.unset(first_free);
        return &self.client_pool[first_free];
    }

    pub fn deallocateClient(self: *Server, client: *Client) void {
        // Find the client index in the pool
        const pool_ptr = @intFromPtr(&self.client_pool[0]);
        const client_ptr = @intFromPtr(client);
        const client_size = @sizeOf(Client);

        if (client_ptr >= pool_ptr and client_ptr < pool_ptr + (server_config.MAX_CLIENTS * client_size)) {
            const index = (client_ptr - pool_ptr) / client_size;
            self.client_pool_bitmap.set(index);
        }
    }

    // Pub/sub HashMap management methods
    pub fn ensureChannelExists(self: *Server, channel_name: []const u8) !void {
        // Check if channel already exists
        if (self.pubsub_map.contains(channel_name)) {
            return;
        }

        // Create new empty subscriber list for this channel
        const subscribers = try self.base_allocator.alloc(u64, 0);
        try self.pubsub_map.put(channel_name, subscribers);
    }

    pub fn subscribeToChannel(self: *Server, channel_name: []const u8, client_id: u64) !void {
        // Ensure channel exists
        try self.ensureChannelExists(channel_name);

        // Get current subscribers
        const current_subscribers = self.pubsub_map.get(channel_name).?;

        // Check if client is already subscribed
        for (current_subscribers) |existing_id| {
            if (existing_id == client_id) {
                return; // Already subscribed, no-op
            }
        }

        // Check limit
        if (current_subscribers.len >= server_config.MAX_SUBSCRIBERS_PER_CHANNEL) {
            return error.ChannelFull;
        }

        // Add client to channel by reallocating the slice
        const new_subscribers = try self.base_allocator.realloc(current_subscribers, current_subscribers.len + 1);
        new_subscribers[new_subscribers.len - 1] = client_id;
        try self.pubsub_map.put(channel_name, new_subscribers);
    }

    pub fn unsubscribeFromChannel(self: *Server, channel_name: []const u8, client_id: u64) !void {
        // Get current subscribers
        const current_subscribers = self.pubsub_map.get(channel_name) orelse return;

        // Find the client in the subscribers list
        for (current_subscribers, 0..) |existing_id, i| {
            if (existing_id == client_id) {
                // Create new slice without this client
                const new_subscribers = try self.base_allocator.alloc(u64, current_subscribers.len - 1);

                // Copy elements before the removed one
                @memcpy(new_subscribers[0..i], current_subscribers[0..i]);

                // Copy elements after the removed one
                if (i < current_subscribers.len - 1) {
                    @memcpy(new_subscribers[i..], current_subscribers[i + 1 ..]);
                }

                // Free old slice and update map
                self.base_allocator.free(current_subscribers);

                if (new_subscribers.len == 0) {
                    // Remove channel entirely if no subscribers
                    _ = self.pubsub_map.remove(channel_name);
                    self.base_allocator.free(new_subscribers);
                } else {
                    try self.pubsub_map.put(channel_name, new_subscribers);
                }
                return;
            }
        }
    }

    // Clean up a disconnected pubsub client from all channels
    pub fn cleanupDisconnectedPubSubClient(self: *Server, client_id: u64) void {
        // Iterate through all channels and remove this client
        var channel_iterator = self.pubsub_map.iterator();
        while (channel_iterator.next()) |entry| {
            const channel_name = entry.key_ptr.*;
            self.unsubscribeFromChannel(channel_name, client_id) catch |err| {
                std.log.warn("Failed to unsubscribe client {} from channel {s}: {s}", .{ client_id, channel_name, @errorName(err) });
            };
        }
    }

    // Memory statistics
    pub fn getMemoryStats(self: *Server) server_config.MemoryStats {
        return server_config.MemoryStats{
            .fixed_memory_used = server_config.FIXED_MEMORY_SIZE,
            .kv_memory_used = self.kv_allocator.getMemoryUsage(),
            .temp_arena_used = self.temp_arena.queryCapacity() - self.temp_arena.state.buffer_list.first.?.data.len,
            .total_allocated = server_config.FIXED_MEMORY_SIZE + self.kv_allocator.getMemoryUsage() +
                (self.temp_arena.queryCapacity() - self.temp_arena.state.buffer_list.first.?.data.len),
            .total_budget = server_config.TOTAL_MEMORY_BUDGET,
        };
    }
    pub fn getChannelSubscribers(self: *Server, channel_name: []const u8) []const u64 {
        return self.pubsub_map.get(channel_name) orelse &[_]u64{};
    }

    pub fn getChannelCount(self: *Server) u32 {
        return @intCast(self.pubsub_map.count());
    }

    pub fn getChannelNames(self: *Server) std.StringHashMap([]u64).KeyIterator {
        return self.pubsub_map.keyIterator();
    }

    pub fn findClientById(self: *Server, client_id: u64) ?*Client {
        for (self.client_pool, 0..) |*client, index| {
            // if (!self.client_pool_bitmap.isSet(index) and client.client_id == client_id) {
            //     if (client.client_id == client_id) {
            //         return client;
            //     }
            // }

            _ = index;
            if (client.client_id == client_id) {
                if (client.client_id == client_id) {
                    return client;
                }
            }
        }
        return null;
    }
};
