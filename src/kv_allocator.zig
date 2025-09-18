const std = @import("std");
const server_config = @import("server_config.zig");

pub const KeyValueAllocator = struct {
    base_allocator: std.mem.Allocator,
    memory_pool: []u8,
    pool_allocator: std.heap.FixedBufferAllocator,
    memory_used: std.atomic.Value(usize),
    memory_budget: usize,
    eviction_policy: server_config.ServerConfig.EvictionPolicy,

    // LRU tracking
    access_counter: std.atomic.Value(u64),

    const Self = @This();

    pub fn init(base_allocator: std.mem.Allocator, budget: usize, eviction_policy: server_config.ServerConfig.EvictionPolicy) !Self {
        const memory_pool = try base_allocator.alloc(u8, budget);

        return Self{
            .base_allocator = base_allocator,
            .memory_pool = memory_pool,
            .pool_allocator = std.heap.FixedBufferAllocator.init(memory_pool),
            .memory_used = std.atomic.Value(usize).init(0),
            .memory_budget = budget,
            .eviction_policy = eviction_policy,
            .access_counter = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base_allocator.free(self.memory_pool);
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = std.mem.Allocator.noRemap,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        // Try allocation first
        if (self.pool_allocator.allocator().rawAlloc(len, ptr_align, ret_addr)) |ptr| {
            _ = self.memory_used.fetchAdd(len, .monotonic);
            return ptr;
        }

        // If allocation failed and we have eviction policy, try to make space
        if (self.eviction_policy != .noeviction) {
            self.evictMemory(len);
            // Try allocation again after eviction
            if (self.pool_allocator.allocator().rawAlloc(len, ptr_align, ret_addr)) |ptr| {
                _ = self.memory_used.fetchAdd(len, .monotonic);
                return ptr;
            }
        }

        return null;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        if (self.pool_allocator.allocator().rawResize(buf, buf_align, new_len, ret_addr)) {
            const old_len = buf.len;
            if (new_len > old_len) {
                _ = self.memory_used.fetchAdd(new_len - old_len, .monotonic);
            } else {
                _ = self.memory_used.fetchSub(old_len - new_len, .monotonic);
            }
            return true;
        }
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.pool_allocator.allocator().rawFree(buf, buf_align, ret_addr);
        _ = self.memory_used.fetchSub(buf.len, .monotonic);
    }

    fn evictMemory(self: *Self, needed_bytes: usize) void {
        // Simple eviction strategy: reset the entire pool
        // In a real implementation, you'd implement proper LRU eviction
        // by tracking individual allocations and their access times

        switch (self.eviction_policy) {
            .noeviction => return,
            .allkeys_lru, .volatile_lru => {
                // For now, just reset the pool if we need space
                // This is a simplified implementation
                const current_used = self.memory_used.load(.acquire);
                if (current_used + needed_bytes > self.memory_budget) {
                    self.pool_allocator.reset();
                    self.memory_used.store(0, .release);
                    std.log.warn("KV allocator: Evicted all keys due to memory pressure", .{});
                }
            },
        }
    }

    pub fn getMemoryUsage(self: *Self) usize {
        return self.memory_used.load(.acquire);
    }

    pub fn getMemoryBudget(self: *Self) usize {
        return self.memory_budget;
    }

    pub fn resetPool(self: *Self) void {
        self.pool_allocator.reset();
        self.memory_used.store(0, .release);
    }
};
