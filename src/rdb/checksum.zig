const std = @import("std");

/// Implements CRC-64-Jones, the algorithm used by Redis for RDB checksums.
pub const CRC64 = struct {
    /// The specific polynomial for CRC-64-Jones.
    const polynomial: u64 = 0xad93d23594c935a9;

    /// A 256-entry lookup table for fast checksum calculation.
    /// This table is generated at compile time for maximum efficiency.
    const lookup_table: [256]u64 = blk: {
        var table: [256]u64 = undefined;
        var i: usize = 0;
        while (i < 256) : (i += 1) {
            var value = @as(u64, @intCast(i));
            var j: u4 = 0;
            @setEvalBranchQuota(256 * 9);
            while (j < 8) : (j += 1) {
                if (value & 1 == 1) {
                    value = (value >> 1) ^ polynomial;
                } else {
                    value >>= 1;
                }
            }
            table[i] = value;
        }
        break :blk table;
    };

    /// Calculates the CRC64 checksum for a given data slice.
    pub fn checksum(data: []const u8) u64 {
        // Start with the initial value (all ones).
        var crc: u64 = 0xffffffffffffffff;

        // Process each byte using the lookup table.
        for (data) |byte| {
            // XOR the low byte of the current CRC with the current data byte.
            // Then use the result as an index into the lookup table.
            const index = @as(u8, @truncate(crc)) ^ byte;
            // Shift the current CRC and XOR it with the table value.
            crc = (crc >> 8) ^ lookup_table[index];
        }

        // The Redis implementation requires reflecting the final CRC value
        // and then performing a final NOT operation (equivalent to XOR with all ones).
        return ~@bitReverse(crc);
    }
};
