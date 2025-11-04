const std = @import("std");
const mml = @import("mml");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var write_buffer: [512]u8 = undefined;
    var file_writer = std.fs.File.stdout().writer(&write_buffer);
    const stdout = &file_writer.interface;

    var eval: mml.Evaluator = try .init(&arena, null);
    defer eval.deinit();

    var config: mml.Config = .{ .writer = stdout };
    eval.conf = &config;
    config.evaluator = &eval;

    const parsed = try mml.parse.parseExpr(&arena, "5 + 9cos{2.3}");
    const val = try eval.eval(parsed);
    try val.printValue(config);

    try stdout.flush();
}
