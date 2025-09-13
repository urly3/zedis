const std = @import("std");

/// Implements the CRC-64 algorithm used by Redis/Valkey.
/// Parameters:
///   Width   = 64
///   Poly    = 0xad93d23594c935a9 (normal form) / 0x95ac9329ac4bc9b5 (reflected form)
///   XorIn   = 0xffffffffffffffff
///   XorOut  = 0x0000000000000000
///   RefIn   = true (bytes are processed LSB-first)
///   RefOut  = true (we perform a final bit reflection)
pub const CRC64 = struct {
    /// Reflected polynomial (LSB-first form) used for table driven updates.
    const reflected_polynomial: u64 = 0x95ac9329ac4bc9b5;

    /// Reflect bits in a 64-bit value.
    fn reflect64(x: u64) u64 {
        var v = x;
        var i: u6 = 0;
        while (i < 32) : (i += 1) {
            const lo_bit = (v >> i) & 1;
            const hi_shift: u6 = @intCast(63 - i);
            const hi_bit = (v >> hi_shift) & 1;
            if (lo_bit != hi_bit) {
                const lo_mask: u64 = @as(u64, 1) << i;
                const hi_mask: u64 = @as(u64, 1) << hi_shift;
                v ^= lo_mask | hi_mask;
            }
        }
        return v;
    }

    const lookup_table: [256]u64 = blk: {
        var table: [256]u64 = undefined;
        var i: u16 = 0;
        @setEvalBranchQuota(256 * 9);
        while (i < 256) : (i += 1) {
            var crc: u64 = @as(u64, @intCast(@as(u8, @truncate(i))));
            var j: u4 = 0;
            while (j < 8) : (j += 1) {
                if ((crc & 1) == 1) {
                    crc = (crc >> 1) ^ reflected_polynomial;
                } else {
                    crc >>= 1;
                }
            }
            table[@as(u8, @truncate(i))] = crc;
        }
        break :blk table;
    };

    pub fn update(current_crc: u64, data: []const u8) u64 {
        var crc = current_crc;
        for (data) |b| {
            const idx = (@as(u8, @truncate(crc))) ^ b;
            crc = (crc >> 8) ^ lookup_table[idx];
        }
        return crc;
    }

    pub fn checksum(data: []const u8) u64 {
        // Redis/Valkey effective parameters for the fast path implementation:
        //   initial crc = 0
        //   no final reflection/XorOut at API boundary (reflection is baked into bit-by-bit reference)
        // The combination of reflected polynomial + this table-driven method
        // yields values matching crc64(0, data, len) in Redis (see crc64.c test vectors).
        const init: u64 = 0;
        return update(init, data);
    }
};

const testing = std.testing;

test "CRC64 String key" {
    const rdb = [_]u8{
        0x52, 0x45, 0x44, 0x49, 0x53, 0x30, 0x30, 0x31,
        0x32, 0xfa, 0x09, 0x72, 0x65, 0x64, 0x69, 0x73,
        0x2d, 0x76, 0x65, 0x72, 0x0b, 0x32, 0x35, 0x35,
        0x2e, 0x32, 0x35, 0x35, 0x2e, 0x32, 0x35, 0x35,
        0xfa, 0x0a, 0x72, 0x65, 0x64, 0x69, 0x73, 0x2d,
        0x62, 0x69, 0x74, 0x73, 0xc0, 0x40, 0xfa, 0x05,
        0x63, 0x74, 0x69, 0x6d, 0x65, 0xc2, 0x7f, 0xb2,
        0xc5, 0x68, 0xfa, 0x08, 0x75, 0x73, 0x65, 0x64,
        0x2d, 0x6d, 0x65, 0x6d, 0xc2, 0xb0, 0xb6, 0x0d,
        0x00, 0xfa, 0x08, 0x61, 0x6f, 0x66, 0x2d, 0x62,
        0x61, 0x73, 0x65, 0xc0, 0x00, 0xfe, 0x00, 0xfb,
        0x03, 0x00, 0x00, 0x04, 0x6b, 0x65, 0x79, 0x32,
        0xc0, 0x02, 0x00, 0x04, 0x6b, 0x65, 0x79, 0x33,
        0x0b, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x2d, 0x77,
        0x6f, 0x72, 0x6c, 0x64, 0x00, 0x04, 0x6b, 0x65,
        0x79, 0x31, 0x03, 0x6f, 0x6c, 0x61, 0xff,
    };

    const crc = CRC64.checksum(&rdb);
    try testing.expectEqual(@as(u64, 7264180175356744374), crc);
}

test "CRC64 canonical test vector 123456789" {
    const input = "123456789";
    const crc = CRC64.checksum(input);
    // Known Redis/Valkey CRC64 for this vector.
    try testing.expectEqual(@as(u64, 0xe9c6d914c4b8d9ca), crc);
}
