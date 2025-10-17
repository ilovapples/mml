const std = @import("std");
const complex = std.math.complex;
const Complex = complex.Complex;

const exprs = @import("../expr.zig");
const Expr = exprs.Expr;
const Evaluator = @import("../Evaluator.zig");

pub fn initConstants(consts_map: *std.StringHashMap(Expr)) !void {
    _ = consts_map;
}

pub fn initFuncs(funcs_maps: Evaluator.FuncsStruct) !void {
    try funcs_maps.multiarg_funcs_map.put("dbg", .{.n_args = 1, .func = &dbg});
    try funcs_maps.multiarg_funcs_map.put("dbg_type", .{.n_args = 1, .func = &dbg_type});
    try funcs_maps.multiarg_funcs_map.put("dbg_ident", .{.n_args = 1, .func = &dbg_ident});
    try funcs_maps.multiarg_funcs_map.put("print", .{.n_args = 0, .func = &print});
    try funcs_maps.multiarg_funcs_map.put("println", .{.n_args = 0, .func = &println});
    try funcs_maps.multiarg_funcs_map.put("sort", .{.n_args = 1, .func = &sort});
    try funcs_maps.builtin_funcs_map.put("as", .{.n_args = 2, .func = &builtin_as});
}

fn dbg(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    args[0].print(state.config.?.*);
    return Expr.init({});
}
fn dbg_type(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const val = try state.eval(args[0]);
    return Expr{ .string = @tagName(val) };
}
fn dbg_ident(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
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
    const vec = &args[0].vector;
    const vec_expr = Expr{
        .vector = try state.allocator.alloc(*Expr, vec.len),
    };

    @memcpy(vec_expr.vector, vec.*);
    std.sort.heap(*Expr, vec_expr.vector, .{state}, exprLessThan);

    return vec_expr;
}
fn exprLessThan(c: struct { *Evaluator }, a: *Expr, b: *Expr) bool {
    const a_v: Expr = c.@"0".eval(a) catch return false;
    const b_v: Expr = c.@"0".eval(b) catch return false;

    const a_r = a_v.getReal() catch return false;
    const b_r = b_v.getReal() catch return false;
    
    return a_r < b_r;
}

fn builtin_as(state: *Evaluator, args: []*Expr) Evaluator.EvalError!Expr {
    const s = args[0].*; // string
    const e = try state.eval(args[1]);

    if (std.mem.eql(u8, s.string, "complex") and e.isNumber()) { // -> complex
        if (e.isComplex()) return e;
        if (e.isReal()) return Expr.init(Complex(exprs.real_number_type).init(try e.getReal(), 0.0));
    } else if (std.mem.eql(u8, s.string, "integer") and e.isReal()) { // -> integer
        return Expr.init(@as(i64, @intFromFloat(@trunc(try e.getReal()))));
    } else if (std.mem.eql(u8, s.string, "real") and (e.isNumber() or e == .integer)) { // -> real
        return switch (e) {
            .boolean, .real_number => Expr.init(try e.getReal()),
            .complex_number => if (Evaluator.dropComplexIfZeroImag(e.complex_number)) |c| Expr.init(c)
                else Expr{.invalid = {}},
            .integer => Expr.init(@as(exprs.real_number_type, @floatFromInt(e.integer))),
            else => Expr{.invalid = {}},
        };
    } else if (std.mem.eql(u8, s.string, "string")) { // -> string
        const buffer = try state.allocator.alloc(u8, 512);
        var writer = std.Io.Writer.fixed(buffer);
        var new_config = state.config.?.*;
        new_config.writer = &writer;
        
        e.printValue(new_config) catch return Expr{.string = buffer};
        return Expr{.string = buffer[0..writer.end]};
    }

    return Evaluator.EvalError.BadOperation;
}
