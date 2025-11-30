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

pub const Params = struct {
    veth_name: []const u8,
    cidr: []const u8,

    pub const Error = error{
        InvalidCIDR,
        MissingCIDR,
        MissingVethName,
    };

    pub fn parse(params: std.ArrayList([]const u8)) Params.Error!Params {
        for (params.items) |p| {
            std.debug.print("Argument: {s}\n", .{p});
        }
        return error.MissingVethName;
    }
};
