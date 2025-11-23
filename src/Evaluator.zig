const std = @import("std");
const Io = std.Io;
const Complex = std.math.Complex;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const mml = @import("root.zig");
const expr = mml.expr;
const Expr = expr.Expr;
const token = mml.token;
const Config = mml.Config;

conf: ?*Config = null,
variable_map: std.StringHashMap(*Expr),
locals_map: ?std.StringHashMap(*Expr) = null,
last_val: ?Expr = null,
allocs: *mml.Allocators,

var n_initialized: std.atomic.Value(u64) = .init(0);
var constants_map: std.StringHashMap(Expr) = undefined;
var multiarg_funcs_map: std.StringHashMap(MultiArgFuncEntry) = undefined;
var builtin_funcs_map: std.StringHashMap(MultiArgFuncEntry) = undefined;

pub const MultiArgFuncEntry = struct {
    func: MultiArgFunc,
    n_args: usize = 0,

    pub const MultiArgFunc = *const fn (state: *Self, args: []*Expr) EvalError!Expr;
};

pub const FuncsStruct = struct {
    multiarg_funcs_map: *std.StringHashMap(MultiArgFuncEntry),
    builtin_funcs_map: *std.StringHashMap(MultiArgFuncEntry),
};

const Self = @This();

/// Initialize an Evaluator (along with other global state that needs to be initialized).
pub fn init(allocs: *mml.Allocators, conf: ?*Config) !Self {
    const arena_alloc = allocs.arena.allocator();
    const n_initialized_val = n_initialized.load(.acquire);
    if (n_initialized_val == 0) {
        constants_map = .init(arena_alloc);
        multiarg_funcs_map = .init(arena_alloc);
        builtin_funcs_map = .init(arena_alloc);

        try initBuiltins();
    }
    n_initialized.store(n_initialized_val + 1, .release);
    return .{
        .conf = conf,
        .variable_map = .init(arena_alloc),
        .allocs = allocs,
    };
}

/// Uninitialize an Evaluator.
pub fn deinit(self: *Self) void {
    self.variable_map.deinit();
    if (self.locals_map) |*lm| lm.deinit();
    const n_initialized_val = n_initialized.load(.acquire);
    if (n_initialized_val == 1) {
        constants_map.deinit();
        multiarg_funcs_map.deinit();
        builtin_funcs_map.deinit();
    }
    n_initialized.store(n_initialized_val - 1, .release);
}

pub const EvalError = error{
    NoLastValue,
    UndefinedIdentifier,
    CircularDefinitionError,
    WrongArgumentCount,
    NonIntegerVectorIndex,
    OutOfBoundsIndex,
    BadFuncCall,
    IllegalFunctionDefinition,
    BadOperation,
    InvalidExpression,
    BadConfiguration,
} || Allocator.Error;
fn evalRecurse(state: *Self, e: *const Expr) EvalError!Expr {
    switch (e.*) {
        .invalid => return EvalError.InvalidExpression,
        .vector, .integer, .real_number, .complex_number, .boolean, .string, .func_object, .nothing => return e.*,
        .identifier, .builtin_ident => {
            const ident = if (e.* == .identifier) e.identifier else e.builtin_ident;
            if (e.* == .builtin_ident and std.mem.eql(u8, ident, "ans")) {
                return state.last_val orelse EvalError.NoLastValue;
            }
            if (constants_map.get(ident)) |new_e| {
                return new_e;
            }

            if (e.* != .builtin_ident) {
                if (state.variable_map.get(ident)) |ie| {
                    return state.evalRecurse(ie);
                } else if (state.locals_map != null) {
                    if (state.locals_map.?.get(ident)) |ie| {
                        return state.evalRecurse(ie);
                    }
                }
            }

            if (e.* == .builtin_ident) {
                std.log.warn("undefined builtin identifier: '@{s}'", .{ident});
            } else {
                std.log.warn("undefined identifier: '{s}'", .{ident});
            }
            return EvalError.UndefinedIdentifier;
        },
        else => {},
    }

    const left = e.operation.left;
    const right = e.operation.right;

    const alloc = state.allocs.arena.allocator();

    if (e.operation.op == .OpAssertEqual and left != null and right != null) {
        if (left.?.* == .identifier) {
            if (right.?.dependsOn(state, left.?.identifier)) {
                std.log.err("circular dependency found in definition of '{s}'", .{left.?.identifier});
                return EvalError.CircularDefinitionError;
            }

            try state.variable_map.put(left.?.identifier, right.?);
            if (state.conf) |c| {
                if (c.assign_returns_nothing) return Expr.init({});
            }
            return state.evalRecurse(right.?);
        } else if (left.?.* == .operation and left.?.operation.op == .OpFuncCall and
            left.?.operation.left.?.* == .identifier and left.?.operation.right.?.* == .vector)
        {
            var is_legal = true;
            const fo: Expr.FuncObject = .{
                .body = right.?,
                .params = blk: {
                    const param_name_vector = left.?.operation.right.?;
                    var params: [][]const u8 = try alloc.alloc([]const u8, param_name_vector.vector.len);
                    for (param_name_vector.vector, 0..) |pname, i| {
                        if (pname.* != .identifier) {
                            std.log.err("arguments to function definition must be " ++
                                "identifiers; found '.{t}' type", .{pname.*});
                            is_legal = false;
                            continue;
                        }
                        params[i] = pname.identifier;
                    }
                    break :blk params;
                },
            };

            if (is_legal) {
                const expr_to_save = try state.allocs.expr_pool.create();
                expr_to_save.* = @unionInit(Expr, "func_object", fo);

                try state.variable_map.put(left.?.operation.left.?.identifier, expr_to_save);
            }

            return Expr.init({});
        }
    } else if (e.operation.op == .OpFuncCall) {
        if (left == null or right == null or (left.?.* != .builtin_ident and left.?.* != .identifier)) {
            return EvalError.BadFuncCall;
        }

        const right_val_vec = try state.evalRecurse(right.?);
        return try state.applyFunc(left.?.*, right_val_vec.vector);
    }

    return try state.applyOp(
        try state.evalRecurse(left.?),
        if (right) |r| try state.evalRecurse(r) else null,
        e.operation.op,
    );
}

