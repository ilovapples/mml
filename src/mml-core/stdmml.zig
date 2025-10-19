const std = @import("std");
const complex = std.math.complex;
const Complex = complex.Complex;

const expr = @import("../expr.zig");
const Expr = expr.Expr;
const Evaluator = @import("../Evaluator.zig");

pub fn initConstants(consts_map: *std.StringHashMap(Expr)) !void {
    try consts_map.put("exit", Expr{ .code = Expr.Code.Exit });
    try consts_map.put("clear", Expr{ .code = Expr.Code.ClearScreen });
}

pub fn initFuncs(funcs_maps: Evaluator.FuncsStruct) !void {
    try funcs_maps.multiarg_funcs_map.put("print", .{.n_args = 0, .func = &print});
    try funcs_maps.multiarg_funcs_map.put("println", .{.n_args = 0, .func = &println});
    try funcs_maps.multiarg_funcs_map.put("sort", .{.n_args = 1, .func = &sort});
    try funcs_maps.builtin_funcs_map.put("dbg", .{.n_args = 1, .func = &builtin__dbg});
    try funcs_maps.builtin_funcs_map.put("typeof", .{.n_args = 1, .func = &builtin__typeof});
    try funcs_maps.builtin_funcs_map.put("dbg_ident", .{.n_args = 1, .func = &builtin__dbg_ident});
    try funcs_maps.builtin_funcs_map.put("as", .{.n_args = 2, .func = &builtin__as});
    try funcs_maps.builtin_funcs_map.put("undef", .{.n_args = 1, .func = &builtin__undef});
}

fn builtin__dbg(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    args[0].print(state.config.?.*);
    return Expr.init({});
}
fn builtin__typeof(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const val = try state.eval(args[0]);
    return Expr{ .string = @tagName(val) };
}
fn builtin__dbg_ident(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const e = state.findIdent(args[0].identifier);
    if (e == null) return Expr{.string = "unknown"};
    e.?.print(state.config.?.*);

    return Expr.init({});
}
fn print(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const saved_quote_strings = if (state.config) |conf| conf.quote_strings else false;
    if (state.config) |conf| conf.quote_strings = false;

    for (args, 0..) |e, i| {
        const v = try state.eval(e);
        try v.printValue(state.config.?.*);
        if (i < args.len - 1) state.config.?.writer.writeByte(' ') catch {};
    }

    if (state.config) |conf| conf.quote_strings = saved_quote_strings;
    return Expr.init({});
}
fn println(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const saved_quote_strings = if (state.config) |conf| conf.quote_strings else false;
    if (state.config) |conf| conf.quote_strings = false;

    for (args) |e| {
        try (try state.eval(e)).printValue(state.config.?.*);
        state.config.?.writer.writeByte('\n') catch {};
    }

    if (state.config) |conf| conf.quote_strings = saved_quote_strings;
    return Expr.init({});
}
fn sort(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const vec = try state.eval(args[0]);
    if (!vec.expectType(.vector, "sort{v} takes a vector and returns it sorted")) {
        return Evaluator.EvalError.BadFuncCall;
    }

    const sorted_vec = Expr{ .vector = try state.allocator.dupe(*Expr, vec.vector) };

    std.sort.heap(*Expr, sorted_vec.vector, .{state}, exprLessThan);

    return sorted_vec;
}
fn exprLessThan(c: struct { *Evaluator }, a: *Expr, b: *Expr) bool {
    const a_v: Expr = c.@"0".eval(a) catch return false;
    const b_v: Expr = c.@"0".eval(b) catch return false;

    return a_v.getReal() < b_v.getReal();
}

fn builtin__as(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const bad_call_msg = "@as{t, any} takes a type as a string, and a value ";

    const s = args[0].*; // string
    if (!s.expectType(.string, bad_call_msg)) return Evaluator.EvalError.BadFuncCall;

    const e = try state.eval(args[1]);

    const ExprType = .{
        .Complex = "complex",
        .Integer = "integer",
        .Real = "real",
        .String = "string",
    };

    if (std.mem.eql(u8, s.string, ExprType.Complex) and e.isNumber()) { // -> complex
        if (e.isComplex()) return e;
        if (e.isReal()) return Expr.init(Complex(f64).init(e.getReal(), 0.0));
    } else if (std.mem.eql(u8, s.string, ExprType.Integer) and e.isReal()) { // -> integer
        return Expr.init(@as(i64, @intFromFloat(@trunc(e.getReal()))));
    } else if (std.mem.eql(u8, s.string, ExprType.Real) and (e.isNumber() or e == .integer)) { // -> real
        return switch (e) {
            .boolean, .real_number => Expr.init(e.getReal()),
            .complex_number => if (Evaluator.dropComplexIfZeroImag(e.complex_number)) |c|
                Expr.init(c)
            else blk: {
                std.log.err("{s}", .{bad_call_msg});
                break :blk Evaluator.EvalError.BadFuncCall;
            },
            .integer => Expr.init(@as(f64, @floatFromInt(e.integer))),
            else => blk: {
                std.log.err("{s}", .{bad_call_msg});
                break :blk Evaluator.EvalError.BadFuncCall;
            },
        };
    } else if (std.mem.eql(u8, s.string, ExprType.String)) { // -> string
        const buffer = try state.allocator.alloc(u8, 512);
        var writer = std.Io.Writer.fixed(buffer);
        var new_config = state.config.?.*;
        new_config.writer = &writer;
        
        e.printValue(new_config) catch return Expr{.string = buffer};
        return Expr{.string = buffer[0..writer.end]};
    }

    return Evaluator.EvalError.BadOperation;
}

fn builtin__undef(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const e = args[0].*;

    if (!e.expectType(.identifier, "@undef{ident} takes an identifier")) return Evaluator.EvalError.BadFuncCall;
    
    return Expr.init(state.variables.remove(e.identifier));
}
