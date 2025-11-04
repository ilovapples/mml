const std = @import("std");

pub const StringContextInfo = struct {
    filename: []const u8,
    line: []const u8,
    line_num: usize,
    range_in_line: Range,
};

pub const Range = struct {
    index: usize,
    len: usize,

    pub fn slice(index: usize, len: usize) Range {
        return .{
            .index = index,
            .len = len,
        };
    }
    pub fn from(start: usize, end: usize) Range {
        return .{
            .index = start,
            .len = end - start,
        };
    }
};

pub const LogLevel = enum(u2) {
    Debug,
    Info,
    Warn,
    Error,
};

pub const tab_width = 8;
const terminate_ansi = "\x1b[0m";
pub fn printHighlightLineError(
    writer: *std.Io.Writer,
    log_level: LogLevel,
    comptime fmt: []const u8,
    fmt_args: anytype,
    context: StringContextInfo) void {
    const file_pos_color_ansi = "\x1b[38;5;242m";
    const line_num_color_ansi = "\x1b[38;5;248m";

    printErrorHeader(writer, log_level, fmt, fmt_args);

    writer.print("\n" ++ file_pos_color_ansi ++ " --> {s}:{d};{d}\n" ++ terminate_ansi, .{
        context.filename, context.line_num, context.range_in_line.index,
    }) catch return;

    writer.print(line_num_color_ansi ++ "{d: >5} | " ++ terminate_ansi, .{context.line_num}) catch return;
    var highlight_start_pos: usize = 0;
    for (context.line[0..context.range_in_line.index-1]) |c| {
        if (c == '\t') {
            writer.writeAll(" " ** tab_width) catch return;
            highlight_start_pos += tab_width;
        } else {
            writer.writeByte(c) catch return;
            highlight_start_pos += 1;
        }
    }

    const log_level_data = LogLevelData[@intFromEnum(log_level)];
    writer.writeAll(log_level_data.ansi) catch return;
    for (context.line[context.range_in_line.index-1..][0..context.range_in_line.len]) |c| {
        if (c == '\t') writer.writeAll(" " ** tab_width) catch return
        else writer.writeByte(c) catch return;
    }
    writer.writeAll(terminate_ansi) catch return;
    for (context.line[context.range_in_line.index-1 + context.range_in_line.len..]) |c| {
        if (c == '\t') writer.writeAll(" " ** tab_width) catch return
        else writer.writeByte(c) catch return;
    }
    writer.writeAll("\n" ++ line_num_color_ansi ++ "      | " ++ terminate_ansi) catch return;
    writer.print("{0s: <[1]}{2s}{3s:~<[4]}\n\n" ++ terminate_ansi, .{"", highlight_start_pos, log_level_data.ansi, "^", context.range_in_line.len}) catch return;
}

pub fn printErrorHeader(writer: *std.Io.Writer, log_level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    const log_level_data = LogLevelData[@intFromEnum(log_level)];
    
    writer.writeAll(log_level_data.ansi) catch return;
    writer.writeAll(log_level_data.start) catch return;
    writer.print(fmt ++ terminate_ansi, args) catch return;
}

pub const LogLevelCodes = struct {
    ansi: []const u8,
    start: []const u8,
};
/// index with @intFromEnum(log_level)
pub const LogLevelData: [4]LogLevelCodes = .{
    .{
        .ansi = "\x1b[38;5;255m",
        .start = "[DEBUG] ",
    },
    .{
        .ansi = "\x1b[38;5;81m",
        .start = "[INFO] ",
    },
    .{
        .ansi = "\x1b[38;5;214m",
        .start = "[WARN] ",
    },
    .{
        .ansi = "\x1b[38;5;9m",
        .start = "[ERROR] ",
    },
};
