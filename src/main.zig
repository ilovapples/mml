const std = @import("std");
const mml = @import("root.zig");
const arg_parse = @import("arg_parse");
const ArgParser = arg_parse.ArgParser;

const Config = mml.config.Config;
const Expr = mml.expr.Expr;
const parser = mml.parser;
const Evaluator = mml.Evaluator;

pub fn main() !void {
    // stdout writer
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // allocators
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const gpa_alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    // config
    var my_config: Config = .{
        .writer = stdout,
    };

    // evaluator
    var eval = try Evaluator.init(allocator, &my_config);
    defer eval.deinit();

    my_config.evaluator = &eval;

    // arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var arg_parser = try ArgParser.parse(allocator, args);
    defer arg_parser.deinit();

    const expr_str = arg_parser.option([]const u8, "expr", "the expression to evaluate") orelse "(3+9^2) * 15";
    const print_usage = arg_parser.option(bool, "help", "display usage information") orelse false;
    if (print_usage) {
        arg_parser.printUsage(stdout);
        try stdout.flush();
        std.process.exit(1);
    }

    if (!arg_parser.finalize()) std.process.exit(1);

    // parsing & evaluating
    const exprs = try parser.parseStatements(expr_str, allocator);

    var val: Expr = Expr{.invalid = {}};
    for (exprs) |e| {
        val = eval.eval(e) catch Expr{.invalid = {}};
    }
    try val.printValue(my_config);

    try stdout.flush();
}
