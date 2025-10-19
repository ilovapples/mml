const std = @import("std");

const extern_pkg_path: []const u8 = "packages";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // PACKAGES
    // arg
    const arg_pkg_name: []const u8 = "arg_parse";
    const arg_pkg = b.createModule(.{
        .root_source_file = b.path(extern_pkg_path ++ "/" ++ arg_pkg_name ++ "/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // term_manip
    const term_manip_pkg_name: []const u8 = "term_manip";
    const term_manip_pkg = b.createModule(.{
        .root_source_file = b.path(extern_pkg_path ++ "/" ++ term_manip_pkg_name ++ "/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // LIBMML LIBRARY (currently empty because it has no C exported functions)
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

    // MML EXECUTABLE
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
    main.root_module.addImport(term_manip_pkg_name, term_manip_pkg);
    main.root_module.addImport("mml", libmml.root_module);
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
    //const install_and_test = b.step("test-and-build", "(doesn't work) Run tests and install "
    //    ++ "(same as `install` and `test` steps combined)");
    //install_and_test.dependOn(&main.step);
    //install_and_test.dependOn(&run_mod_tests.step);
}
