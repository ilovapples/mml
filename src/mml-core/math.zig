const std = @import("std");
const complex = std.math.complex;
const Complex = complex.Complex;

const mml = @import("../root.zig");
const expr = mml.expr;
const Expr = expr.Expr;
const Evaluator = mml.Evaluator;

pub fn initConstants(consts_map: *std.StringHashMap(Expr)) !void {
    try consts_map.put("pi", Expr.init(std.math.pi));
    try consts_map.put("e", Expr.init(std.math.e));
    try consts_map.put("phi", Expr.init(std.math.phi));
    try consts_map.put("i", Expr.init(Complex(f64).init(0.0, 1.0)));
    try consts_map.put("nan", Expr.init(std.math.nan(f64)));
    try consts_map.put("inf", Expr.init(std.math.inf(f64)));
}

pub fn initFuncs(funcs_maps: Evaluator.FuncsStruct) !void {
    try funcs_maps.multiarg_funcs_map.put("sin", genMultiArgFuncEntry(std.math.sin, complex.sin));
    try funcs_maps.multiarg_funcs_map.put("cos", genMultiArgFuncEntry(std.math.cos, complex.cos));
    try funcs_maps.multiarg_funcs_map.put("tan", genMultiArgFuncEntry(std.math.tan, complex.tan));
    try funcs_maps.multiarg_funcs_map.put("asin", genMultiArgFuncEntry(std.math.asin, complex.asin));
    try funcs_maps.multiarg_funcs_map.put("acos", genMultiArgFuncEntry(std.math.acos, complex.acos));
    try funcs_maps.multiarg_funcs_map.put("atan", genMultiArgFuncEntry(std.math.atan, complex.atan));
    try funcs_maps.multiarg_funcs_map.put("sinh", genMultiArgFuncEntry(std.math.sinh, complex.sinh));
    try funcs_maps.multiarg_funcs_map.put("cosh", genMultiArgFuncEntry(std.math.cosh, complex.cosh));
    try funcs_maps.multiarg_funcs_map.put("tanh", genMultiArgFuncEntry(std.math.tanh, complex.tanh));
    try funcs_maps.multiarg_funcs_map.put("asinh", genMultiArgFuncEntry(std.math.asinh, complex.asinh));
    try funcs_maps.multiarg_funcs_map.put("acosh", genMultiArgFuncEntry(std.math.acosh, complex.acosh));
    try funcs_maps.multiarg_funcs_map.put("atanh", genMultiArgFuncEntry(std.math.atanh, complex.atanh));

    try funcs_maps.multiarg_funcs_map.put("ln", genMultiArgFuncEntry(ln, complex.log));
    try funcs_maps.multiarg_funcs_map.put("log2", genMultiArgFuncEntry(std.math.log2, log2_c));
    try funcs_maps.multiarg_funcs_map.put("log10", genMultiArgFuncEntry(std.math.log10, log10_c));
    try funcs_maps.multiarg_funcs_map.put("sqrt", genMultiArgFuncEntry(std.math.sqrt, complex.sqrt));
    try funcs_maps.multiarg_funcs_map.put("csqrt", genMultiArgFuncEntry(csqrt, complex.sqrt));

    try funcs_maps.multiarg_funcs_map.put("sign", genMultiArgFuncEntry(std.math.sign, complex.sqrt));

    try funcs_maps.multiarg_funcs_map.put("conj", genComplexFunc(complex.conj));
    try funcs_maps.multiarg_funcs_map.put("phase", genComplexFunc(complex.arg));
    try funcs_maps.multiarg_funcs_map.put("real", genComplexFunc(real_c));
    try funcs_maps.multiarg_funcs_map.put("imag", genComplexFunc(imag_c));

    try funcs_maps.multiarg_funcs_map.put("root", .{.n_args = 2, .func = &root});
    try funcs_maps.multiarg_funcs_map.put("atan2", .{.n_args = 2, .func = &atan2});
    try funcs_maps.multiarg_funcs_map.put("logb", .{.n_args = 2, .func = &logb});
}

fn ln(x: anytype) @TypeOf(x) {
    return std.math.log(f64, std.math.e, x);
}
fn log2_c(z: anytype) @TypeOf(z) {
    return complex.log(z).div(complex.log(Complex(f64).init(2, 0)));
}
fn log10_c(z: anytype) @TypeOf(z) {
    return complex.log(z).div(complex.log(Complex(f64).init(10, 0)));
}
fn csqrt(x: anytype) Complex(f64) {
    return complex.sqrt(Complex(f64).init(x, 0.0));
}
fn real_c(z: anytype) f64 {
    return z.re;
}
fn imag_c(z: anytype) f64 {
    return z.im;
}
fn root(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const a = try state.eval(args[0]);
    const b = try state.eval(args[1]);

    return state.applyOp(a, b, .OpRoot);
}
fn atan2(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const correct_arg_types = [_]Expr.Kinds{.real_number};
    const y = try state.eval(args[0]);
    const x = try state.eval(args[1]);
    if (y != .real_number or x != .real_number) {
        Evaluator.warnBadFuncArgument(
            "atan2",
            if (y != .real_number) 0 else 1,
            &correct_arg_types,
            @tagName(if (y != .real_number) y else x));
        return Expr{.invalid={}};
    }

    return Expr.init(std.math.atan2(y.real_number, x.real_number));
}
fn logb(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const a = try state.eval(args[0]);
    const b = try state.eval(args[1]);
    const correct_arg_types = [_]Expr.Kinds{.real_number, .complex_number, .boolean};
    if (!a.isNumber() or !b.isNumber()) {
        Evaluator.warnBadFuncArgument(
            "logb",
            if (!a.isNumber()) 0 else 1,
            &correct_arg_types,
            @tagName(if (!a.isNumber()) a else b));
        return Expr{.invalid={}};
    }

    if (a.isComplex() or b.isComplex()) {
        return Expr.init(complex.log(a.getComplex()).div(complex.log(b.getComplex())));
    } else {
        return Expr.init(std.math.log(f64, b.getReal(), a.getReal()));
    }
}

fn genMultiArgFuncEntry(f: anytype, cf: anytype) Evaluator.MultiArgFuncEntry {
    return .{
        .n_args = 1,
        .func = struct {
            pub fn wrapper(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
                const val = try state.eval(args[0]);
                if (val == .real_number) {
                    return Expr.init(f(val.real_number));
                } else if (val == .complex_number) {
                    return Expr.init(cf(val.complex_number));
                }
                return Expr{.invalid={}};
            }
        }.wrapper,
    };
}
fn genRealFunc(f: anytype) Evaluator.MultiArgFuncEntry {
    return .{
        .n_args = 1,
        .func = struct {
            pub fn wrapper(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
                const val = try state.eval(args[0]);
                if (val == .real_number) {
                    return Expr.init(f(val.real_number));
                }
                return Expr{.invalid={}};
            }
        }.wrapper,
    };
}
fn genComplexFunc(cf: anytype) Evaluator.MultiArgFuncEntry {
    return .{
        .n_args = 1,
        .func = struct {
            pub fn wrapper(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
                const val = try state.eval(args[0]);
                if (val == .complex_number) {
                    return Expr.init(cf(val.complex_number));
                }
                return Expr{.invalid={}};
            }
        }.wrapper,
    };
}
