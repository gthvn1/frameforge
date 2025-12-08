const std = @import("std");

pub fn macToString(mac: []const u8, buf: *[17]u8) ![]const u8 {
    return try std.fmt.bufPrint(
        buf[0..],
        "{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}:{x:0>2}",
        .{ mac[0], mac[1], mac[2], mac[3], mac[4], mac[5] },
    );
}

pub fn stringToMac(str: []const u8, buf: *[6]u8) !void {
    var it = std.mem.splitScalar(u8, str, ':');
    var idx: usize = 0;

    while (it.next()) |s| {
        if (idx >= 6) return error.MacStringTooBig;

        buf[idx] = try std.fmt.parseInt(u8, s, 16);
        idx += 1;
    }

    if (idx != 6) return error.MacStringTooSmall;
}
