const std = @import("std");
const store = @import("../store.zig");
const Store = store.Store;
const ZedisObject = store.ZedisObject;

pub fn incrDecr(self: *Store, key: []const u8, comptime value: u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const current_value = self.map.get(key);
    if (current_value) |v| {
        if (v.valueType == .int or v.valueType == .string) {
            const intValue = try std.fmt.parseInt(u64, v.value, 10);
            const new_value = try std.math.add(u64, intValue, value);
            const updatedZedisObject = ZedisObject{ .valueType = .int, .value = new_value };
            try self.map.put(key, updatedZedisObject);
        }
    } else {
        const newObj = ZedisObject{ .valueType = .int, .value = 1 };
        try self.map.put(key, newObj);
    }
}
