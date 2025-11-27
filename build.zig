const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "zclient",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig_client/client.zig"),
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        }),
    });

    b.installArtifact(exe);

    const dune_build = b.step("dune", "Build Ocaml project using dune");
    const cmd = b.addSystemCommand(&.{ "dune", "build" });
    cmd.cwd = b.path("frameforge");

    dune_build.dependOn(&cmd.step);
    // Add it in default target
    b.default_step.dependOn(dune_build);
}
