const std = @import("std");
const Store = @import("../store.zig").Store;

// 1 Second
const interval = std.time.ns_per_s * 1;
const keys_per_iteration = 20;

// Starts the expiration job for the given store.
// This function initiates a background process that periodically checks for
// and removes expired keys from the store to maintain data consistency
// and prevent memory leaks from stale entries.
pub fn startExpirationJob(store: *Store) !void {
    const thread = std.Thread.spawn(.{}, processExpiration, .{store}) catch |err| {
        std.log.err("Failed to spawn thread: {s}", .{@errorName(err)});
        return;
    };
    thread.detach();

    std.log.info("Expiration job started", .{});
}

fn initializeRandom() std.Random.DefaultPrng {
    var seed: u64 = undefined;
    std.posix.getrandom(std.mem.asBytes(&seed)) catch {
        seed = @as(u64, @intCast(std.time.milliTimestamp()));
    };
    return std.Random.DefaultPrng.init(seed);
}

fn calculateExpirationRatio(total_keys: usize, expiration_size: usize) f64 {
    if (total_keys == 0) return 0.0;
    return @as(f64, @floatFromInt(expiration_size)) / @as(f64, @floatFromInt(total_keys));
}

fn processExpirationCycle(store: *Store, prng: *std.Random.DefaultPrng) !void {
    var expiration_size = store.expirationSize();

    if (expiration_size == 0) {
        return;
    }

    // Do it once.
    var keys = store.expiration_map.keys();
    var values = store.expiration_map.values();
    try checkExpiredKeys(store, &keys, &values, prng);

    var total_keys = store.size();
    expiration_size = store.expirationSize();

    var ratio = calculateExpirationRatio(total_keys, expiration_size);

    // Continue if the ratio is greater than 25%
    while (ratio >= 0.25) {
        // Recalculate after each iteration as the map may have changed
        total_keys = store.size();
        expiration_size = store.expirationSize();

        if (expiration_size == 0) break;

        ratio = calculateExpirationRatio(total_keys, expiration_size);

        // Refresh the keys and values arrays
        keys = store.expiration_map.keys();
        values = store.expiration_map.values();
        try checkExpiredKeys(store, &keys, &values, prng);
    }
}

fn processExpiration(store: *Store) !void {
    var prng = initializeRandom();

    while (true) {
        std.log.debug("Expiration Map size {any}", .{store.expirationSize()});
        std.log.debug("Map size {any} thread", .{store.size()});
        try processExpirationCycle(store, &prng);
        std.Thread.sleep(interval);
    }
}

fn checkExpiredKeys(store: *Store, keys: *[][]const u8, values: *[]i64, prng: *std.Random.DefaultPrng) !void {
    const iterations = @min(store.expirationSize(), keys_per_iteration);
    for (0..iterations) |_| {
        const index = prng.random().uintLessThan(usize, store.expirationSize());

        const key = keys.*[index];
        const expiration_time = values.*[index];

        const now = std.time.milliTimestamp();
        if (now > expiration_time) {
            _ = store.delete(key);
        }
    }
}
