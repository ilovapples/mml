const std = @import("std");
const Complex = std.math.Complex;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

const exprs = @import("expr.zig");
const token = @import("token.zig");
const config_mod = @import("config.zig");
const Expr = exprs.Expr;

const math_lib = @import("mml-core/math.zig");
const stdmml_lib = @import("mml-core/stdmml.zig");

pub const MultiArgFunc = *const fn(state: *Self, args: []*Expr) EvalError!Expr;
pub const MultiArgFuncEntry = struct {
    func: MultiArgFunc,
    n_args: usize = 1,
};

pub const FuncsStruct = struct {
    multiarg_funcs_map: *std.StringHashMap(MultiArgFuncEntry),
    builtin_funcs_map: *std.StringHashMap(MultiArgFuncEntry),
};

var initialized: usize = 0;
var constants_map: std.StringHashMap(Expr) = undefined;
var multiarg_funcs_map: std.StringHashMap(MultiArgFuncEntry) = undefined;
var builtin_funcs_map: std.StringHashMap(MultiArgFuncEntry) = undefined;

config: ?*config_mod.Config = null,
allocator: Allocator,
variables: std.StringHashMap(*Expr),
last_val: ?Expr = null,

const Self = @This();

// allocator must be obtained from an ArenaAllocator or THERE WILL BE MEMORY LEAKS
pub fn init(allocator: Allocator, config: *config_mod.Config) !Self {
    if (initialized == 0) {
        constants_map = .init(allocator);
        multiarg_funcs_map = .init(allocator);
        builtin_funcs_map = .init(allocator);
        
        try initializeConstants();
        try initializeFuncMaps();

        //multiarg_funcs_map.put("print");
    }
    initialized += 1;
    var evaluator = Self{
        .allocator = allocator,
        .variables = .init(allocator),
        .config = config,
    };
    config.evaluator = &evaluator;
    return evaluator;
}

pub fn deinit(self: *Self) void {
    self.variables.deinit();
    initialized -= 1;
    if (initialized == 0) {
        constants_map.deinit();
        multiarg_funcs_map.deinit();
        builtin_funcs_map.deinit();
    }
}

pub const EvalError = error{
    NoLastValue,
    UndefinedIdentifier,
    RecursiveDefinitionError,
    WrongArgumentCount,
    NonIntegerVectorIndex,
    OutOfBoundsIndex,
    BadFuncCall,
    BadOperation,
    InvalidExpression,
}
|| exprs.Expr.GetComplexError
|| exprs.Expr.PrintExprError
|| Allocator.Error;
fn evalRecurse(self: *Self, e: *const Expr) EvalError!Expr {
    switch (e.*) {
        .invalid => return EvalError.InvalidExpression,
        .vector,
        .real_number,
        .complex_number,
        .boolean,
        .string => return e.*, 
        .identifier, .builtin_ident => {
            const ident = if (e.* == .identifier) e.identifier else e.builtin_ident;
            if (e.* == .builtin_ident and std.mem.eql(u8, ident, "ans")) {
                return self.last_val orelse error.NoLastValue;
            }
            if (constants_map.get(ident)) |new_e| {
                return new_e;
            }

            if (e.* != .builtin_ident) {
                const var_expr = self.variables.get(ident);
                if (var_expr) |var_e| {
                    return self.evalRecurse(var_e);
                }
            }

            std.log.warn("undefined {s}identifier: '{s}{s}'\n", .{
                if (e.* == .builtin_ident) "builtin " else "",
                if (e.* == .builtin_ident) "@" else "",
                ident,
            });
            return EvalError.UndefinedIdentifier;
        },
        else => {},
    }

    const left = e.operation.left;
    const right = e.operation.right;

    if (e.operation.op == .OpAssertEqual and left != null and left.?.* == .identifier) {
        if (right.?.searchFor(.{left.?.*.identifier}, containsIdentCheck)) |_| {
            std.log.err("recursive dependency found in definition of '{s}'\n", .{left.?.identifier});
            return EvalError.RecursiveDefinitionError;
        }
        try self.variables.put(left.?.identifier, right.?);
        return self.evalRecurse(right.?);
    } else if (e.operation.op == .OpFuncCall) {
        if (left == null
            or right == null
            or (left.?.* != .builtin_ident and left.?.* != .identifier)) {
            return EvalError.BadFuncCall;
        }

        const right_val_vec = try self.evalRecurse(right.?);
        return try self.applyFunc(left.?.*, right_val_vec.vector);
    }

    return try self.applyOp(
        try self.evalRecurse(left.?),
        if (right) |r| try self.evalRecurse(r) else null,
        e.operation.op); // todo
}

