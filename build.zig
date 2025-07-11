const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "space-borders",
        .root_source_file = b.path("src/active_window_borders.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link macOS frameworks
    exe.linkFramework("Cocoa");
    exe.linkFramework("CoreGraphics");
    exe.linkFramework("ApplicationServices");
    exe.linkFramework("Carbon");
    exe.linkFramework("CoreVideo");
    exe.linkFramework("QuartzCore");
    exe.linkSystemLibrary("objc");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}