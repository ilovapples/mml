const std = @import("std");
const Complex = std.math.Complex;

const token = @import("token.zig");
const config_mod = @import("config.zig");
const Evaluator = @import("Evaluator.zig");

pub const Oper = struct {
    left: ?*Expr,
    right: ?*Expr,
    op: token.TokenType,
};

pub const Expr = union(enum) {
    invalid: void,
    nothing: void,
    code: Code,
    operation: Oper,
    real_number: f64,
    complex_number: Complex(f64),
    boolean: bool,
    builtin_ident: []const u8,
    string: []const u8,
    identifier: []const u8,
    vector: []*Expr,
    integer: i64,

    pub const Code = enum(usize) {
        Exit,
        ClearScreen,
    };

    const Self = @This();
    pub const Kinds = @typeInfo(Expr).@"union".tag_type.?;

    pub fn init(val: anytype) Self {
        return switch (@TypeOf(val)) {
            f64, comptime_float => .{ .real_number = val },
            Complex(f64) => .{ .complex_number = val },
            bool => .{ .boolean = val },
            []const u8 => .{ .identifier = val },
            []*Expr => .{ .vector = val },
            i64 => .{ .integer = val },
            void => .{ .nothing = {} },
            else => @compileError("can't construct an Expr from a value of this type: " ++ @typeName(@TypeOf(val))),
        };
    }

    fn printRecurse(
        self: ?*const Self,
        config: config_mod.Config,
        indent: u32,
    ) void {
        const w = config.writer;
        printIndent(w, indent);
        if (self == null) {
            w.writeAll("(null)") catch return;
            w.flush() catch return;
            return;
        }
        const unwrapped_expr = self.?;
        switch (unwrapped_expr.*) {
            .operation => {
                w.print("Operation(.{t},\n", .{unwrapped_expr.operation.op}) catch return;

                Expr.printRecurse(unwrapped_expr.operation.left, config, indent+4);
                if (unwrapped_expr.operation.right) |right| {
                    w.writeAll(",\n") catch return;
                    Expr.printRecurse(right, config, indent+4);
                }

                w.writeAll(",\n") catch return;
                printIndent(w, indent);
                w.writeByte(')') catch return;
            },
            .real_number => w.print("Real({f})", .{unwrapped_expr}) catch return,
            .complex_number => w.print("Complex({f})", .{unwrapped_expr}) catch return,
            .boolean => w.print("Bool({f})", .{unwrapped_expr}) catch return,
            .identifier => w.print("Identifier('{s}')", .{unwrapped_expr.identifier}) catch return,
            .builtin_ident => w.print("BuiltinIdent('@{s}')", .{unwrapped_expr.builtin_ident}) catch return,
            .string => w.print("String('{s}')", .{unwrapped_expr.string}) catch return,
            .vector => {
                w.print("Vector(n={},\n", .{unwrapped_expr.vector.len}) catch return;
                for (unwrapped_expr.vector) |e| {
                    Expr.printRecurse(e, config, indent+4);
                    w.writeAll(",\n") catch return;
                }
                printIndent(w, indent);
                w.writeByte(')') catch return;
            },
            .integer => w.print("Integer({f})", .{unwrapped_expr}) catch return,
            .code => w.print("Code(.{t})", .{unwrapped_expr.code}) catch return,
            else => w.writeAll("(null)") catch return,
        }

        w.flush() catch return;
    }
    pub fn print(self: *const Self, config: config_mod.Config) void {
        Expr.printRecurse(self, config, 0);
    }

    pub fn printValue(self: Self, config: config_mod.Config) Evaluator.EvalError!void {
        const w = config.writer;
        switch (self) {
            .nothing => {},
            .real_number => w.print("{d}", .{self.real_number}) catch return,
            .complex_number => w.print("{d}{s}{d}i", .{
                self.complex_number.re,
                if (self.complex_number.im < 0) "-" else "+",
                @abs(self.complex_number.im),
            }) catch return,
            .boolean => {
                if (config.bools_print_as_nums) {
                    w.print("{d}", .{@as(f64, @floatFromInt(@intFromBool(self.boolean)))}) catch return;
                } else {
                    w.writeAll(if (self.boolean) "true" else "false") catch return;
                }
            },
            .string => if (config.quote_strings)
                w.print("\"{s}\"", .{self.string}) catch return
            else
                w.print("{s}", .{self.string}) catch return,
            .identifier => w.print("{s}", .{self.identifier}) catch return,
            .vector => {
                if (config.evaluator == null) {
                    std.log.err("called `printValue` without saving an evaluator in the config.\n", .{});
                    return;
                }
                var new_config = config;
                new_config.quote_strings = true;

                w.writeByte('[') catch return;
                for (self.vector, 0..) |e, i| {
                    const val = try config.evaluator.?.eval(e);
                    try Expr.printValue(val, new_config);
                    if (i < self.vector.len - 1) w.writeAll(", ") catch return;
                }
                w.writeByte(']') catch return;
            },
            .integer => w.print("{}", .{self.integer}) catch return,
            .code => w.print(".{t}", .{self.code}) catch return,
            else => w.writeAll("(null)") catch return,
        }
    }

    // formats value-typed expressions (no operations, but also no vectors)
    pub fn format(
        self: Self,
        w: *std.Io.Writer,
    ) !void {
        if (self == .vector) return;
        const temp_config: config_mod.Config = .{ .writer = w };
        self.printValue(temp_config) catch return;
    }

    pub fn getReal(self: Self) f64 {
        return switch (self) {
            .boolean => @floatFromInt(@intFromBool(self.boolean)),
            .real_number => self.real_number,
            else => unreachable,
        };
    }
    pub fn getComplex(self: Self) Complex(f64) {
        return switch (self) {
            .complex_number => self.complex_number,
            .boolean, .real_number => Complex(f64).init(self.getReal(), 0),
            else => unreachable,
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

    pub fn expectType(self: Self, kind: Kinds, msg: []const u8) bool {
        if (self == kind) return true;

        std.log.warn("expected '{t}' type, got '{t}': {s}", .{kind, self, msg});

        return false;
    }
};

fn printIndent(w: *std.Io.Writer, indent: u32) void {
    w.print("{s: <[1]}", .{"", indent}) catch return;
}

test "expr.getReal" {
    const k = Expr.init(@as(f64, 9.5));
    try std.testing.expect(k.getReal() == 9.5);
    try std.testing.expect(Expr.init(false).getReal() == 0.0);
}
