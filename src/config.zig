const std = @import("std");

const token = @import("token.zig");
const Evaluator = @import("Evaluator.zig");

pub const Config = struct {
    const Self = @This();

    program_name: ?[]const u8 = null,

    evaluator: ?*Evaluator = null,

    writer: ?*std.Io.Writer = null,

    decimal_precision: u32 = 6,
    bools_print_as_nums: bool = false,
    quote_strings: bool = false,
};

pub const default_config: Config = .{};
