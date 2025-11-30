const std = @import("std");
const posix = std.posix;

const params = @import("params.zig");
const Params = params.Params;

pub fn main() !void {

    // Get all params and parse them
    var args_iter = std.process.args();

    // First parameter is the name of the program
    const progname = args_iter.next() orelse "ethproxy";

    // Now we need to construct a list with the rest of parameters
    const GpaType = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GpaType{};
    const allocator = gpa.allocator();
    defer (std.debug.assert(gpa.deinit() == std.heap.Check.ok));

    const arrayType = std.ArrayList([]const u8); // We want a list of strings

    var params_list = arrayType.empty;
    defer params_list.deinit(allocator);

    while (args_iter.next()) |arg| {
        try params_list.append(allocator, arg);
    }

    _ = Params.parse(params_list) catch |err| {
        switch (err) {
            Params.Error.InvalidCIDR => {
                std.debug.print("Invalid CIDR\n", .{});
            },
            Params.Error.MissingCIDR => {
                std.debug.print("CIDR is missing\n", .{});
            },
            Params.Error.MissingVethName => {
                std.debug.print("Veth name is missing\n", .{});
            },
        }

        params.usage(progname);
        return;
    };

    simple_ping_client() catch |err| {
        std.debug.print("Failed to run ping client: {}\n", .{err});
    };
}

fn simple_ping_client() !void {
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
    // We are using a simple protocol where we send the size of the data
    // and then the data.

    const msg = "ping";

    // We use an array of 4 bytes to be sure that it will be send using
    // the correct format.
    var header: [4]u8 = undefined; // will contain the size of the msg
    header[0] = msg.len & 0xff;
    header[1] = (msg.len >> 8) & 0xff;
    header[2] = (msg.len >> 16) & 0xff;
    header[3] = (msg.len >> 24) & 0xff;

    _ = try posix.send(sock, &header, 0);
    _ = try posix.send(sock, msg, 0);

    // And wait for the response...
    var buf: [64]u8 = undefined;
    const n = try posix.recv(sock, &buf, 0);

    if (n < 4) {
        std.debug.print("We should at least received 4 bytes, received {d}\n", .{n});
        return;
    }

    // The first four bytes are the size and then the data
    const data_len: u32 =
        @as(u32, buf[0]) | @as(u32, buf[1]) << 8 | @as(u32, buf[2]) << 16 | @as(u32, buf[3]) << 24;

    std.debug.print("ETHPROXY: Data size: {d} \n", .{data_len});
    std.debug.print("ETHPROXY: Payload  : {s}\n", .{buf[4 .. 4 + data_len]});
}
