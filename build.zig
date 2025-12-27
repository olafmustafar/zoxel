const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{ .name = "zoxel", .root_module = mod });
    b.installArtifact(exe);

    const raylib = b.dependency("raylib", .{ .target = target, .optimize = optimize }).artifact("raylib");

    const translate_raylib = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.addWriteFiles().add("all.h",
            \\#include <raylib.h>
            \\#include <rcamera.h>
            \\#include <raymath.h>
            \\#include <rlgl.h>
        ),
    });
    translate_raylib.include_dirs.append(.{ .other_step = raylib }) catch @panic("OOM");
    translate_raylib.step.dependOn(&raylib.step);
    const raylib_mod = translate_raylib.createModule();
    raylib_mod.linkLibrary(raylib);
    mod.addImport("raylib", raylib_mod);

    const exe_check = b.addExecutable(.{ .name = "zoxel", .root_module = mod });
    const check = b.step("check", "Check if compiles");
    check.dependOn(&exe_check.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
