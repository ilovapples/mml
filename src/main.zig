const std = @import("std");
const Io = std.Io;
const IoLimit = Io.Limit;
const linux = std.os.linux;

const ArgParser = @import("arg_parse").ArgParser;

const mml = @import("mml");
const Config = mml.config.Config;
const Expr = mml.expr.Expr;
const parser = mml.parser;
const Evaluator = mml.Evaluator;

pub fn main() !void {
    // I/O setup
    //var stdin_buffer: [512]u8 = undefined;
    //var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // arena & allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    // arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var arg_parser = try ArgParser.parse(allocator, args);
    defer arg_parser.deinit();

    const expr_str = arg_parser.option([]const u8, "expr", "the expression to evaluate") orelse "(3+9^2) * 15";
    
    // config
    var my_config: Config = .{
        .writer = stdout,
    };

    if (arg_parser.option(bool, "repl", "(not fully implemented) use an interactive prompt (REPL)") orelse false) {
        @panic("REPL is not fully implemented, so you can't use it yet");
        //try runPrompt(&stdin_reader, stdout);
        //return;
    }
    my_config.bools_print_as_nums = arg_parser.option(bool,
        "bools-are-nums", "if set, Booleans print as 1 or 0 instead of as true or false") orelse false;
    my_config.decimal_precision = arg_parser.option(u32,
        "precision", "(WARNING: unused) precision to use when displaying decimals") orelse 6;
    my_config.quote_strings = arg_parser.option(bool,
        "quote-strings", "if set, strings print surrounded by double quotes") orelse false;

    const print_usage = arg_parser.option(bool, "help", "display usage information") orelse false;
    if (print_usage) {
        arg_parser.printUsage(stdout);
        try stdout.flush();
        std.process.exit(1);
    }

    // evaluator
    var eval = try Evaluator.init(allocator, &my_config);
    defer eval.deinit();

    my_config.evaluator = &eval;

    if (!arg_parser.finalize()) {
        try stdout.writeByte('\n');
        arg_parser.printUsage(stdout);
        try stdout.flush();
        std.process.exit(1);
    }

    // parsing & evaluating
    const exprs = parser.parseStatements(expr_str, allocator) catch {
        std.log.err("failed to parse expressions from source: '{s}'\n", .{expr_str});
        return;
    };

    var val: Expr = Expr{.invalid = {}};
    for (exprs) |e| {
        val = eval.eval(e) catch Expr{.invalid = {}};
    }
    try val.printValue(my_config);

    try stdout.flush();
}

fn runPrompt(stdin_reader: *std.fs.File.Reader, stdout: *Io.Writer) !void {
    const prompt_str = ">> ";

    try stdout.writeAll(
        "MML Interactive Prompt 0.1.0 (zig ver.)\n"
     ++ "Type 'exit'+Enter or ctrl+d to quit the prompt\n");

    try stdout.writeAll(prompt_str);
    try stdout.flush();

    var line_buffer: [512]u8 = undefined;
    const line_len = try readLine(stdin_reader, &line_buffer);
 
    try stdout.print("buf: '{s}'\n", .{line_buffer[0..line_len]});

    try stdout.flush();
}

fn readLine(reader: *std.fs.File.Reader, out: []u8) !usize {
    var w = Io.Writer.fixed(out[0..]);
    const r = &reader.interface;
    linux.tcgetattr(reader.file.handle, );
    return r.streamDelimiterLimit(&w, '\n', IoLimit.limited(out.len));
}

var saved_termios: ?linux.termios = null;
fn setTerminalRawMode(file: *const std.fs.File) void {
    linux.tcgetattr(file.handle, &(saved_termios.?));
    var new_termios = saved_termios.?;
}
