const std = @import("std");
const Io = std.Io;
const AtomicOrder = std.builtin.AtomicOrder;
const posix = std.posix;
const builtin = @import("builtin");

const mml = @import("mml");
const Expr = mml.expr.Expr;
const Config = mml.Config;
const parse = mml.parse;
const Evaluator = mml.Evaluator;

const mibu = @import("mibu");
const RawTerm = mibu.term.RawTerm;
const term = @import("term.zig");

const line_max_len = 512;

var history_buffer: [64][]const u8 = undefined;
var history_used: usize = 0; // may be larger than history_buffer.len; modulo is used to fit it in range
var history_pos: ?usize = null;
var history_saved_line: [line_max_len]u8 = undefined;

pub fn runPrompt(tty_reader: *std.fs.File.Reader, conf: *Config, original_term: *?RawTerm) !u8 {
    const prompt_str = ">> ";
    const tty_writer = conf.writer;

    if (conf.evaluator == null) {
        std.log.err("The config passed to this function must be supplied with an evaluator, "
                 ++ "in order to start the prompt.\n", .{});
        return 1;
    }
    const eval = conf.evaluator.?;
    const alloc = eval.arena_alloc;

    try tty_writer.writeAll(
        "MML Interactive Prompt 0.1.0 (zig ver.)\n"
     ++ "Type 'exit' or ctrl+d to quit the prompt\n"
     ++ "Type 'help' or '@help{}' for help.\n");

    try tty_writer.writeAll("\x1b[?25l");
    try tty_writer.flush();
    original_term.* = term.enableRawMode(tty_reader.file.handle) catch |e| if (e != error.NotATerminal) return e else null;
    while (true) {
        try tty_writer.writeAll(prompt_str);
        try tty_writer.flush();

        var line_buffer: [line_max_len]u8 = undefined;
        const line_len = try readLineRaw(
            tty_reader,
            tty_writer,
            &line_buffer,
            prompt_str,
        );
        if (line_len == null) break;
        if (line_len == 0) {
            try tty_writer.writeByte('\n');
            continue;
        }
        try tty_writer.writeByte('\n');
        try tty_writer.flush();

        var eval_finished = std.atomic.Value(bool).init(false);
        // start '...' loop to satisfy the user while the parser is parsing (because it's really slow in some cases)
        _ = try std.Thread.spawn(.{}, dotDotDotThread, .{ tty_writer, &eval_finished });

        // BEGIN LINE PARSING & EVALUATION
        const val = blk: {
            const start_parse_time = std.time.nanoTimestamp();
            // parse line into expressions
            const exprs = parse.parseStatements(@ptrCast(@alignCast(eval.arena_alloc.ptr)), line_buffer[0..line_len.?]) catch {
                eval_finished.store(true, AtomicOrder.release);
                break :blk Expr{ .invalid = {} };
            };
            const end_parse_time = std.time.nanoTimestamp();
            if (conf.debug_output) {
                try tty_writer.print("Parsed in {} ms\n", .{
                    @divTrunc(end_parse_time - start_parse_time, std.time.ns_per_ms)
                });
            }

            const start_eval_time = std.time.nanoTimestamp();
            // evaluate expressions
            var val: Expr = .{.invalid = {}};
            for (exprs) |e| {
                val = eval.eval(e) catch .{.invalid = {}};
            }
            const end_eval_time = std.time.nanoTimestamp();
            if (conf.debug_output) {
                try tty_writer.print("\rEvaluated in {} ms\n", .{
                    @divTrunc(end_eval_time - start_eval_time, std.time.ns_per_ms)
                });
            }

            eval_finished.store(true, AtomicOrder.release);
            break :blk val;
        };


        if (val == .code) {
            switch (val.code) {
                .Exit => break,
                .ClearScreen => try tty_writer.writeAll("\x1b[1;1f\x1b[2J"),
                .Help => {
                    _ = try mml.core.stdmml.builtin__help(eval, &.{});
                    try tty_writer.writeByte('\n');
                },
            }
            continue;
        }
        // strings should be quoted when printing from the prompt
        const saved_quote_strings = conf.quote_strings;
        conf.quote_strings = true;
        try val.printValue(conf.*);
        conf.quote_strings = saved_quote_strings;
        try tty_writer.writeByte('\n');

        conf.evaluator.?.last_val = val;

        if (history_used > history_buffer.len) alloc.free(history_buffer[history_used % history_buffer.len]);
        history_buffer[history_used % history_buffer.len] = try alloc.dupe(u8, line_buffer[0..line_len.?]);
        history_used += 1;
        history_pos = null;
    }

    for (if (history_used <= history_buffer.len) history_buffer[0..history_used] else history_buffer[0..]) |l| {
        alloc.free(l);
    }

    return 0;
}

