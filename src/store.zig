const std = @import("std");

pub const Store = struct {
    allocator: std.mem.Allocator,
    // The HashMap stores string keys and string values.
    // We need to own the keys and values, so we allocate them.
    map: std.StringHashMap([]u8),
    // A mutex is crucial for preventing race conditions when multiple
    // clients try to access the store at the same time.
    mutex: std.Thread.Mutex,

    // Initializes the store.
    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap([]u8).init(allocator),
            .mutex = .{},
        };
    }

    // Frees all memory associated with the store.
    pub fn deinit(self: *Store) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    // Sets a key-value pair. It acquires a lock to ensure thread safety.
    pub fn set(self: *Store, key: []const u8, value: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // If the key already exists, we need to free the old value.
        if (self.map.get(key)) |old_value| {
            self.allocator.free(old_value);
        }

        // We must allocate new memory for the key and value because the
        // incoming slices might be temporary.
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        try self.map.put(key_copy, value_copy);
    }

    // Gets a value by its key. It also acquires a lock.
    pub fn get(self: *Store, key: []const u8) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.map.get(key);
    }
};
