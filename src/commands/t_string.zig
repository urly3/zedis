const std = @import("std");
const store = @import("../store.zig");
const Store = store.Store;
const ZedisObject = store.ZedisObject;

pub fn incrDecr(self: *Store, key: []const u8, value: i64) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const current_value = self.map.get(key);
    if (current_value) |v| {
        switch (v.valueType) {
            .string => |_| {
                const intValue = try std.fmt.parseInt(i64, v.value.string, 10);
                const new_value = try std.math.add(i64, intValue, value);
                const updatedZedisObject = ZedisObject{ .valueType = .int, .value = .{ .int = new_value } };
                try self.map.put(key, updatedZedisObject);
            },
            .int => |_| {
                const new_value = try std.math.add(i64, v.value.int, value);
                const updatedZedisObject = ZedisObject{ .valueType = .int, .value = .{ .int = new_value } };
                try self.map.put(key, updatedZedisObject);
            },
        }
    } else {
        std.debug.print("Key not found: {s}\n", .{key});
    }
}
