const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const assert = std.debug.assert;

pub const ArgParser = struct {
    alloc: std.mem.Allocator,
    parsed_long_args: std.StringHashMap([]const u8),
    /// lowercase letters stored in [0..26], uppercase in [26..52]
    parsed_short_args: [26*2]?[]const u8 = .{null} ** 52,
    parsed_pos_args: std.ArrayList(?[]const u8),
    requested_args: std.ArrayList(ArgumentOptions),
    dashdash_pos: ?usize = null,
    program_name: []const u8,

    usage_column_2: usize = 30,
    usage_initial_message: ?[]const u8 = null,

    pub const ArgumentOptions = struct {
        type_str: ?[]const u8,
        long: ?[]const u8 = null,
        short: ?u8 = null,
        desc: []const u8,
    };

    const Self = @This();
    
    pub fn parse(allocator: std.mem.Allocator, args: []const [:0]u8) !Self {
        // pa is not fully initialized until the end of this function body
        var pa = Self{
            .alloc = allocator,
            .parsed_long_args = .init(allocator),
            .parsed_pos_args = .empty,
            .requested_args = .empty,
            .program_name = args[0],
        };

        var consume_next: bool = false;
        for (args[1..], 1..) |cur, i| {
            if (consume_next) {
                consume_next = false;
                continue;
            }
            if (std.mem.eql(u8, cur[0..2], "--")) { // long fields like --field
                const eql_idx = std.mem.indexOfScalar(u8, cur, '=');
                if (eql_idx) |delim| { // --field=value
                    const up_to = cur[2..delim];
                    if (up_to.len != 0) {
                        try pa.parsed_long_args.put(up_to, cur[delim+1..]);
                    }
                } else if (cur.len > 2) { // --field value
                    if (i >= args.len - 1
                        or (args[i+1].len > 2
                            and std.mem.eql(u8, args[i+1][0..2], "--"))) { // '--field' means a true boolean
                        try pa.parsed_long_args.put(cur[2..], &.{});
                    } else { // `--field value`
                        try pa.parsed_long_args.put(cur[2..], args[i+1]);
                        consume_next = true;
                    }
                } else {
                    pa.dashdash_pos = i;
                }
            } else if (cur[0] == '-') { // short fields like 
                for (cur[1..], 1..) |c, ci| {
                    if (shortOptionLetterStorageIndex(c)) |idx| {
                        if (ci == cur.len-1 and i < args.len-1) {
                            pa.parsed_short_args[idx] = args[i+1];
                            consume_next = true;
                        } else {
                            pa.parsed_short_args[idx] = "true";
                        }
                    } else {
                        warnArgError(null, "non-alphabetic short-form option '-{c}' is not allowed", .{c});
                        return error.ArgumentError;
                    }
                }
            } else {
                try pa.parsed_pos_args.append(pa.alloc, args[i]);
            }
        }

        return pa;
    }
    fn shortOptionLetterStorageIndex(letter: u8) ?usize {
        if (!ascii.isAlphabetic(letter)) return null;
        return if (ascii.isLower(letter)) letter - 'a' else letter - 'A';
    }

    pub fn deinit(pa: *Self) void {
        pa.parsed_long_args.deinit();
        pa.parsed_pos_args.deinit(pa.alloc);
        pa.requested_args.deinit(pa.alloc); }

    pub fn option(
        pa: *Self,
        comptime T: type,
        comptime name: []const u8,
        comptime desc: []const u8) ?T {
        pa.requested_args.append(pa.alloc, .{
            .type_str = if (T == bool) null else if (T == []const u8) "[string]" else "[" ++ @typeName(T) ++ "]",
            .long = name,
            .desc = desc,
        }) catch return null;

        const str_val = pa.parsed_long_args.fetchRemove(name) orelse return null;

        return getTypeFromString(T, str_val.value);
    }

    pub fn posOption(pa: *Self, index: usize) ?[]const u8 {
        if (index >= pa.parsed_pos_args.items.len or pa.parsed_pos_args.items[index] == null) {
            return null;
        }
        defer pa.parsed_pos_args.items[index] = null;
        return pa.parsed_pos_args.items[index];
    }

    /// specify a short option like '-h' or '-l'. 
    /// if assoc_long_name is not null, desc must be null. the opposite is true as well.
    pub fn shortOption(
        pa: *Self,
        comptime T: type,
        comptime letter: u8,
        comptime desc: ?[]const u8,
        comptime assoc_long_name: ?[]const u8) ?T {
        comptime {
            if (desc == null and assoc_long_name == null) {
                @compileError("if an associated long name is not specified for a short option, a description must be explicitly specified.");
            } else if (desc != null and assoc_long_name != null) {
                @compileError("if an associated long name is specified for a short option, the description associated to that long name must be used for the short option.");
            }
        }
        if (assoc_long_name) |long| {
            for (pa.requested_args.items) |*e| {
                if (e.long != null and std.mem.eql(u8, e.long.?, long)) {
                    e.short = letter;
                    break;
                }
            } else {
                warnArgError(null,
                    "short option '-{c}' is supposed to be associated with " ++
                    "long option '--{s}', but it doesn't exist", .{letter, long});
            }
        } else {
            pa.requested_args.append(pa.alloc, .{
                .type_str = if (T == bool) null else if (T == []const u8) "[string]" else "[" ++ @typeName(T) ++ "]",
                .short = letter,
                .desc = desc.?,
            }) catch return null;
        }

        const idx = comptime shortOptionLetterStorageIndex(letter);
        comptime if (idx == null) @compileError("short-form options must be a letter");


        defer pa.parsed_short_args[idx.?] = null;
        return getTypeFromString(T, pa.parsed_short_args[idx.?] orelse return null);
    }

    fn getTypeFromString(comptime T: type, str: []const u8) ?T {
        return switch (@typeInfo(T)) {
            .int => std.fmt.parseInt(T, str, 10) catch null,
            .float => std.fmt.parseFloat(T, str) catch null,
            .bool => blk: {
                if (str.len == 0) break :blk true;
                if (std.mem.eql(u8, str, "true")) break :blk true;
                if (std.mem.eql(u8, str, "false")) break :blk false;
                break :blk null;
            },
            .pointer => if (T == []const u8) str else null,
            else => null,
        };
    }

    pub fn finalize(pa: Self) bool {
        var stderr_buffer: [512]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        const stderr = &stderr_writer.interface;

        var ret = true;
        if (pa.parsed_long_args.count() > 0) {
            warnArgError(stderr, "found unidentified long-form argument(s) with values:\n", .{});
            pa.printLongArgs(stderr);
            stderr.print("\n", .{}) catch return ret;
            ret = false;
        }
        {
            var unknown_positional_arg_found = false;
            for (pa.parsed_pos_args.items, 1..) |a, i| {
                if (a != null) {
                    if (!unknown_positional_arg_found) {
                        defer unknown_positional_arg_found = true;
                        warnArgError(stderr, "found unidentified positional argument(s):\n", .{});
                    }
                    stderr.print("'{s}' at position {d}\n", .{a.?, i}) catch return ret;
                    ret = false;
                }
            }
        }
        {
            var unknown_short_arg_found = false;
            for (pa.parsed_short_args, 0..) |a, i| {
                if (a != null) {
                    if (!unknown_short_arg_found) {
                        defer unknown_short_arg_found = true;
                        warnArgError(stderr, "found unidentified short argument(s): ", .{});
                    }
                    const i_u8: u8 = @intCast(i);
                    stderr.print("-{c}, ", .{if (i < 26) i_u8 + 'a' else i_u8 + 'A'}) catch return ret;
                    ret = false;
                }
            }
            if (unknown_short_arg_found) stderr.writeByte('\n') catch return ret;
        }

        if (!ret) stderr.flush() catch {};

        return ret;
    }

    fn warnArgError(writer: ?*std.Io.Writer, comptime fmt: []const u8, args: anytype) void {
        // yes, the extra newline with std.log.warn was intended
        if (writer) |w| w.print("warning: argument error: " ++ fmt, args) catch return
        else std.log.warn("argument error: " ++ fmt, args);
    }

    pub fn printLongArgs(self: Self, w: *std.Io.Writer) void {
        var it = self.parsed_long_args.iterator();
        while (it.next()) |e| {
            w.print("'--{s}{s}{s}', ", .{e.key_ptr.*, if (e.value_ptr.len == 0) "" else " ", e.value_ptr.*}) catch return;
        }
    }

    pub fn longShortOption(
        pa: *Self,
        comptime T: type,
        comptime long_name: []const u8,
        comptime short_letter: u8,
        comptime desc: []const u8) ?T {
        const long_option = pa.option(T, long_name, desc);
        const short_option = pa.shortOption(T, short_letter, null, long_name);
        return long_option orelse short_option;
    }
    
    pub fn printUsage(pa: Self, writer: *std.Io.Writer) void {
        writer.print("usage: {s} [options]\n", .{pa.program_name}) catch return;
        if (pa.usage_initial_message) |msg| writer.writeAll(msg) catch return;

        if (pa.requested_args.items.len > 0) {
            writer.writeAll("\nOptions:\n") catch return;

            for (pa.requested_args.items) |item| {
                writer.writeAll("  ") catch return;
                if (item.long) |long| {
                    if (item.type_str != null and item.short == null) {
                        writer.print("--{s} {s}", .{long, item.type_str.?}) catch return;
                    } else {
                        writer.print("--{s}", .{long}) catch return;
                    }
                }
                if (item.short) |short| {
                    if (item.type_str) |t| {
                        writer.print("{s}-{c} {s}", .{if (item.long) |_| ", " else "", short, t}) catch return;
                    } else {
                        writer.print("{s}-{c}", .{if (item.long) |_| ", " else "", short}) catch return;
                    }
                }
                writer.print("\x1b[{}G{s}", .{pa.usage_column_2, item.desc}) catch return;
                writer.writeByte('\n') catch return;
            }
        }
    }
};
