const std = @import("std");
const Client = @import("./client.zig").Client;

// Server memory configuration constants
pub const MAX_CLIENTS = 100; // Reduced for testing: support 100 concurrent clients
pub const MAX_CHANNELS = 100; // Reduced for testing: support 100 pub/sub channels
pub const MAX_SUBSCRIBERS_PER_CHANNEL = 10; // Reduced for testing: 10 subscribers per channel

// Memory budgets (in bytes)
pub const KV_MEMORY_BUDGET = 8 * 1024 * 1024 * 1024; // 8GB for key-value store
pub const TEMP_ARENA_SIZE = 512 * 1024 * 1024; // 512MB for temporary allocations
pub const CLIENT_POOL_SIZE = MAX_CLIENTS * @sizeOf(Client);
pub const PUBSUB_MATRIX_SIZE = MAX_CHANNELS * MAX_SUBSCRIBERS_PER_CHANNEL * @sizeOf(u64);

// Total fixed memory calculation
pub const FIXED_MEMORY_SIZE = CLIENT_POOL_SIZE + PUBSUB_MATRIX_SIZE;
pub const TOTAL_MEMORY_BUDGET = FIXED_MEMORY_SIZE + KV_MEMORY_BUDGET + TEMP_ARENA_SIZE;

pub const ServerConfig = struct {
    max_clients: u32 = MAX_CLIENTS,
    max_channels: u32 = MAX_CHANNELS,
    max_subscribers_per_channel: u32 = MAX_SUBSCRIBERS_PER_CHANNEL,
    kv_memory_budget: usize = KV_MEMORY_BUDGET,
    temp_arena_size: usize = TEMP_ARENA_SIZE,
    eviction_policy: EvictionPolicy = .allkeys_lru,

    pub const EvictionPolicy = enum {
        noeviction, // Return errors when memory limit reached
        allkeys_lru, // Evict least recently used keys
        volatile_lru, // Evict LRU keys with expire set
    };
};

pub const MemoryStats = struct {
    fixed_memory_used: usize,
    kv_memory_used: usize,
    temp_arena_used: usize,
    total_allocated: usize,
    total_budget: usize,

    pub fn usagePercent(self: MemoryStats) u8 {
        return @intCast((self.total_allocated * 100) / self.total_budget);
    }
};
