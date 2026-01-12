const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // WASM target for Cloudflare Workers
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Get the cf-workerz dependency
    const workers_dep = b.dependency("cf_workerz", .{
        .target = wasm_target,
        .optimize = optimize,
    });

    // Create root module for WASM build
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });

    // Add the cf-workerz module import
    root_module.addImport("cf-workerz", workers_dep.module("cf-workerz"));

    // Create the WASM executable
    const exe = b.addExecutable(.{
        .name = "worker",
        .root_module = root_module,
    });

    // WASM-specific settings
    exe.entry = .disabled;
    exe.rdynamic = true;

    // Install the WASM artifact
    b.installArtifact(exe);
}