pub fn eval(state: *Self, e: *const Expr) !Expr {
    state.last_val = try state.evalRecurse(e);
    return state.last_val.?;
}

fn applyFunc(state: *Self, func_ident: Expr, args: []*Expr) EvalError!Expr {
    const alloc = state.allocs.arena.allocator();

    if (func_ident == .identifier) blk: {
        const fo_expr = state.variable_map.get(func_ident.identifier) orelse break :blk;
        if (fo_expr.* != .func_object) {
            std.log.warn("call to function '{s}' failed: function name shadowed by non-function-object variable.", .{func_ident.identifier});
            return EvalError.BadFuncCall;
        }
        const fo = fo_expr.func_object;

        if (state.locals_map) |*lm| lm.deinit();
        state.locals_map = .init(alloc);

        if (args.len != fo.params.len) {
            std.log.err("expected {d} argument(s), got {d}; in call to user-defined function '{s}'", .{ fo.params.len, args.len, func_ident.identifier });
            return EvalError.BadFuncCall;
        }

        for (fo.params, 0..) |param, i| {
            try state.locals_map.?.put(param, args[i]);
        }

        return state.eval(fo.body);
    }

    if (func_ident == .builtin_ident) {
        if (builtin_funcs_map.get(func_ident.builtin_ident)) |func| {
            if (func.n_args > 0 and func.n_args != args.len) {
                std.log.err("expected {} argument(s), got {}; in call to builtin function `@{s}`", .{ func.n_args, args.len, func_ident.builtin_ident });
                return EvalError.WrongArgumentCount;
            }
            return try func.func(state, args);
        }

        std.log.err("undefined builtin function `@{s}` in function call", .{func_ident.builtin_ident});
        return EvalError.BadFuncCall;
    }
    const func_name = func_ident.identifier;

    if (multiarg_funcs_map.get(func_name)) |func| {
        if (func.n_args > 0 and func.n_args != args.len) {
            std.log.err("expected {} arguments, got {}; in call to function `{s}`", .{ func.n_args, args.len, func_name });
            return EvalError.WrongArgumentCount;
        }
        return try func.func(state, args);
    }

    if (args.len > 0) {
        const first_arg = try state.eval(args[0]);

        std.log.err("undefined function `{s}` for `{t}` type argument in function call", .{
            func_name, first_arg,
        });
    } else {
        std.log.err("undefined function `{s}` for function call with zero arguments", .{func_name});
    }
    return EvalError.BadFuncCall;
}

const epsilon = 1e-14;

