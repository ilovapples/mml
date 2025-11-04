const std = @import("std");
const Build = std.Build;

const extern_pkg_path: []const u8 = "packages";

const out_name = "mml";

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "use-llvm", "use llvm? 'false' is not recommended for non-x86_64 targets");

    // PACKAGES
    // arg
    const arg_pkg_name: []const u8 = "arg_parse";
    const arg_pkg = b.createModule(.{
        .root_source_file = b.path(extern_pkg_path ++ "/" ++ arg_pkg_name ++ "/root.zig"),
        .target = target,
        .optimize = optimize,
    });


    const libmml_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // LIBMML LIBRARY (currently empty because it has no C exported functions)
    //const libmml = b.addLibrary(.{
    //    .name = "mml",
    //    .linkage = .static,
    //    .root_module = libmml_mod,
    //});

    //installArtifactOptions(b, libmml, .{
    //    .dest_dir = .{ .override = .{ .custom = "lib/" ++ out_name } },
    //});

    // MML EXECUTABLE
    const main = b.addExecutable(.{
        .name = out_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
    });

    //main.linkLibrary(libmml);
    main.root_module.addImport(arg_pkg_name, arg_pkg);
    const mibu_dep = b.dependency("mibu", .{});
    main.root_module.addImport("mibu", mibu_dep.module("mibu"));
    main.root_module.addImport("mml", libmml_mod);
    b.installArtifact(main);

    const run_main = b.addRunArtifact(main);

    const run_step = b.step("run", "run executable after building");
    run_step.dependOn(&run_main.step);


    const mod_tests = b.addTest(.{
        .root_module = libmml_mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

fn installArtifactOptions(
    b: *Build,
    artifact: *Build.Step.Compile,
    options: Build.Step.InstallArtifact.Options) void {
    b.getInstallStep().dependOn(&b.addInstallArtifact(artifact, options).step);
}
