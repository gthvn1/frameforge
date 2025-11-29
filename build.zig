const std = @import("std");

pub fn build(b: *std.Build) !void {

    // ---- Build Zig client
    const exe = b.addExecutable(.{
        .name = "ethproxy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("ethproxy/client.zig"),
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        }),
    });

    b.installArtifact(exe);

    // ----- Build Ocaml server via dune
    const dune_build = b.step("dune", "Build Ocaml project using dune");
    const cmd = b.addSystemCommand(&.{ "dune", "build" });
    cmd.cwd = b.path("frameforge");

    try dune_build.addWatchInput(b.path("frameforge/bin/main.ml"));
    try dune_build.addWatchInput(b.path("frameforge/lib/server.ml"));
    try dune_build.addWatchInput(b.path("frameforge/lib/server.mli"));

    dune_build.dependOn(&cmd.step);
    // Add it in default target
    b.default_step.dependOn(dune_build);

    // ----- Add a run step
    // we want to:
    //   - start the server
    //   - wait that socket /tmp/frameforge.socket is ready
    //   - start the client
    const run_step = b.step("run", "Run frameforge and zclient");

    run_step.dependOn(&exe.step);
    run_step.dependOn(dune_build);

    // start frameforge in the background and wait for socket to be ready
    const server = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\ ./frameforge/_build/default/bin/main.exe --test &
        \\ echo "Waiting for server to be ready"
        \\ for i in $(seq 1 50); do
        \\   [ -S /tmp/frameforge.socket ] && exit 0
        \\   sleep 0.1
        \\ done
        \\ echo "Failed to get /tmp/frameforge.socket ready; timed out."
        \\ exit 1
        ,
    });

    // Run the client when server is ready
    const client = b.addRunArtifact(exe);
    client.step.dependOn(&server.step);

    // Finally we have all the parts
    run_step.dependOn(&client.step);
}
