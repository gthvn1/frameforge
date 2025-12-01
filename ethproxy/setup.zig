const std = @import("std");
const Child = std.process.Child;

// man 4 veth
// To create veth devices we just need to do
// - `ip link add <p1-name> type veth peer name <p2-name>`
// To run external command: https://cookbook.ziglang.cc/08-02-external/

pub const Veth = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    peer: []const u8,

    exit_code: u8,
    stdout: std.ArrayListUnmanaged(u8),
    stderr: std.ArrayListUnmanaged(u8),

    pub fn create(allocator: std.mem.Allocator, veth_name: []const u8, veth_cidr: []const u8) !Veth {
        const veth_peer = try std.mem.concat(allocator, u8, &.{
            veth_name,
            "-peer",
        });

        var exit_code: u8 = 0;
        var stdout: std.ArrayListUnmanaged(u8) = .empty;
        var stderr: std.ArrayListUnmanaged(u8) = .empty;

        const cmds = [_][]const []const u8{
            &[_][]const u8{ "ip", "link", "show", veth_name },
            &[_][]const u8{ "ip", "link", "add", veth_name, "type", "veth", "peer", "name", veth_peer },
            &[_][]const u8{ "ip", "addr", "add", veth_cidr, "dev", veth_name },
            &[_][]const u8{ "ip", "link", "set", veth_name, "up" },
            &[_][]const u8{ "ip", "link", "set", veth_peer, "up" },
        };

        inline for (cmds) |cmd| {
            exit_code = try runCmd(cmd, allocator, &stdout, &stderr);
            if (exit_code != 0) break;
        }

        return Veth{
            .allocator = allocator,
            .name = veth_name,
            .peer = veth_peer,
            .stdout = stdout,
            .stderr = stderr,
            .exit_code = exit_code,
        };
    }

    pub fn destroy(self: *Veth) void {
        const cmds = [_][]const []const u8{
            &[_][]const u8{ "ip", "link", "set", self.name, "down" },
            &[_][]const u8{ "ip", "link", "set", self.peer, "down" },
            &[_][]const u8{ "ip", "link", "del", self.name },
        };

        inline for (cmds) |cmd| {
            _ = runCmd(cmd, self.allocator, &self.stdout, &self.stderr) catch {};
        }

        self.allocator.free(self.peer);
        self.stderr.deinit(self.allocator);
        self.stdout.deinit(self.allocator);
    }
};

fn runCmd(cmd: []const []const u8, allocator: std.mem.Allocator, stdout: *std.ArrayListUnmanaged(u8), stderr: *std.ArrayListUnmanaged(u8)) !u8 {
    var child = Child.init(cmd, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    try child.collectOutput(allocator, stdout, stderr, 1024);
    const term = try child.wait();

    return term.Exited;
}
