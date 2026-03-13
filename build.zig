const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_optimize = b.option(std.builtin.OptimizeMode, "dep-optimize", "optimization mode") orelse .ReleaseFast;

    const libevdev = b.dependency("libevdev", .{
        .target = target,
        .optimize = dep_optimize,
    });
    const libevdev_artifact = libevdev.artifact("evdev");

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(libevdev_artifact.getEmittedIncludeTree());

    const translate_c_module = translate_c.createModule();
    translate_c_module.linkLibrary(libevdev_artifact);

    const exe = b.addExecutable(.{
        .name = "caps2esc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{
                .name = "c",
                .module = translate_c_module,
            }},
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
