const std = @import("std");

// pub const ValueType = enum { string, int };
pub const ZedisObject = struct { valueType: type, value: []u8 };

pub const Store = struct {
    allocator: std.mem.Allocator,
    // The HashMap stores string keys and string values.
    // We need to own the keys and values, so we allocate them.
    map: std.StringHashMap(ZedisObject),
    // A mutex is crucial for preventing race conditions when multiple
    // clients try to access the store at the same time.
    mutex: std.Thread.Mutex,

    // Initializes the store.
    pub fn init(allocator: std.mem.Allocator) Store {
        return .{
            .allocator = allocator,
            .map = std.StringHashMap(ZedisObject).init(allocator),
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

        const zedisObject = ZedisObject{ .valueType = .string, .value = value_copy };
        try self.map.put(key_copy, zedisObject);
    }

    // Gets a value by its key. It also acquires a lock.
    pub fn get(self: *Store, key: []const u8) ?[]const u8 {
        if (self.map.get(key)) |obj| {
            return obj.value;
        } else {
            return null;
        }
    }
};
