const std = @import("std");

const extern_pkg_path: []const u8 = "packages";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // arg
    const arg_pkg_name: []const u8 = "arg_parse";
    const arg_pkg = b.createModule(.{
        .root_source_file = b.path(extern_pkg_path ++ "/arg_parse/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const libmml = b.addLibrary(.{
        .name = "mml",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(libmml);

    const main = b.addExecutable(.{
        .name = "mml_main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    main.linkLibrary(libmml);
    main.root_module.addImport(arg_pkg_name, arg_pkg);
    b.installArtifact(main);

    const run_main = b.addRunArtifact(main);

    const run_step = b.step("run", "run executable after building");
    run_step.dependOn(&run_main.step);


    const mod_tests = b.addTest(.{
        .root_module = libmml.root_module,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    //libmml.step.dependOn(test_step);
}
