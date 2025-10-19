const std = @import("std");

const token = @import("token.zig");
const Evaluator = @import("Evaluator.zig");

pub const Config = struct {
    const Self = @This();

    program_name: ?[]const u8 = null,

    evaluator: ?*Evaluator = null,

    writer: *std.Io.Writer,

    decimal_precision: u32 = 6, // unused
    bools_print_as_nums: bool = false,
    quote_strings: bool = false,

    debug_output: bool = false,
};