pub fn applyOp(state: *Self, lo: ?Expr, ro: ?Expr, op: token.TokenType) EvalError!Expr {
    const alloc = state.allocs.arena.allocator();

    if (lo == null) return EvalError.InvalidExpression;
    const left = lo.?;

    if (ro == null) {
        return switch (op) {
            .OpNot => { // Boolean NOT operation
                if (left != .complex_number) {
                    return Expr.init(left.getReal() == 0);
                }
                warnBadOperation(op, left, null);
                return EvalError.BadOperation;
            },
            .OpNegate => { // negation operation
                return switch (left) {
                    .boolean, .real_number => Expr.init(-(left.getReal())),
                    .complex_number => Expr.init(left.complex_number.neg()),
                    .vector => state.applyOp(lo, Expr.init(@as(f64, -1.0)), .OpMul),
                    else => blk: {
                        warnBadOperation(op, left, null);
                        break :blk EvalError.BadOperation;
                    },
                };
            },
            .Pipe => { // compute magnitude of real number, complex number, or vector
                return switch (left) {
                    .boolean, .real_number => Expr.init(@abs(left.getReal())),
                    .complex_number => Expr.init(left.getComplex().magnitude()),
                    .vector => blk: {
                        var sum: f64 = 0.0;
                        for (left.vector) |e| {
                            sum += (try state.applyOp(try state.eval(e), null, .Pipe)).getComplex().squaredMagnitude();
                        }
                        const magnitude = @sqrt(sum);
                        break :blk Expr.init(magnitude);
                    },
                    else => blk: {
                        warnBadOperation(op, left, null);
                        break :blk EvalError.BadOperation;
                    },
                };
            },
            .OpTilde => { // plus-minus operator
                var vec_expr: Expr = .{
                    .vector = try alloc.alloc(*Expr, 2),
                };

                const two_exprs = try alloc.alloc(Expr, 2);
                const negated = try state.applyOp(lo, null, .OpNegate);
                two_exprs[0] = left;
                two_exprs[1] = negated;

                vec_expr.vector[0] = &two_exprs[0];
                vec_expr.vector[1] = &two_exprs[1];

                return vec_expr;
            },
            .OpUnaryNothing => left,
            .OpRoot => {
                return switch (left) {
                    .boolean, .real_number => Expr.init(@sqrt(left.getReal())),
                    .complex_number => Expr.init(std.math.complex.sqrt(left.getComplex())),
                    else => blk: {
                        warnBadOperation(op, left, null);
                        break :blk EvalError.BadOperation;
                    },
                };
            },
            else => {
                warnBadOperation(op, left, null);
                return EvalError.BadOperation;
            },
        };
    }
    const right = ro.?;
    if (left.isReal() and right.isReal()) {
        const left_real = left.getReal();
        const right_real = right.getReal();
        return switch (op) {
            .OpPow => Expr.init(std.math.pow(f64, left_real, right_real)),
            .OpMul => Expr.init(left_real * right_real),
            .OpDiv => Expr.init(left_real / right_real),
            .OpMod => Expr.init(std.math.mod(f64, left_real, right_real) catch |err| switch (err) {
                error.DivisionByZero => std.math.inf(f64),
                error.NegativeDenominator => std.math.mod(f64, left_real, @abs(right_real)) catch std.math.nan(f64),
            }),
            .OpAdd => Expr.init(left_real + right_real),
            .OpSub => Expr.init(left_real - right_real),
            .OpLess => Expr.init(left_real < right_real),
            .OpGreater => Expr.init(left_real > right_real),
            .OpLessEq => Expr.init(left_real <= right_real),
            .OpGreaterEq => Expr.init(left_real >= right_real),
            .OpEq => Expr.init(std.math.approxEqAbs(f64, left_real, right_real, epsilon)),
            .OpNotEq => Expr.init(!std.math.approxEqAbs(f64, left_real, right_real, epsilon)),
            .OpExactEq => Expr.init(left_real == right_real),
            .OpExactNotEq => Expr.init(left_real != right_real),
            .OpRoot => Expr.init(std.math.pow(f64, left_real, 1.0 / right_real)),
            else => blk: {
                warnBadOperation(op, left, right);
                break :blk EvalError.BadOperation;
            },
        };
    } else if (left.isNumber() and right.isNumber()) {
        const left_complex = left.getComplex();
        const right_complex = right.getComplex();
        return switch (op) {
            .OpPow => Expr.init(std.math.complex.pow(left_complex, right_complex)),
            .OpMul => Expr.init(left_complex.mul(right_complex)),
            .OpDiv => Expr.init(left_complex.div(right_complex)),
            .OpAdd => Expr.init(left_complex.add(right_complex)),
            .OpSub => Expr.init(left_complex.sub(right_complex)),
            .OpEq => Expr.init(std.math.approxEqAbs(f64, left_complex.re, right_complex.re, epsilon) and
                std.math.approxEqAbs(f64, left_complex.im, right_complex.im, epsilon)),
            .OpNotEq => Expr.init(!(std.math.approxEqAbs(f64, left_complex.re, right_complex.re, epsilon) and
                std.math.approxEqAbs(f64, left_complex.im, right_complex.im, epsilon))),
            .OpExactEq => Expr.init(left_complex.re == right_complex.re and left_complex.im == right_complex.im),
            .OpExactNotEq => Expr.init(!(left_complex.re == right_complex.re and left_complex.im == right_complex.im)),
            .OpRoot => Expr.init(std.math.complex.pow(left_complex, right_complex.reciprocal())),
            else => blk: {
                warnBadOperation(op, left, right);
                break :blk EvalError.BadOperation;
            },
        };
    } else if (left == .string and right == .string) {
        return switch (op) {
            .OpAdd => blk: {
                const str = try alloc.alloc(u8, left.string.len + right.string.len);
                @memcpy(str[0..left.string.len], left.string);
                @memcpy(str[left.string.len..(left.string.len + right.string.len)], right.string);
                break :blk Expr{ .string = str };
            },
            .OpEq => Expr.init(std.mem.eql(u8, left.string, right.string)),
            .OpNotEq => Expr.init(!std.mem.eql(u8, left.string, right.string)),
            else => blk: {
                warnBadOperation(op, left, right);
                break :blk EvalError.BadOperation;
            },
        };
    } else if (((left == .string and right == .real_number) or
        (left == .real_number and right == .string)) and op == .OpMul)
    {
        const the_str, const the_multiple: usize = if (left == .string)
            .{ left.string, @intFromFloat(@trunc(right.real_number)) }
        else
            .{ right.string, @intFromFloat(@trunc(left.real_number)) };
        const str = try alloc.alloc(u8, the_str.len * the_multiple);
        for (0..the_multiple) |i| {
            @memcpy(str[i * the_str.len .. (i + 1) * the_str.len], the_str);
        }
        return Expr{ .string = str };
    } else if ((left == .vector or left == .string) and right == .integer and op == .OpDot) {
        // vector/string index
        if (right.integer < 0) {
            std.log.err("vectors and strings may only be indexed by a positive integer", .{});
            return EvalError.NonIntegerVectorIndex;
        }
        const i: usize = @intCast(right.integer);
        if (left == .vector) {
            if (i >= left.vector.len) {
                std.log.err("index {} out of range for vector of length {}", .{ i, left.vector.len });
                return EvalError.OutOfBoundsIndex;
            }
            return state.eval(left.vector[i]);
        } else if (left == .string) {
            if (i >= left.string.len) {
                std.log.err("index {} out of range for string of length {}", .{ i, left.string.len });
                return EvalError.OutOfBoundsIndex;
            }
            return Expr.init(@as(i64, left.string[i]));
        }
    } else if (left == .vector and right == .vector and left.vector.len == right.vector.len) {
        switch (op) {
            .OpMul => {
                // n-dimensional dot product
                var sum = Complex(f64).init(0.0, 0.0);
                for (0..left.vector.len) |i| {
                    sum = sum.add((try state.applyOp(try state.eval(left.vector[i]), try state.eval(right.vector[i]), .OpMul)).getComplex());
                }
                const dropped_imag = dropComplexIfZeroImag(sum);
                if (dropped_imag) |f| return Expr.init(f) else return Expr.init(sum);
            },
            .OpEq => return for (0..left.vector.len) |i| {
                if (!(try state.applyOp(try state.eval(left.vector[i]), try state.eval(right.vector[i]), .OpEq)).boolean) {
                    break Expr.init(false);
                }
            } else Expr.init(true),
            else => {
                warnBadOperation(op, left, right);
                return EvalError.BadOperation;
            },
        }
    } else if ((left == .vector and right.isNumber()) or
        (left.isNumber() and right == .vector))
    {
        switch (op) {
            .OpAdd, .OpSub, .OpMul, .OpDiv => {
                const source_vec = if (left == .vector) &left.vector else &right.vector;
                var vec_expr: Expr = .{
                    .vector = try alloc.alloc(*Expr, source_vec.len),
                };
                const n_exprs = try alloc.alloc(Expr, source_vec.len);
                for (0..source_vec.len) |i| {
                    const cur = if (left == .vector) try state.applyOp(try state.eval(left.vector[i]), right, op) else try state.applyOp(left, try state.eval(right.vector[i]), op);
                    n_exprs[i] = cur;
                    vec_expr.vector[i] = &n_exprs[i];
                }
                return vec_expr;
            },
            else => {
                warnBadOperation(op, left, right);
                return EvalError.BadOperation;
            },
        }
    }

    warnBadOperation(op, left, right);
    return EvalError.BadOperation;
}