pub fn eval(self: *Self, e: *const Expr) !Expr {
    self.last_val = try self.evalRecurse(e);
    return self.last_val.?;
}

fn applyFunc(self: *Self, func_ident: Expr, args: []*Expr) EvalError!Expr {
    if (func_ident == .builtin_ident) {
        if (builtin_funcs_map.get(func_ident.builtin_ident)) |func| {
            if (func.n_args > 0 and func.n_args != args.len) {
                std.log.err("expected {} arguments, got {}; in call to builtin function `@{s}`\n", .{func.n_args, args.len, func_ident.builtin_ident});
                return EvalError.WrongArgumentCount;
            }
            return try func.func(self, args);
        }

        std.log.err("undefined builtin function `@{s}` in function call\n", .{func_ident.builtin_ident});
    }
    const func_name = func_ident.identifier;

    if (multiarg_funcs_map.get(func_name)) |func| {
        if (func.n_args > 0 and func.n_args != args.len) {
            std.log.err("expected {} arguments, got {}; in call to function `{s}`\n", .{func.n_args, args.len, func_name});
            return EvalError.WrongArgumentCount;
        }
        return try func.func(self, args);
    }

    const first_arg = try self.eval(args[0]);

    std.log.err("undefined function `{s}` for `{t}` type argument in function call\n", .{
        func_name, first_arg,
    });
    return EvalError.BadFuncCall;
}

const epsilon = 1e-14;

