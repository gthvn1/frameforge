const std = @import("std");

// We are expecting an name for Veth and a CIDR
pub fn usage(prog: []const u8) void {
    std.debug.print(
        \\USAGE:
        \\  {s} --veth <veth-name> --cidr <ipv4 address>
        \\
        \\DESCRIPTION:
        \\  Veth devices are virtual Ethernet devices. They are created in
        \\  interconected pairs. "<veth-name>" and "<veth-name>-peer" are the
        \\  name assigned to the two connected end points.
        \\
        \\  The IP address must be in CIDR notation (xx.xx.xx.xx/yy). This
        \\  address will be assigned to <interfacce>.
        \\
        \\  The program will then listen on <veth-name>-peer for incoming Ethernet frames.
        \\  The MAC addresses are discovered automatically.
        \\
        \\EXAMPLES:
        \\  sudo {s} --veth veth0 --cidr 192.168.38.2/24
        \\
        \\NOTES:
        \\  - Requires root privileges or CAP_NET_ADMIN and CAP_NET_RAW capabilites.
        \\  - The virtual pair is created using:
        \\        ip link add <iface> type veth peer name <iface>-peer
        \\  - Useful for testing or simulating Layer 2 protocols (e.g., ARP).
        \\  - `man 4 veth` for more information.
        \\
    ,
        .{ prog, prog },
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
    Unknown,

    // Lookup table for args
    fn lookup(arg: []const u8) ArgType {
        if (std.mem.eql(u8, arg, "--veth")) return .Veth;
        if (std.mem.eql(u8, arg, "--cidr")) return .Cidr;
        return .Unknown;
    }
};

pub const Params = struct {
    veth_name: [:0]const u8,
    cidr: [:0]const u8,

    pub const Error = error{
        InvalidCIDR,
        MissingCIDR,
        MissingVethName,
    };

    pub fn parse(params: *std.process.ArgIterator) Params.Error!Params {
        var veth_name: ?[:0]const u8 = null;
        var cidr: ?[:0]const u8 = null;

        while (params.next()) |p| {
            switch (ArgType.lookup(p)) {
                .Veth => veth_name = params.next() orelse return Error.MissingVethName,
                .Cidr => cidr = params.next() orelse return Error.MissingCIDR,
                .Unknown => std.debug.print("skipping {s}\n", .{p}),
            }
        }

        if (veth_name == null) return Error.MissingVethName;
        if (cidr == null) return Error.MissingCIDR;

        if (checkCidr(cidr.?) == false) return Error.InvalidCIDR;

        return .{
            .veth_name = veth_name.?,
            .cidr = cidr.?,
        };
    }
};