fn warnBadOperation(op: token.TokenType, lo: expr.Expr, ro: ?expr.Expr) void {
    if (ro) |r| {
        std.log.warn("failed to apply .{t} operator on '{t}' and '{t}' type operands", .{ op, lo, r });
    } else {
        std.log.warn("failed to apply .{t} operator to '{t}' type operand", .{ op, lo });
    }
}
pub fn warnBadFuncArgument(func_name: []const u8, arg_index: usize, expected_types: []const Expr.Kinds, got_type_str: []const u8) void {
    var buffer: [1024]u8 = undefined;
    var writer = Io.Writer.fixed(&buffer);
    writer.print("in call to function '{s}': argument {} expects one of these types: ", .{ func_name, arg_index + 1 }) catch return;
    for (expected_types) |t| {
        writer.print("'{t}', ", .{t}) catch return;
    }
    writer.print("\ngot '{s}'", .{got_type_str}) catch return;
    std.log.warn("{s}", .{buffer[0..writer.end]});
}
pub fn dropComplexIfZeroImag(z: Complex(f64)) ?f64 {
    if (z.im != 0) return null;
    return z.re;
}

test "Evaluator.dropComplexIfZeroImag" {
    try expectEqual(19.0, dropComplexIfZeroImag(Complex(f64).init(19.0, 0.0)).?);
}

