const std = @import("std");
const Io = std.Io;
const posix = std.posix;

const ArgParser = @import("arg_parse").ArgParser;

const mml = @import("mml");
const Config = mml.Config;
const Expr = mml.expr.Expr;
const parse = mml.parse;
const Evaluator = mml.Evaluator;

const mibu = @import("mibu");
const prompt = @import("prompt.zig");

var stdout_w: *Io.Writer = undefined;
var stdin_reader: std.fs.File.Reader = undefined;
var original_term: ?mibu.term.RawTerm = null;

pub fn main() !void {
    // I/O setup
    var stdin_buffer: [512]u8 = undefined;
    stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    stdout_w = &stdout_writer.interface;

    // signal handler setup for SIGINT (Ctrl+C/^C)
    posix.sigaction(posix.SIG.INT, &.{
        .handler = .{ .handler = interruptHandler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    }, null);

    // arena & allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // argument parsing
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var pa = ArgParser.parse(allocator, args) catch |err| switch (err) {
        error.OutOfMemory => @panic("OOM"),
        error.ArgumentError => {
            std.log.err("failed due to argument error", .{});
            std.process.exit(2);
        },
    };
    defer pa.deinit();
    pa.usage_initial_message =
        "mml-zig is a Zig rewrite of the MML mathematical scripting language project.\n" ++
        "the default action, if none are specified, is to open the REPL (like '--repl' or '-R')\n";

    const expr_str = pa.longShortOption([]const u8, "expr", 'E', "the expression to evaluate");
    const start_repl = pa.longShortOption(bool, "repl", 'R', "use an interactive prompt (REPL)") orelse false;

    // config
    var conf: Config = .{
        .writer = stdout_w,
    };

    conf.debug_output = pa.longShortOption(bool, "debug", 'd', "enable debug output across the program") orelse false;

    conf.bools_print_as_nums = pa.option(bool, "bools-are-nums", "if set, Booleans print as 1 or 0 instead of as true or false") orelse false;
    conf.decimal_precision = pa.option(u32, "precision", "(WARNING: unused) precision to use when displaying decimals") orelse 6;
    conf.quote_strings = pa.option(bool, "quote-strings", "if set, strings print surrounded by double quotes") orelse false;

    const mml_consts_opt = pa.option(bool, "mml-consts", "display list of provided constants in MML") orelse false;
    const mml_funcs_opt = pa.option(bool, "mml-funcs", "display list of provided functions in MML") orelse false;
    const print_usage = pa.longShortOption(bool, "help", 'h', "display usage information") orelse false;

    if (!pa.finalize()) {
        try stdout_w.writeByte('\n');
        pa.printUsage(stdout_w);
        try stdout_w.flush();
        std.process.exit(1);
    }

    if (print_usage) {
        pa.printUsage(stdout_w);
        try stdout_w.flush();
        std.process.exit(1);
    }

    // evaluator
    var eval = try Evaluator.init(&arena, &conf);
    defer eval.deinit();

    conf.evaluator = &eval;

    if (mml_consts_opt) {
        eval.printConstantsList(stdout_w);
        try stdout_w.flush();
        return;
    }
    if (mml_funcs_opt) {
        eval.printFuncsList(stdout_w);
        try stdout_w.flush();
        return;
    }

    if (start_repl or expr_str == null) {
        defer if (original_term) |*ot| ot.disableRawMode() catch {};

        const res = try prompt.runPrompt(&stdin_reader, &conf, &original_term);

        try stdout_w.writeAll("\x1b[0 q\x1b[?25h");
        try stdout_w.flush();

        if (res != 0) std.process.exit(1)
            else return;
    }

    // parsing & evaluating
    const exprs = parse.parseStatements(&arena, expr_str.?) catch {
        std.log.err("failed to parse expressions from source: '{s}'\n", .{expr_str.?});
        return;
    };

    var val: Expr = .{.invalid = {}};
    for (exprs) |e| {
        val = eval.eval(e) catch .{.invalid = {}};
    }
    try val.printValue(conf);

    try stdout_w.flush();
}

const its_ok_to_print_in_signal_handler = true;
fn interruptHandler(signum: i32) callconv(.c) void {
    if (original_term) |*ot| {
        ot.disableRawMode() catch {};
    }
    stdout_w.writeAll("\x1b[?25h") catch {}; // make cursor visible

    if (its_ok_to_print_in_signal_handler) {
        stdout_w.print("terminated with signum {}", .{signum}) catch {};
        switch (signum) {
            posix.SIG.INT => stdout_w.writeAll(": Ctrl+C interrupt") catch {},
            else => {},
        }
        stdout_w.writeByte('\n') catch {};
        stdout_w.flush() catch {};
    }

    std.process.exit(2);
}
