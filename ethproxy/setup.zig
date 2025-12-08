const std = @import("std");
const Child = std.process.Child;

const utils = @import("utils.zig");

// man 4 veth
// To create veth devices we just need to do
// - `ip link add <p1-name> type veth peer name <p2-name>`
// To run external command: https://cookbook.ziglang.cc/08-02-external/

// This is used to read the output from "ip -j link show ..."
const VethJsonIface = struct {
    ifindex: i32,
    ifname: []const u8,
    flags: []const []const u8,
    mtu: i32,
    qdisc: []const u8,
    operstate: []const u8,
    linkmode: []const u8,
    group: []const u8,
    link_type: []const u8,
    link: ?[]const u8 = null,
    master: ?[]const u8 = null,
    txqlen: ?i32 = null,
    address: ?[]const u8 = null,
    broadcast: ?[]const u8 = null,
    altnames: ?[]const []const u8 = null,
};

pub const Veth = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    peer: []const u8,
    peer_mac: ?[6]u8 = null,

    stdout: std.ArrayListUnmanaged(u8),
    stderr: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator, veth_name: []const u8) !Veth {
        const veth_peer = try std.mem.concat(allocator, u8, &.{
            veth_name,
            "-peer",
        });

        return Veth{
            .allocator = allocator,
            .name = veth_name,
            .peer = veth_peer,
            .stdout = .empty,
            .stderr = .empty,
        };
    }

    pub fn createVeth(self: *Veth, veth_cidr: []const u8) !void {
        // Clear buffer even if we excpect them to be empty since createVeth should be the first
        // function called.
        self.resetBuffers();

        const cmds = .{
            .{ &[_][]const u8{ "ip", "link", "show", self.name }, 1 },
            .{ &[_][]const u8{ "ip", "link", "add", self.name, "type", "veth", "peer", "name", self.peer }, 0 },
            .{ &[_][]const u8{ "ip", "addr", "add", veth_cidr, "dev", self.name }, 0 },
            .{ &[_][]const u8{ "ip", "link", "set", self.name, "up" }, 0 },
            .{ &[_][]const u8{ "ip", "link", "set", self.peer, "up" }, 0 },
        };

        inline for (cmds) |cmd| {
            const exit_code = try self.runCmd(cmd[0]);
            if (exit_code != cmd[1]) return error.CommandFailed;
        }
    }

    pub fn getPeerMac(self: *Veth) ![6]u8 {
        if (self.peer_mac) |mac| {
            return mac;
        }

        self.resetBuffers();
        const cmd = &[_][]const u8{ "ip", "-j", "link", "show", self.peer };
        if (try self.runCmd(cmd) != 0) return error.CommandFailed;

        // We need to parse the JSON output. We are expecting:
        // [{"ifindex":18,
        //   "link":"toto",
        //   "ifname":"toto-peer",
        //   "flags":["BROADCAST","MULTICAST","UP","LOWER_UP"],
        //   "mtu":1500,
        //   "qdisc":"noqueue",
        //   "operstate":"UP",
        //   "linkmode":"DEFAULT",
        //   "group":"default",
        //   "txqlen":1000,
        //   "link_type":"ether",
        //   "address":"be:ef:0f:ce:76:0b",
        //   "broadcast":"ff:ff:ff:ff:ff:ff"}]
        const json_str = self.stdout.items;
        const parsed_output = try std.json.parseFromSlice([]VethJsonIface, self.allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
        defer parsed_output.deinit();

        // We are expecting only one device
        const peer_mac_str = switch (parsed_output.value.len) {
            0 => return error.DeviceNotFound,
            1 => parsed_output.value[0].address.?,
            else => return error.MultipleDeviceFound,
        };

        var mac: [6]u8 = undefined;
        try utils.stringToMac(peer_mac_str, &mac);

        self.peer_mac = mac;
        return mac;
    }

    pub fn destroy(self: *Veth) void {
        const cmds = .{
            &[_][]const u8{ "ip", "link", "set", self.name, "down" },
            &[_][]const u8{ "ip", "link", "set", self.peer, "down" },
            &[_][]const u8{ "ip", "link", "del", self.name },
        };

        inline for (cmds) |cmd| {
            _ = runCmd(self, cmd) catch {};
        }

        self.allocator.free(self.peer);
        self.stderr.deinit(self.allocator);
        self.stdout.deinit(self.allocator);
    }

    fn resetBuffers(self: *Veth) void {
        self.stdout.clearRetainingCapacity();
        self.stderr.clearRetainingCapacity();
    }

    fn runCmd(self: *Veth, cmd: []const []const u8) !u8 {
        var child = Child.init(cmd, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        try child.collectOutput(self.allocator, &self.stdout, &self.stderr, 1024);
        const term = try child.wait();

        return term.Exited;
    }
};
