const std = @import("std");
const Child = std.process.Child;

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
        _ = try self.runCmd(cmd);

        // We need to pase the JSON output
        const json_str = self.stdout.items;
        const parser = try std.json.parseFromSlice([]VethJsonIface, self.allocator, json_str, .{
            .ignore_unknown_fields = true,
        });
        defer parser.deinit();

        std.debug.print("TODO: extract the real value from sting:\n{s}\n", .{json_str});
        const fake_mac = [6]u8{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
        return fake_mac;
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
