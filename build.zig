const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options - consumers will override these
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Primary module for external consumption via zig fetch
    // Usage: const workers = @import("cf-workerz");
    _ = b.addModule("cf-workerz", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // For local development: WASM target for Cloudflare Workers
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // Create WASM module for testing
    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });

    // WASM executable for verification
    const wasm_exe = b.addExecutable(.{
        .name = "cf-workerz",
        .root_module = wasm_module,
    });

    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;

    const install_wasm = b.addInstallArtifact(wasm_exe, .{});

    // WASM build step
    const wasm_step = b.step("wasm", "Build WASM module for verification");
    wasm_step.dependOn(&install_wasm.step);

    // Default install
    b.getInstallStep().dependOn(&install_wasm.step);

    // Unit tests (native)
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
