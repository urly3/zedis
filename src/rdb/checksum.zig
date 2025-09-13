const std = @import("std");

/// Implements the CRC-64 algorithm used by Redis/Valkey.
///
/// This specific variant is defined by the following parameters:
/// - Polynomial: 0xad93d23594c935a9
/// - Initial Value: 0xffffffffffffffff
/// - Reflect Input: True
/// - Reflect Output: True
/// - Final XOR: 0x0000000000000000
pub const CRC64 = struct {
    /// The generator polynomial for this CRC64 variant.
    const polynomial: u64 = 0xad93d23594c935a9;

    /// A 256-entry lookup table for fast checksum calculation, generated at compile-time.
    const lookup_table: [256]u64 = blk: {
        var table: [256]u64 = undefined;
        var i: u16 = 0;
        while (i < 256) : (i += 1) {
            var value: u64 = i;
            var j: u4 = 0;
            @setEvalBranchQuota(256 * 9);
            while (j < 8) : (j += 1) {
                if (value & 1 == 1) {
                    value = (value >> 1) ^ polynomial;
                } else {
                    value >>= 1;
                }
            }
            table[@as(u8, @truncate(i))] = value;
        }
        break :blk table;
    };

    /// Returns the initial value for the CRC calculation.
    /// The standard requires starting with all bits set to 1.
    pub fn init() u64 {
        return ~@as(u64, 0);
    }

    /// Updates a running checksum with a new slice of data.
    pub fn update(current_crc: u64, data: []const u8) u64 {
        var crc = current_crc;
        // Process each byte using the standard reflected table-driven method.
        for (data) |byte| {
            const index = @as(u8, @truncate(crc)) ^ byte;
            crc = (crc >> 8) ^ lookup_table[index];
        }
        return crc;
    }

    /// Calculates the CRC64 checksum for a given data slice in one go.
    /// This is a convenience function that wraps init, update, and final.
    pub fn checksum(data: []const u8) u64 {
        const initial_crc = init();
        const updated_crc = update(initial_crc, data);
        return ~(updated_crc);
    }
};
