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

    code: u8,
    stdout: std.ArrayListUnmanaged(u8),
    stderr: std.ArrayListUnmanaged(u8),

    pub fn create(allocator: std.mem.Allocator, veth_name: []const u8) !Veth {
        const veth_peer = try std.mem.concat(allocator, u8, &.{
            veth_name,
            "-peer",
        });

        const argv = [_][]const u8{
            "ip",
            "link",
            "add",
            veth_name,
            "type",
            "veth",
            "peer",
            "name",
            veth_peer,
        };

        // We want to get the output of the command.
        var child = Child.init(&argv, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        var stdout: std.ArrayListUnmanaged(u8) = .empty;
        var stderr: std.ArrayListUnmanaged(u8) = .empty;

        try child.spawn();

        try child.collectOutput(allocator, &stdout, &stderr, 1024);
        const term = try child.wait();

        return Veth{
            .allocator = allocator,
            .name = veth_name,
            .peer = veth_peer,
            .stdout = stdout,
            .stderr = stderr,
            .code = term.Exited,
        };
    }

    pub fn destroy(self: *Veth) void {
        // TODO: destroy the veth pair
        // - `ip link set <p1-name> down`
        // - `ip link del <p1-name>`
        self.allocator.free(self.peer);
        self.stderr.deinit(self.allocator);
        self.stdout.deinit(self.allocator);
    }
};
