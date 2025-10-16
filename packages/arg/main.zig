const std = @import("std");
const ArgParse = @import("test.zig").ArgParser;

pub fn main() !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    var argparser = try ArgParse.parse(alloc, args);
    defer argparser.deinit();

    const yes = argparser.option(bool, "yes", "hi") orelse false;
    const name = argparser.option([]const u8, "name", "your name") orelse "default name";

    if (!argparser.finalize()) return;

    std.debug.print("yes = {}\n", .{yes});
    std.debug.print("Hello, {s}!\n", .{name});

    argparser.printUsage(stdout);
    //argparser.printFields();

    try stdout.flush();
}
