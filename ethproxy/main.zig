const std = @import("std");
const posix = std.posix;

const params = @import("params.zig");
const Params = params.Params;

const Veth = @import("setup.zig").Veth;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args_iter = std.process.args();

    // First parameter is the name of the program
    // It is not expected to not have it...
    const progname = args_iter.next() orelse unreachable();

    const client_args = Params.parse(&args_iter) catch |err| {
        switch (err) {
            Params.Error.InvalidCIDR => std.debug.print("Invalid CIDR\n", .{}),
            Params.Error.MissingCIDR => std.debug.print("CIDR is missing\n", .{}),
            Params.Error.MissingVethName => std.debug.print("Veth name is missing\n", .{}),
        }

        params.usage(progname);
        return;
    };

    // Print that we have all parameters
    std.debug.print("vethname is {s}\n", .{client_args.veth_name});
    std.debug.print("cidr is {s}\n", .{client_args.cidr});

    // We can now setup the network
    var veth = Veth.create(allocator, client_args.veth_name, client_args.cidr) catch |err| {
        std.debug.print("Unexpected error when creating veth: {}\n", .{err});
        return;
    };
    defer veth.destroy();

    // Check the error code
    if (veth.exit_code != 0) {
        std.debug.print("Failed to create veth pair: {s}\n", .{veth.stderr.items});
        return;
    }

    // At this point the network should be up and running.
    simpleClient() catch |err| {
        std.debug.print("Failed to run client: {}\n", .{err});
    };
}

// We are using a global variable to quit loop so handler
// of sigint can set it. Not sure if it is the correct solution.
// As it is global let's use an atomic one...
var quit_loop = std.atomic.Value(bool).init(false);

fn handleSigint(sig: c_int) callconv(.c) void {
    _ = sig;
    quit_loop.store(true, .release);
}

fn simpleClient() !void {
    // At this point the network should be up and running.
    // We will go to the infinite loop but before we need to
    // setup a signal handler for Sigint to be able to quit properly
    // and cleanup network.
    //   - man signal
    //   - man 7 signal
    const signalInterrupt = std.posix.Sigaction{
        .handler = .{ .handler = handleSigint },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    // Change the signal action SIGINT that is "interrupt from keyboard"
    std.posix.sigaction(std.posix.SIG.INT, &signalInterrupt, null);
    std.debug.print("You can quit using Ctrl-C\n", .{});

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

    var stdin_buffer: [64]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    loop: while (!quit_loop.load(.acquire)) {
        // Ask to the user what to send
        std.debug.print("> ", .{});
        const msg = try stdin.takeDelimiterExclusive('\n');
        // consume the '\n'
        _ = try stdin.take(1);

        std.debug.print("READ <{s}>\n", .{msg});

        // We are using a simple protocol where we send the size of the data
        // and then the data.
        // We use an array of 4 bytes to be sure that it will be send using
        // the correct format.
        var header: [4]u8 = undefined; // will contain the size of the msg
        std.mem.writeInt(u32, &header, @intCast(msg.len), .little);
        _ = try posix.send(sock, &header, 0);
        _ = try posix.send(sock, msg, 0);

        // And wait for the response...
        var buf: [64]u8 = undefined;
        const n = try posix.recv(sock, &buf, 0);

        if (n < 4) {
            std.debug.print("We should at least received 4 bytes, received {d}\n", .{n});
            continue :loop;
        }

        // The first four bytes are the size and then the data
        const data_len: u32 = std.mem.readInt(u32, buf[0..4], .little);
        std.debug.print("ETHPROXY: Data size: {d} \n", .{data_len});
        std.debug.print("ETHPROXY: Payload  : {s}\n", .{buf[4 .. 4 + data_len]});
    }

    std.debug.print("Break out of the loop cleanly\n", .{});
}
