const std = @import("std");
const posix = std.posix;

pub fn main() !void {
    // man 7 unix
    // -> We use AF_UNIX to communicate locally between processes
    const sock = try posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0);

    // Now we need to bind to local file: man 2 connect
    var path: [108]u8 = [_]u8{0} ** 108;
    const path_str = "/tmp/frameforge.socket";
    std.mem.copyForwards(u8, &path, path_str);

    const laddr: posix.sockaddr.un = .{
        .family = posix.AF.UNIX,
        .path = path,
    };
    try posix.connect(sock, @ptrCast(&laddr), @sizeOf(posix.sockaddr.un));
    defer posix.close(sock);

    // Now we can send the ping
    _ = try posix.send(sock, "ping", 0);

    // And wait for the pong...
    var buf: [32]u8 = undefined;
    const n = try posix.recv(sock, &buf, 0);
    std.debug.print("Received {d} bytes: {s}", .{ n, buf[0..n] });
}