fn readLineRaw(reader: *std.fs.File.Reader, stdout: *Io.Writer, out: []u8, prompt_str: []const u8) !?usize {
    const eof_char: u8 = 0x04;
    const backspace_char: u8 = 0x08;
    const delete_char: u8 = 0x7f;

    var cursor: usize = 0;
    var line_len: usize = 0;

    try drawLine(stdout, out[0..0], cursor, prompt_str);
    var seq = [_]u8{0} ** 11;
    var seq_pos: usize = 0;

    const r = &reader.interface;

    while (line_len >= cursor and line_len < out.len) {
        const c = r.takeByte() catch return null;

        const seq_is_empty = seq_pos == 0;
        const second_char_is_correct = 
            (seq_pos == 1 and c == '[') or
            (seq_pos > 1 and seq[1] == '[') or
            (seq_pos == 1 and (c == 'b' or c == 'f'));
        const is_esc_seq_char = (seq_is_empty and c == 0x1b) or second_char_is_correct;
        if (is_esc_seq_char) {
            seq[seq_pos] = c;
            seq_pos += 1;

            // seq[seq_pos-1] = c, c is not yet reset
            const is_extra_short_seq = seq_pos == 2 and (c == 'b' or c == 'f');
            const is_short_seq = seq_pos == 3 and (c >= 'A' and c <= 'D');
            const is_medium_seq = seq_pos == 4 and seq[2] == '3';
            const is_long_seq = seq_pos == 6 and seq[2] == '1';
            const is_good_len = (is_extra_short_seq or is_short_seq or is_medium_seq or is_long_seq);
            if (is_good_len and seq[0] == 0x1b and (seq[1] == '[' or is_extra_short_seq)) {
                _ = handleEscapeSequence(seq[0..seq_pos], out.ptr, &line_len, &cursor);
                seq_pos = 0;
                try drawLine(stdout, out[0..line_len], cursor, prompt_str);
                continue;
            }

            if (seq_pos >= seq.len-1) seq_pos = 1;
            continue;
        }

        if (c == '\n') {
            //try stdout.writeByte('\n');
            break;
        } else if (c == eof_char) {
            return null;
        } else if (c == delete_char or c == backspace_char) {
            deleteChar(out, &cursor, &line_len);
        } else if (std.ascii.isPrint(c)) {
            insertChar(out, &cursor, &line_len, c);
        }

        try drawLine(stdout, out[0..line_len], cursor, prompt_str);
    }

    return line_len;
}

fn drawLine(stdout: *Io.Writer, line: []const u8, cursor_pos: usize, prompt_str: []const u8) !void {
    try stdout.writeAll("\r\x1b[0K");
    try stdout.writeAll(prompt_str);
    try stdout.writeAll(line);
    try stdout.print("\r\x1b[{}C\x1b[?25h", .{prompt_str.len + cursor_pos});
    try stdout.flush();
}