pub fn applyOp(self: *Self, lo: ?Expr, ro: ?Expr, op: token.TokenType) EvalError!Expr {
    if (lo == null) return EvalError.InvalidExpression;
    const left = lo.?;

    if (ro == null) {
        return switch (op) {
            .OpNot => { // Boolean NOT operation
                if (left != .complex_number) {
                    return Expr.init(try left.getReal() == 0);
                }
                warnBadOperation(op, left, null);
                return EvalError.BadOperation;
            },
            .OpNegate => { // negation operation
                return switch (left) {
                    .boolean, .real_number => Expr.init(-(try left.getReal())),
                    .complex_number => Expr.init(left.complex_number.neg()),
                    .vector => self.applyOp(lo, Expr.init(@as(exprs.real_number_type, -1.0)), .OpMul),
                    else => blk: {
                        warnBadOperation(op, left, null);
                        break :blk EvalError.BadOperation;
                    },
                };
            },
            .Pipe => { // compute magnitude of real number, complex number, or vector
                return switch (left) {
                    .boolean, .real_number => Expr.init(@abs(try left.getReal())),
                    .complex_number => Expr.init((try left.getComplex()).magnitude()),
                    .vector => blk: {
                        var sum: exprs.real_number_type = 0.0;
                        for (left.vector) |expr| {
                            sum += (try (try self.eval(expr)).getComplex()).squaredMagnitude();
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
                    .vector = try self.allocator.alloc(*Expr, 2),
                };
                
                const two_exprs = try self.allocator.alloc(Expr, 2);
                const negated = try self.applyOp(lo, null, .OpNegate);
                two_exprs[0] = left;
                two_exprs[1] = negated;

                vec_expr.vector[0] = &two_exprs[0];
                vec_expr.vector[1] = &two_exprs[1];

                return vec_expr;
            },
            .OpUnaryNothing => left,
            .OpRoot => {
                return switch (left) {
                    .boolean, .real_number => Expr.init(@sqrt(try left.getReal())),
                    .complex_number => Expr.init(std.math.complex.sqrt(try left.getComplex())),
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
        const left_real = try left.getReal();
        const right_real = try right.getReal();
        return switch (op) {
            .OpPow => Expr.init(std.math.pow(exprs.real_number_type, left_real, right_real)),
            .OpMul => Expr.init(left_real * right_real),
            .OpDiv => Expr.init(left_real / right_real),
            .OpMod => Expr.init(std.math.mod(exprs.real_number_type, left_real, right_real) catch |err| switch (err) {
                    error.DivisionByZero => std.math.inf(exprs.real_number_type),
                    error.NegativeDenominator => std.math.mod(exprs.real_number_type, left_real, @abs(right_real))
                        catch std.math.nan(exprs.real_number_type),
            }),
            .OpAdd => Expr.init(left_real + right_real),
            .OpSub => Expr.init(left_real - right_real),
            .OpLess => Expr.init(left_real < right_real),
            .OpGreater => Expr.init(left_real > right_real),
            .OpLessEq => Expr.init(left_real <= right_real),
            .OpGreaterEq => Expr.init(left_real >= right_real),
            .OpEq => Expr.init(std.math.approxEqAbs(exprs.real_number_type, left_real, right_real, epsilon)),
            .OpNotEq => Expr.init(!std.math.approxEqAbs(exprs.real_number_type, left_real, right_real, epsilon)),
            .OpExactEq => Expr.init(left_real == right_real),
            .OpExactNotEq => Expr.init(left_real != right_real),
            .OpRoot => Expr.init(std.math.pow(exprs.real_number_type, left_real, 1.0/right_real)),
            else => blk: {
                warnBadOperation(op, left, right);
                break :blk EvalError.BadOperation;
            },
        };
    } else if (left.isNumber() and right.isNumber()) {
        const left_complex = try left.getComplex();
        const right_complex = try right.getComplex();
        return switch (op) {
            .OpPow => Expr.init(std.math.complex.pow(left_complex, right_complex)),
            .OpMul => Expr.init(left_complex.mul(right_complex)),
            .OpDiv => Expr.init(left_complex.div(right_complex)),
            .OpAdd => Expr.init(left_complex.add(right_complex)),
            .OpSub => Expr.init(left_complex.sub(right_complex)),
            .OpEq => Expr.init(
                std.math.approxEqAbs(exprs.real_number_type, left_complex.re, right_complex.re, epsilon) and
                std.math.approxEqAbs(exprs.real_number_type, left_complex.im, right_complex.im, epsilon)
            ),
            .OpNotEq => Expr.init(!(
                std.math.approxEqAbs(exprs.real_number_type, left_complex.re, right_complex.re, epsilon) and
                std.math.approxEqAbs(exprs.real_number_type, left_complex.im, right_complex.im, epsilon)
            )),
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
                const str = try self.allocator.alloc(u8, left.string.len + right.string.len);
                @memcpy(str[0..left.string.len], left.string);
                @memcpy(str[left.string.len..(left.string.len + right.string.len)], right.string);
                break :blk Expr{.string = str};
            },
            .OpEq => Expr.init(std.mem.eql(u8, left.string, right.string)),
            .OpNotEq => Expr.init(!std.mem.eql(u8, left.string, right.string)),
            else => blk: {
                warnBadOperation(op, left, right);
                break :blk EvalError.BadOperation;
            },
        };
    } else if (((left == .string and right == .real_number) or
                (left == .real_number and right == .string)) and op == .OpMul) {
        const the_str, const the_multiple: usize = if (left == .string)
            .{ left.string, @intFromFloat(@trunc(right.real_number)) }
        else
            .{ right.string, @intFromFloat(@trunc(left.real_number)) };
        const str = try self.allocator.alloc(u8, the_str.len * the_multiple);
        for (0..the_multiple) |i| {
            @memcpy(str[i*the_str.len..(i+1)*the_str.len], the_str);
        }
        return Expr{.string = str};
    } else if ((left == .vector or left == .string) and right == .real_number and op == .OpDot) {
        // vector/string index
        const right_real = try right.getReal();
        if (!std.math.approxEqAbs(exprs.real_number_type, @trunc(right_real), right_real, epsilon)) {
            std.log.err("vectors and strings may only be indexed by a positive integer\n", .{});
            return EvalError.NonIntegerVectorIndex;
        }
        const i: usize = @intFromFloat(@trunc(right_real));
        if (left == .vector) {
            if (i >= left.vector.len) {
                std.log.err("index {} out of range for vector of length {}\n", .{i, left.vector.len});
                return EvalError.OutOfBoundsIndex;
            }
            return self.eval(left.vector[i]);
        } else if (left == .string) {
            if (i >= left.string.len) {
                std.log.err("index {} out of range for string of length {}\n", .{i, left.string.len});
                return EvalError.OutOfBoundsIndex;
            }
            return Expr.init(@as(i64, left.string[i]));
        }
    } else if (left == .vector and right == .vector and left.vector.len == right.vector.len) {
        switch (op) {
            .OpMul => {
                // n-dimensional dot product
                var sum = Complex(exprs.real_number_type).init(0.0, 0.0);
                for (0..left.vector.len) |i| {
                    sum = sum.add(try (try self.applyOp(
                                try self.eval(left.vector[i]),
                                try self.eval(right.vector[i]),
                                .OpMul)
                            ).getComplex());
                }
                const dropped_imag = dropComplexIfZeroImag(sum);
                if (dropped_imag) |f| return Expr.init(f)
                else return Expr.init(sum);
            },
            .OpEq => return for (0..left.vector.len) |i| {
                if (!(try self.applyOp(
                            try self.eval(left.vector[i]),
                            try self.eval(right.vector[i]),
                            .OpEq)).boolean) {
                    break Expr.init(false);
                }
            } else Expr.init(true),
            else => {
                warnBadOperation(op, left, right);
                return EvalError.BadOperation;
            },
        }
    } else if ((left == .vector and right.isNumber()) or
               (left.isNumber() and right == .vector)) {
        switch (op) {
            .OpAdd, .OpSub, .OpMul, .OpDiv => {
                const source_vec = if (left == .vector) &left.vector else &right.vector;
                var vec_expr: Expr = .{
                    .vector = try self.allocator.alloc(*Expr, source_vec.len),
                };
                const n_exprs = try self.allocator.alloc(Expr, source_vec.len);
                for (0..source_vec.len) |i| {
                    const cur = if (left == .vector) try self.applyOp(try self.eval(left.vector[i]), right, op)
                                                else try self.applyOp(left, try self.eval(right.vector[i]), op);
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

fn warnBadOperation(op: token.TokenType, lo: exprs.Expr, ro: ?exprs.Expr) void {
    if (ro) |r| {
        std.log.warn("failed to apply .{t} operator on '{t}' and '{t}' type operands\n" , .{op, lo, r});
    } else {
        std.log.warn("failed to apply .{t} operator to '{t}' type operand\n", .{op, lo});
    }
}
pub fn warnBadFuncArgument(
    func_name: []const u8,
    arg_index: usize,
    expected_types: []const Expr.Kinds,
    got_type_str: []const u8,
) !void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.print("in call to function '{s}': argument {} expects one of these types: ", .{func_name, arg_index+1});
    for (expected_types) |t| {
        try writer.print("'{t}', ", .{t});
    }
    try writer.print("\ngot '{s}'", .{got_type_str});
    std.log.warn("{s}", .{buffer[0..writer.end]});
}
pub fn dropComplexIfZeroImag(z: Complex(exprs.real_number_type)) ?exprs.real_number_type {
    if (z.im != 0) return null;
    return z.re;
}

test "Evaluator.dropComplexIfZeroImag" {
    try expect(dropComplexIfZeroImag(Complex(exprs.real_number_type).init(19.0, 0.0)).? == 19.0);
}

test "Evaluator.eval" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;

    var config = config_mod.Config{.writer = stdout};
    var evaluator = try Self.init(allocator, &config);
    defer evaluator.deinit();
}

pub fn findIdent(self: *Self, ident: []const u8) ?Expr {
    if (std.mem.eql(u8, ident, "ans")) return self.last_val;
    if (constants_map.get(ident)) |e| return e;
    if (self.variables.get(ident)) |e| return e.*;

    return null;
}

pub fn containsIdentCheck(e: *const Expr, context: struct { []const u8 }) bool {
    return e.* == .identifier and std.mem.eql(u8, e.identifier, context.@"0");
}

fn initializeConstants() !void {
    try constants_map.put("true", Expr.init(true));
    try constants_map.put("false", Expr.init(false));
    try math_lib.initConstants(&constants_map);
    try stdmml_lib.initConstants(&constants_map);
}

fn initializeFuncMaps() !void {
    const funcs_struct: FuncsStruct = .{
        .multiarg_funcs_map = &multiarg_funcs_map,
        .builtin_funcs_map = &builtin_funcs_map,
    };
    try math_lib.initFuncs(funcs_struct);
    try stdmml_lib.initFuncs(funcs_struct);
}
