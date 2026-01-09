const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_optimize = b.option(std.builtin.OptimizeMode, "dep-optimize", "optimization mode") orelse .ReleaseFast;

    const exe = b.addExecutable(.{
        .name = "caps2esc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const libevdev = b.dependency("libevdev", .{
        .target = target,
        .optimize = dep_optimize,
    });
    exe.root_module.linkLibrary(libevdev.artifact("evdev"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
