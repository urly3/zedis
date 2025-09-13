const std = @import("std");

pub const ValueType = enum {
    string,
    int,
    // list,

    pub fn toRdbOpcode(self: ValueType) u8 {
        const RDB_TYPE_STRING = 0x00;
        // const RDB_TYPE_LIST = 0x01;

        return switch (self) {
            .string => RDB_TYPE_STRING,
            .int => RDB_TYPE_STRING,
            // .list => RDB_TYPE_LIST,
        };
    }
};

pub const ZedisValue = union(ValueType) {
    string: []u8,
    int: i64,
    // list: std.array_list,
};

pub const ZedisObject = struct { valueType: ValueType, value: ZedisValue, expiry: ?u64 = null };

pub const Store = struct {
    allocator: std.mem.Allocator,
    // The HashMap stores string keys and string values.
    // We need to own the keys and values, so we allocate them.
    map: std.StringHashMap(ZedisObject),
    // A mutex is crucial for preventing race conditions when multiple
    // clients try to access the store at the same time.
    mutex: std.Thread.RwLock,

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
            // Only free string values since integers don't need freeing
            switch (entry.value_ptr.*.value) {
                .string => |str| self.allocator.free(str),
                .int => {},
            }
        }
        self.map.deinit();
    }

    pub fn size(self: Store) u32 {
        return self.map.count();
    }

    // Sets a key-value pair with a string value. It acquires a lock to ensure thread safety.
    pub fn set(self: *Store, key: []const u8, value: []const u8) !void {
        const zedis_object = ZedisObject{ .valueType = .string, .value = .{ .string = undefined } };
        try self.setObject(key, zedis_object, value);
    }

    // Sets a key-value pair with a ZedisObject. It acquires a lock to ensure thread safety.
    pub fn setObject(self: *Store, key: []const u8, object: ZedisObject, string_data: ?[]const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.setObjectUnsafe(key, object, string_data);
    }

    // Sets a key with an integer value
    pub fn setInt(self: *Store, key: []const u8, value: i64) !void {
        const zedis_object = ZedisObject{ .valueType = .int, .value = .{ .int = value } };
        try self.setObject(key, zedis_object, null);
    }

    // Internal unsafe version that doesn't acquire locks (for use when already locked)
    pub fn setObjectUnsafe(self: *Store, key: []const u8, object: ZedisObject, string_data: ?[]const u8) !void {
        // Check if key already exists and free old memory
        var key_exists = false;
        if (self.map.getPtr(key)) |existing_entry| {
            key_exists = true;
            // Free the old value if it's a string
            switch (existing_entry.value) {
                .string => |str| self.allocator.free(str),
                .int => {},
            }
        }

        // If key doesn't exist, we need to allocate memory for the key
        if (!key_exists) {
            const key_copy = try self.allocator.dupe(u8, key);
            errdefer self.allocator.free(key_copy);

            // Pre-allocate the entry in the map
            try self.map.put(key_copy, undefined);
        }

        // Now we know the key exists in the map, get a pointer to modify it
        const entry_ptr = self.map.getPtr(key).?;

        // Set up the new object
        var new_object = object;
        switch (object.valueType) {
            .string => {
                if (string_data) |data| {
                    // Allocate and copy string data
                    const value_copy = try self.allocator.dupe(u8, data);
                    errdefer self.allocator.free(value_copy);
                    new_object.value = .{ .string = value_copy };
                } else {
                    return error.MissingStringData;
                }
            },
            .int => {
                // Integer values don't need allocation
                new_object.value = object.value;
            },
        }

        // Update the entry
        entry_ptr.* = new_object;
    }

    // Delete a key from the store
    pub fn delete(self: *Store, key: []const u8) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.map.fetchRemove(key)) |kv| {
            // Free the key
            self.allocator.free(kv.key);
            // Free the value if it's a string
            switch (kv.value.value) {
                .string => |str| self.allocator.free(str),
                .int => {},
            }
            return true;
        }
        return false;
    }

    // Check if a key exists
    pub fn exists(self: *Store, key: []const u8) bool {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();
        return self.map.contains(key);
    }

    // Get the type of a value
    pub fn getType(self: *Store, key: []const u8) ?ValueType {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        if (self.map.get(key)) |obj| {
            return obj.valueType;
        }
        return null;
    }

    // Gets a value by its key. It also acquires a lock.
    pub fn get(self: *Store, key: []const u8) ?ZedisObject {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        if (self.map.get(key)) |obj| {
            return obj;
        } else {
            return null;
        }
    }

    // Gets a copy of the string value for thread safety
    pub fn getString(self: *Store, allocator: std.mem.Allocator, key: []const u8) !?[]u8 {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        if (self.map.get(key)) |obj| {
            switch (obj.value) {
                .string => |str| return try allocator.dupe(u8, str),
                .int => |i| return try std.fmt.allocPrint(allocator, "{d}", .{i}),
            }
        }
        return null;
    }

    // Gets an integer value, converting from string if necessary
    pub fn getInt(self: *Store, key: []const u8) !?i64 {
        self.mutex.lockShared();
        defer self.mutex.unlockShared();

        if (self.map.get(key)) |obj| {
            switch (obj.value) {
                .int => |i| return i,
                .string => |str| {
                    return std.fmt.parseInt(i64, str, 10) catch error.NotAnInteger;
                },
            }
        }
        return null;
    }
};
