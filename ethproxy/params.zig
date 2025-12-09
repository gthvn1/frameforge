const std = @import("std");

// We are expecting an name for Veth and a CIDR
pub fn usage(prog: []const u8) void {
    std.debug.print(
        \\USAGE:
        \\  {s} [--veth <veth-name>] [--cidr <ipv4 address>] [--unix-socket <path>]
        \\
        \\DESCRIPTION:
        \\  Creates a veth pair "<veth-name>" and "<veth-name>-peer", assigns the
        \\  given IPv4/CIDR address to <veth-name>, and listens for Ethernet frames
        \\  on the peer interface. A Unix domain socket is used for data exchange
        \\ with frameforge server.
        \\
        \\OPTIONS:
        \\  --veth <name>        Name of the veth interface.
        \\                       Default: "veth0"
        \\
        \\  --cidr <IPv4/CIDR>   IPv4 address in CIDR format to assign.
        \\                       Default: "192.168.35.1/24"
        \\
        \\ --unix-socket <path>  Local socket used to communicate with frameforge server
        \\                       Default: "/tmp/frameforge.sock"
        \\
        \\EXAMPLES:
        \\  sudo {s} --veth veth2 --cidr 192.168.38.2/24
        \\  sudo {s} --unix-socket /tmp/custom.sock
        \\
        \\NOTES:
        \\  - Requires root privileges or CAP_NET_ADMIN and CAP_NET_RAW capabilites.
        \\  - The virtual pair is created using:
        \\        ip link add <iface> type veth peer name <iface>-peer
        \\  - Useful for testing or simulating Layer 2 protocols (e.g., ARP).
        \\  - `man 4 veth` for more information.
        \\
    ,
        .{ prog, prog, prog },
    );
}

fn checkCidr(s: [:0]const u8) bool {
    var parts_iter = std.mem.splitScalar(u8, s, '/');
    // Read the first part the should be an IPv4
    const ipv4 = parts_iter.next() orelse return false;
    const prefix = parts_iter.next() orelse return false;
    // We don't expect anything else
    if (parts_iter.next() != null) return false;

    // Check IP
    _ = std.net.Ip4Address.parse(ipv4, 1234) catch return false;

    // Prefix is valid from 0 to 32
    const p = std.fmt.parseInt(u8, prefix, 10) catch return false;
    return p <= 32;
}

const ArgType = enum {
    Veth,
    Cidr,
    UnixSocket,
    Unknown,

    // Lookup table for args
    fn lookup(arg: []const u8) ArgType {
        if (std.mem.eql(u8, arg, "--veth")) return .Veth;
        if (std.mem.eql(u8, arg, "--cidr")) return .Cidr;
        if (std.mem.eql(u8, arg, "--unix-socket")) return .UnixSocket;
        return .Unknown;
    }
};

pub const Params = struct {
    veth_name: [:0]const u8,
    cidr: [:0]const u8,
    unix_socket: [:0]const u8,

    pub const DEFAULT_VETH = "veth0";
    pub const DEFAULT_CIDR = "192.168.35.1/24";
    pub const DEFAULT_UNIX_SOCKET = "/tmp/frameforge.sock";

    pub const Error = error{
        InvalidCIDR,
    };

    pub fn parse(params: *std.process.ArgIterator) Params.Error!Params {
        var veth_name: [:0]const u8 = DEFAULT_VETH;
        var cidr: [:0]const u8 = DEFAULT_CIDR;
        var unix_socket: [:0]const u8 = DEFAULT_UNIX_SOCKET;

        while (params.next()) |p| {
            switch (ArgType.lookup(p)) {
                .Veth => veth_name = params.next() orelse DEFAULT_VETH,
                .Cidr => cidr = params.next() orelse DEFAULT_CIDR,
                .UnixSocket => unix_socket = params.next() orelse DEFAULT_UNIX_SOCKET,
                .Unknown => std.debug.print("skipping {s}\n", .{p}),
            }
        }

        if (checkCidr(cidr) == false) return Error.InvalidCIDR;

        return .{
            .veth_name = veth_name,
            .cidr = cidr,
            .unix_socket = unix_socket,
        };
    }
};
