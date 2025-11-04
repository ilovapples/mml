const std = @import("std");

const mml = @import("root.zig");
const token = mml.token;
const Evaluator = mml.Evaluator;

program_name: ?[]const u8 = null,

evaluator: ?*Evaluator = null,

writer: *std.Io.Writer,

decimal_precision: u32 = 6, // unused
bools_print_as_nums: bool = false,
quote_strings: bool = false,

debug_output: bool = false,
