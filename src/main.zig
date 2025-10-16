const std = @import("std");
const mml = @import("root.zig");

const Config = mml.config.Config;
const Expr = mml.expr.Expr;
const parser = mml.parser;
const Evaluator = mml.Evaluator;

pub fn main() !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    var my_config: Config = .{
        .writer = stdout,
    };

    var eval = try Evaluator.init(allocator, &my_config);
    defer eval.deinit();

    my_config.evaluator = &eval;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const expr_str: []const u8 = if (args.len > 1) args[1] else "(3+9^2) * 15";

    const exprs = try parser.parseStatements(expr_str, allocator);

    var val: Expr = Expr{.invalid = {}};
    for (exprs) |e| {
        val = eval.eval(e) catch Expr{.invalid = {}};
    }
    try val.printValue(my_config);

    try stdout.flush();
}
