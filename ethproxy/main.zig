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

    runProxy(&veth, client_args.unix_socket) catch |err| {
        std.debug.print("Failed to run client: {}\n", .{err});
    };
}

fn runProxy(veth: *Veth, unix_socket_path: [:0]const u8) !void {
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
    std.mem.copyForwards(u8, &path, unix_socket_path);

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
    loop: while (!quit_loop.load(.acquire)) {
        // Ask to the user what to send. But as we can block we need to poll or timeout
        // so if the user hit ctrl-c we will be able to catch it. Otherwise we need to wait
        // that something is entered to catch it.
        var fds = [_]std.posix.pollfd{
            .{ .fd = std.posix.STDIN_FILENO, .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = peer_sockfd, .events = posix.POLL.IN, .revents = 0 },
        };

        const ret = std.posix.poll(&fds, timeout_ms) catch continue :loop;
        if (ret == 0) continue :loop; // n == 0 means we hit the timeout

        var frame_buf: [1600]u8 = undefined;
        var msg: ?[]u8 = null;

        if (fds[0].revents & posix.POLL.IN != 0) {
            // ---- Read from user -----
            msg = try stdin.takeDelimiterExclusive('\n');
            _ = try stdin.take(1); // consume the '\n'
            std.debug.print("READ <{s}>\n", .{msg.?});
        } else if (fds[1].revents & posix.POLL.IN != 0) {
            // ---- Read from peer socket -----
            // NOTE: we assume here that Linux returns a whole packet because we are
            //       using AF_PACKET, SOCK_RAW.
            const bytes = posix.read(peer_sockfd, frame_buf[0..]) catch |err| {
                std.debug.print("Failed to read data from peer: {s}\n", .{@errorName(err)});
                return error.PeerReadFailed;
            };
            std.debug.print("TODO: Received a frame of {d} bytes !!!\n", .{bytes});
            msg = frame_buf[0..bytes];
        } else {
            std.debug.print("WTF???\n", .{});
            continue :loop;
        }

        // We are using a simple protocol where we send the size of the data
        // and then the data.
        if (msg) |m| {
            var header: [4]u8 = undefined; // will contain the size of m
            std.mem.writeInt(u32, &header, @intCast(m.len), .little);
            _ = try posix.send(local_sockfd, &header, 0);
            _ = try posix.send(local_sockfd, m, 0);

            // We need to read the exact number of bytes otherwise we will be desynchrnized
            // and most probably crashed the client.
            // So first get the size of the payload
            try readExact(local_sockfd, &header);
            const payload_len = std.mem.readInt(u32, header[0..4], .little);
            std.debug.print("ETHPROXY: Data size: {d} \n", .{payload_len});

            // Now we need to read exactly the payload
            const payload = try std.heap.page_allocator.alloc(u8, payload_len);
            defer std.heap.page_allocator.free(payload);

            try readExact(local_sockfd, payload);
            std.debug.print("ETHPROXY: Payload  : {s}\n", .{payload});
        }

        std.debug.print("> ", .{});
    }

    std.debug.print("Break out of the loop cleanly\n", .{});
}

// Reads bytes until buffer is filled
fn readExact(fd: posix.fd_t, buf: []u8) !void {
    var off: usize = 0;

    while (off < buf.len) {
        const n = try posix.recv(fd, buf[off..], 0);
        if (n == 0) return error.ConnectionClosed;
        off += n;
    }
}
