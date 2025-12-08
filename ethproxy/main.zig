const std = @import("std");
const posix = std.posix;

const params = @import("params.zig");
const Params = params.Params;

const Veth = @import("setup.zig").Veth;
const utils = @import("utils.zig");

// We are using a global variable to quit loop so handler
// of sigint can set it. Not sure if it is the correct solution.
// As it is global let's use an atomic one...
var quit_loop = std.atomic.Value(bool).init(false);

fn handleSigint(sig: c_int) callconv(.c) void {
    _ = sig;
    quit_loop.store(true, .release);
}

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
    var veth = try Veth.init(allocator, client_args.veth_name);
    defer veth.destroy();

    veth.createVeth(client_args.cidr) catch {
        std.debug.print("Failed to create veth pair: {s}\n", .{veth.stderr.items});
        return;
    };

    // At this point the network should be up and running.
    // But before starting the proxy we need to setup a signal handler for Sigint
    // to be able to quit properly and cleanup network.
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

    runProxy(&veth) catch |err| {
        std.debug.print("Failed to run client: {}\n", .{err});
    };
}

fn runProxy(veth: *Veth) !void {
    // We are listening for incoming raw frame on peer interface and
    // forwards them to the frameforge server.

    // ----------------------------------------------------------------
    // First listen on peer socket. It is a low level packet using
    // raw network protocol.
    // man 7 packet
    const peer_sockfd = try posix.socket(posix.AF.PACKET, posix.SOCK.RAW, 0);
    defer posix.close(peer_sockfd);

    const peer_mac = try veth.getPeerMac();

    const ssl_protocol = std.mem.nativeToBig(u16, std.os.linux.ETH.P.ALL);
    const ssl_ifindex = try veth.getPeerIfIndex();
    const ssl_hatype = 0;
    const ssl_pkttype = std.os.linux.PACKET.BROADCAST;
    const ssl_halen = peer_mac.len;
    var ssl_addr = [_]u8{0} ** 8; // for sockaddr.ll addr is [8]u8
    std.mem.copyForwards(u8, ssl_addr[0..], peer_mac[0..6]);

    const peer_sockaddr: posix.sockaddr.ll = .{
        .family = posix.AF.PACKET,
        .protocol = ssl_protocol,
        .ifindex = ssl_ifindex,
        .hatype = ssl_hatype,
        .pkttype = ssl_pkttype,
        .halen = ssl_halen,
        .addr = ssl_addr,
    };

    posix.bind(peer_sockfd, @ptrCast(&peer_sockaddr), @sizeOf(posix.sockaddr.ll)) catch |err| {
        std.debug.print("Failed to bound endpoint: {s}\n", .{@errorName(err)});
        return error.PeerBindFailed;
    };

    std.debug.print("Bound to interface {s}\n", .{veth.peer});

    // ----------------------------------------------------------------
    // Use local socket AF_UNIX to communicate with server
    // man 7 unix
    const local_sockfd = try posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0);
    defer posix.close(local_sockfd);

    var path: [108]u8 = [_]u8{0} ** 108;
    const path_str = "/tmp/frameforge.socket";
    std.mem.copyForwards(u8, &path, path_str);

    const local_sockaddr: posix.sockaddr.un = .{
        .family = posix.AF.UNIX,
        .path = path,
    };
    try posix.connect(local_sockfd, @ptrCast(&local_sockaddr), @sizeOf(posix.sockaddr.un));

    var stdin_buffer: [64]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    const timeout_ms: i32 = 200;

    std.debug.print("> ", .{}); // first prompt

    // ----------------------------------------------------------------
    // Finally the main loop, when something is received on peer, forward
    // it to server... Quit when ctrl-c is pressed.
    //
    // TODO:
    // After adding a veth peer socket, data can now arrive from two places:
    //   - stdin (the user input FD)
    //   - peer_sockfd (the veth peer)
    // Need to select the correct source now.
    //
    loop: while (!quit_loop.load(.acquire)) {
        // Ask to the user what to send. But as we can block we need to poll or timeout
        // so if the user hit ctrl-c we will be able to catch it. Otherwise we need to wait
        // that something is entered to catch it.
        var fds = [_]std.posix.pollfd{.{
            .fd = std.posix.STDIN_FILENO,
            .events = posix.POLL.IN,
            .revents = 0,
        }};

        const ret = std.posix.poll(&fds, timeout_ms) catch continue :loop;
        if (ret == 0) continue :loop; // n == 0 means we hit the timeout

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
        _ = try posix.send(local_sockfd, &header, 0);
        _ = try posix.send(local_sockfd, msg, 0);

        // And wait for the response...
        var buf: [64]u8 = undefined;
        const n = try posix.recv(local_sockfd, &buf, 0);

        if (n < 4) {
            std.debug.print("We should at least received 4 bytes, received {d}\n", .{n});
            continue :loop;
        }

        // The first four bytes are the size and then the data
        const data_len: u32 = std.mem.readInt(u32, buf[0..4], .little);
        std.debug.print("ETHPROXY: Data size: {d} \n", .{data_len});
        std.debug.print("ETHPROXY: Payload  : {s}\n", .{buf[4 .. 4 + data_len]});

        std.debug.print("> ", .{});
    }

    std.debug.print("Break out of the loop cleanly\n", .{});
}