test "Evaluator.eval" {
    const Evaluator = Self;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer: [512]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&buffer);
    const stderr = &stderr_writer.interface;

    var config: Config = .{ .writer = stderr };
    var evaluator: Evaluator = try .init(&arena, &config);
    defer evaluator.deinit();
}

pub fn findIdent(state: *Self, ident: []const u8) ?Expr {
    if (std.mem.eql(u8, ident, "ans")) return state.last_val;
    if (constants_map.get(ident)) |e| return e;
    if (state.variable_map.get(ident)) |e| return e.*;
    if (state.locals_map) |lm| {
        if (lm.get(ident)) |e| return e.*;
    }

    return null;
}

pub fn containsIdentCheck(e: *const Expr, context: struct { []const u8 }) bool {
    return e.* == .identifier and std.mem.eql(u8, e.identifier, context.@"0");
}

fn initBuiltins() !void {
    try initializeConstants();
    try initializeFuncMaps();
}

fn initializeConstants() !void {
    try constants_map.put("true", Expr.init(true));
    try constants_map.put("false", Expr.init(false));
    try mml.core.math.initConstants(&constants_map);
    try mml.core.stdmml.initConstants(&constants_map);
}

fn initializeFuncMaps() !void {
    const funcs_struct: FuncsStruct = .{
        .multiarg_funcs_map = &multiarg_funcs_map,
        .builtin_funcs_map = &builtin_funcs_map,
    };
    try mml.core.math.initFuncs(funcs_struct);
    try mml.core.stdmml.initFuncs(funcs_struct);
}

pub fn printFuncsList(_: *const Self, w: *Io.Writer) void {
    w.writeAll("Builtins:\n") catch return;
    var bit = builtin_funcs_map.iterator();
    while (bit.next()) |func| {
        w.print("    @{s}{{", .{func.key_ptr.*}) catch return;
        for (0..func.value_ptr.n_args) |i| {
            if (i == func.value_ptr.n_args - 1) {
                w.print("a{}", .{i}) catch return;
            } else {
                w.print("a{}, ", .{i}) catch return;
            }
        }
        if (func.value_ptr.n_args == 0) {
            w.writeAll("...") catch return;
        }
        w.writeAll("}\n") catch return;
    }
    w.writeAll("Other provided functions:\n") catch return;

    var oit = multiarg_funcs_map.iterator();
    while (oit.next()) |func| {
        w.print("   {s}{{", .{func.key_ptr.*}) catch return;
        for (0..func.value_ptr.n_args) |i| {
            if (i == func.value_ptr.n_args - 1) {
                w.print("a{}", .{i}) catch return;
            } else {
                w.print("a{}, ", .{i}) catch return;
            }
        }
        if (func.value_ptr.n_args == 0) {
            w.writeAll("...") catch return;
        }
        w.writeAll("}\n") catch return;
    }
}

pub fn printConstantsList(_: *const Self, w: *Io.Writer) void {
    w.writeAll("Constants:\n") catch return;
    var it = constants_map.iterator();
    while (it.next()) |constant| {
        w.print("    {s}\n", .{constant.key_ptr.*}) catch return;
    }
}