fn handleEscapeSequence(seq: []u8, line: [*]u8, line_len: *usize, cursor: *usize) bool {
    const UP_C = "A";
    const DOWN_C = "B";
    const RIGHT_C = "C";
    const LEFT_C = "D";
    const START_ANSI = "\x1b[";
    const CTRL_ANSI = "\x1b[1;5";
    const ALT_ANSI = "\x1b[1;3";
    const ALT_LEFT = "\x1bb";
    const ALT_RIGHT = "\x1bf";

    if (std.mem.eql(u8, seq, START_ANSI ++ LEFT_C)) { // if LEFT
        if (cursor.* > 0) cursor.* -= 1; // go left
    } else if (std.mem.eql(u8, seq, START_ANSI ++ RIGHT_C)) { // if RIGHT
        if (cursor.* < line_len.*) cursor.* += 1; // go right
    } else if (std.mem.eql(u8, seq, ALT_LEFT) // if ALT+LEFT
            or std.mem.eql(u8, seq, ALT_ANSI ++ LEFT_C) // or ALT+LEFT (other test)
            or std.mem.eql(u8, seq, CTRL_ANSI ++ LEFT_C)) { // or CTRL+LEFT
        cursor.* = 0; // go all the way left
    } else if (std.mem.eql(u8, seq, ALT_RIGHT) // if ALT+RIGHT
            or std.mem.eql(u8, seq, ALT_ANSI ++ RIGHT_C) // or ALT+RIGHT (other test)
            or std.mem.eql(u8, seq, CTRL_ANSI ++ RIGHT_C)) { // or CTRL+RIGHT
        cursor.* = line_len.*; // go all the way right
    } else if (std.mem.eql(u8, seq, START_ANSI ++ "3~")) { // if DEL
        if (line_len.* > cursor.*) {
            @memmove(line + cursor.*, line[cursor.* + 1..line_len.*]);
            line_len.* -= 1;
        } else if (line_len.* > 0) {
            line_len.* -= 1;
            cursor.* = line_len.*;
        } else return false;
    } else if (std.mem.eql(u8, seq, START_ANSI ++ UP_C)) { // if UP, go back in history
        if (history_used == 0) return false;

        if (history_pos == null or history_pos.? == 0) {
            history_pos = history_used-1;
        } else {
            history_pos.? -= 1;
        }
        const hist_line = history_buffer[history_pos.?];
        //@memcpy(history_saved_line[0..line_len.*], line);
        //@memset(history_saved_line[line_len.*..], 0);
        @memcpy(line, hist_line);
        line_len.* = hist_line.len;
        cursor.* = hist_line.len;
        if (false) { // some debug stuf
            std.debug.print("\ngoing up", .{});
            std.debug.print("history_used = {}", .{history_used});
            std.debug.print("history_pos = {?}", .{history_pos});
        }
    } else if (std.mem.eql(u8, seq, START_ANSI ++ DOWN_C)) { // if DOWN, go forward in history
        // this is not implemented yet (it will be!)
    } else return false;

    return true;
}

fn deleteChar(line: []u8, cursor: *usize, line_len: *usize) void {
    if (cursor.* == 0) return;

    @memmove(line.ptr + cursor.* - 1, line[cursor.*..line_len.*]);

    cursor.* -= 1;
    line_len.* -= 1;
}

fn insertChar(line: []u8, cursor: *usize, line_len: *usize, c: u8) void {
    if (line_len.* >= line.len - 1) return;

    @memmove(line.ptr + cursor.* + 1, line[cursor.*..line_len.*]);
    line[cursor.*] = c;

    cursor.* += 1;
    line_len.* += 1;
}

fn dotDotDotThread(w: *Io.Writer, eval_finished: *const std.atomic.Value(bool)) void {
    std.Thread.sleep(1*std.time.ns_per_ms);

    var step: u2 = 1;
    while (!eval_finished.load(AtomicOrder.acquire)) : (step +%= 1) {
        if (step == 0) {
            step = 1;
            w.writeAll("\r\x1b[K") catch {};
        }
        w.writeByte('.') catch {};
        w.flush() catch {};
        std.Thread.sleep(std.time.ns_per_s / 3);
    }
    w.writeByte('\r') catch {};
}
