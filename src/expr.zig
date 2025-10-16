const std = @import("std");
const Complex = std.math.Complex;

const token = @import("token.zig");
const config = @import("config.zig");
const Evaluator = @import("Evaluator.zig");

pub const Oper = struct {
    left: ?*Expr,
    right: ?*Expr,
    op: token.TokenType,
};

pub const real_number_type = f64;

pub const Expr = union(enum) {
    invalid: void,
    nothing: void,
    operation: Oper,
    real_number: real_number_type,
    complex_number: Complex(real_number_type),
    boolean: bool,
    builtin_ident: []const u8,
    string: []const u8,
    identifier: []const u8,
    vector: []*Expr,
    integer: i64,
    //mml_type: ,// something here

    const Self = @This();
    pub const Kinds = @typeInfo(Expr).@"union".tag_type.?;

    pub fn init(val: anytype) Self {
        return switch (@TypeOf(val)) {
            real_number_type, comptime_float => .{ .real_number = val },
            Complex(real_number_type) => .{ .complex_number = val },
            bool => .{ .boolean = val },
            []const u8 => .{ .identifier = val },
            []*Expr => .{ .vector = val },
            i64 => .{ .integer = val },
            void => .{ .nothing = {} },
            else => blk: {
                std.debug.print("bruh what the heck is this type: {t}\n", .{val});
                break :blk .{ .invalid = {} };
            },
        };
    }

    pub const PrintExprError = error{ConfigHasNoWriter} || std.Io.Writer.Error;
    pub const PrintExprValueError = PrintExprError || Evaluator.EvalError;
    fn printRecurse(
        self: ?*const Self,
        config_: config.Config,
        indent: u32,
    ) PrintExprError!void {
        const writer = config_.writer orelse return PrintExprError.ConfigHasNoWriter;
        try printIndent(writer, indent);
        if (self == null) {
            try writer.writeAll("(null)");
            try writer.flush();
            return;
        }
        const expr = self.?;
        switch (expr.*) {
            .operation => {
                try writer.print("Operation(.{t},\n", .{expr.operation.op});

                try Expr.printRecurse(expr.operation.left, config_, indent+4);
                if (expr.operation.right) |right| {
                    try writer.writeAll(",\n");
                    try Expr.printRecurse(right, config_, indent+4);
                }

                try writer.writeAll(",\n");
                try printIndent(writer, indent);
                try writer.writeByte(')');
            },
            .real_number => try writer.print("Real({f})", .{expr}),
            .complex_number => try writer.print("Complex({f})", .{expr}),
            .boolean => try writer.print("Bool({f})", .{expr}),
            .identifier => try writer.print("Identifier('{s}'", .{expr.identifier}),
            .builtin_ident => try writer.print("BuiltinIdent('@{s}'", .{expr.builtin_ident}),
            .string => try writer.print("String('{s}'", .{expr.string}),
            .vector => {
                try writer.print("Vector(n={},\n", .{expr.vector.len});
                for (expr.vector) |e| {
                    try Expr.printRecurse(e, config_, indent+2);
                    try writer.writeAll(",\n");
                }
                try printIndent(writer, indent);
                try writer.writeByte(')');
            },
            .integer => try writer.print("Integer({f})", .{expr}),
            else => try writer.writeAll("(null)"),
        }

        try writer.flush();
    }
    pub fn print(self: *const Self, config_: config.Config) PrintExprError!void {
        try Expr.printRecurse(self, config_, 0);
    }

    pub fn printValue(self: Self, config_: config.Config) PrintExprValueError!void {
        const w = config_.writer orelse return error.ConfigHasNoWriter;
        switch (self) {
            .nothing => {},
            .real_number => try w.print("{d}", .{self.real_number}),
            .complex_number => try w.print("{d}{s}{d}i", .{
                self.complex_number.re,
                if (self.complex_number.im < 0) "-" else "+",
                @abs(self.complex_number.im),
            }),
            .boolean => {
                if (config_.bools_print_as_nums) {
                    try w.print("{d}", .{@as(real_number_type, @floatFromInt(@intFromBool(self.boolean)))});
                } else {
                    try w.writeAll(if (self.boolean) "true" else "false");
                }
            },
            .string => if (config_.quote_strings)
                try w.print("\"{s}\"", .{self.string})
            else
                try w.print("{s}", .{self.string}),
            .identifier => try w.print("{s}", .{self.identifier}),
            .vector => {
                if (config_.evaluator == null) {
                    std.log.err("called `printValue` without saving an evaluator in the config.\n", .{});
                    return;
                }
                var new_config = config_;
                new_config.quote_strings = true;

                try w.writeByte('[');
                for (self.vector, 0..) |e, i| {
                    const val = try config_.evaluator.?.eval(e);
                    try Expr.printValue(val, new_config);
                    if (i < self.vector.len - 1) try w.writeAll(", ");
                }
                try w.writeByte(']');
            },
            .integer => try w.print("{}", .{self.integer}),
            else => try w.writeAll("(null)"),
        }
    }

    // formats value-typed expressions (no operations, but also no vectors)
    pub fn format(
        self: Self,
        w: *std.Io.Writer,
    ) !void {
        if (self == .vector) return;
        const temp_config: config.Config = .{ .writer = w };
        self.printValue(temp_config) catch return;
    }

    pub const GetRealError = error{NotRealNumberExpression};
    pub const GetComplexError = error{NotComplexNumberExpression} || GetRealError;

    pub fn getReal(self: Self) GetRealError!real_number_type {
        return switch (self) {
            .boolean => @floatFromInt(@intFromBool(self.boolean)),
            .real_number => self.real_number,
            else => GetRealError.NotRealNumberExpression,
        };
    }
    pub fn getComplex(self: Self) GetComplexError!Complex(real_number_type) {
        return switch (self) {
            .complex_number => self.complex_number,
            .boolean, .real_number => Complex(real_number_type).init(try self.getReal(), 0),
            else => GetComplexError.NotComplexNumberExpression,
        };
    }

    pub fn isNumber(self: Self) bool {
        return self.isReal() or self.isComplex();
    }
    pub fn isReal(self: Self) bool {
        return self == .boolean or self == .real_number;
    }
    pub fn isComplex(self: Self) bool {
        return self == .complex_number;
    }

    pub fn searchFor(self: *Self, context: anytype, check_fn: fn (*const Self, context: @TypeOf(context)) bool) ?*Self {
        if (self.* == .operation) {
            if (self.operation.left.?.searchFor(context, check_fn)) |e| return e;
            if (self.operation.right) |r| {
                if (r.searchFor(context, check_fn)) |e| return e;
            }
        }
        if (check_fn(self, context))
            return self;
        return null;
    }
};

fn printIndent(w: *std.Io.Writer, indent: u32) !void {
    try w.print("{s: <[1]}", .{"", indent});
}

test "test test" {
    const k: Expr = .init(@as(real_number_type, 9.5));
    try std.testing.expect(try k.getReal() == 9.5);
    try std.testing.expect(try Expr.init(false).getReal() == 0.0);

    //try k.print(.{});

    //try config.default_config.writer.?.writeByte('\n');
    //try config.default_config.writer.?.flush();
}
