const std = @import("std");
const complex = std.math.complex;
const Complex = complex.Complex;

const mml = @import("../root.zig");
const Expr = mml.expr.Expr;
const Evaluator = mml.Evaluator;
const EvalError = Evaluator.EvalError;

pub fn initConstants(consts_map: *std.StringHashMap(Expr)) !void {
    try consts_map.put("exit", Expr{ .code = Expr.Code.Exit });
    try consts_map.put("clear", Expr{ .code = Expr.Code.ClearScreen });
    try consts_map.put("help", Expr{ .code = Expr.Code.Help });
}

pub fn initFuncs(funcs_maps: Evaluator.FuncsStruct) !void {
    try funcs_maps.multiarg_funcs_map.put("print", .{.n_args = 0, .func = &print});
    try funcs_maps.multiarg_funcs_map.put("println", .{.n_args = 0, .func = &println});
    try funcs_maps.multiarg_funcs_map.put("sort", .{.n_args = 1, .func = &sort});

    try funcs_maps.builtin_funcs_map.put("dbg", .{.n_args = 1, .func = &builtin__dbg});
    try funcs_maps.builtin_funcs_map.put("dbg_str", .{.n_args = 1, .func = &builtin__dbg_str});
    try funcs_maps.builtin_funcs_map.put("typeof", .{.n_args = 1, .func = &builtin__typeof});
    try funcs_maps.builtin_funcs_map.put("dbg_ident", .{.n_args = 1, .func = &builtin__dbg_ident});
    try funcs_maps.builtin_funcs_map.put("as", .{.n_args = 2, .func = &builtin__as});
    try funcs_maps.builtin_funcs_map.put("undef", .{.n_args = 1, .func = &builtin__undef});
    try funcs_maps.builtin_funcs_map.put("help", .{.n_args = 0, .func = &builtin__help});
}

fn builtin__dbg(state: *Evaluator, args: []*Expr) EvalError!Expr {
    args[0].print(state.conf.?.*);
    return Expr.init({});
}
fn builtin__dbg_str(state: *Evaluator, args: []*Expr) EvalError!Expr {
    return Expr{
        .string = try std.fmt.allocPrint(state.arena_alloc, "{f}", .{std.fmt.alt(args[0].*, .printFmt)})
    };
}
fn builtin__typeof(state: *Evaluator, args: []*Expr) EvalError!Expr {
    const val = try state.eval(args[0]);
    return Expr{ .string = @tagName(val) };
}
fn builtin__dbg_ident(state: *Evaluator, args: []*Expr) EvalError!Expr {
    const e = state.findIdent(args[0].identifier);
    if (e == null) return Expr{.string = "unknown"};
    e.?.print(state.conf.?.*);

    return Expr.init({});
}
fn print(state: *Evaluator, args: []*Expr) EvalError!Expr {
    const saved_quote_strings = if (state.conf) |conf| conf.quote_strings else false;
    if (state.conf) |conf| conf.quote_strings = false;

    for (args, 0..) |e, i| {
        const v = try state.eval(e);
        try v.printValue(state.conf.?.*);
        if (i < args.len - 1) state.conf.?.writer.writeByte(' ') catch {};
    }

    if (state.conf) |conf| conf.quote_strings = saved_quote_strings;
    return Expr.init({});
}
fn println(state: *Evaluator, args: []*Expr) EvalError!Expr {
    const saved_quote_strings = if (state.conf) |conf| conf.quote_strings else false;
    if (state.conf) |conf| conf.quote_strings = false;

    for (args) |e| {
        try (try state.eval(e)).printValue(state.conf.?.*);
        state.conf.?.writer.writeByte('\n') catch {};
    }

    if (state.conf) |conf| conf.quote_strings = saved_quote_strings;
    return Expr.init({});
}
fn sort(state: *Evaluator, args: []*Expr) EvalError!Expr {
    const vec = try state.eval(args[0]);
    if (!vec.expectType(.vector, "sort{v} takes a vector and returns it sorted")) {
        return EvalError.BadFuncCall;
    }

    const sorted_vec = Expr{ .vector = try state.arena_alloc.dupe(*Expr, vec.vector) };

    std.sort.heap(*Expr, sorted_vec.vector, .{state}, exprLessThan);

    return sorted_vec;
}
fn exprLessThan(c: struct { *Evaluator }, a: *Expr, b: *Expr) bool {
    const a_v: Expr = c.@"0".eval(a) catch return false;
    const b_v: Expr = c.@"0".eval(b) catch return false;

    return a_v.getReal() < b_v.getReal();
}

fn builtin__as(state: *Evaluator, args: []*Expr) EvalError!Expr {
    const bad_call_msg = "@as{t, any} takes a type as a string, and a value ";

    const s = args[0].*; // string
    if (!s.expectType(.string, bad_call_msg)) return EvalError.BadFuncCall;

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
                break :blk EvalError.BadFuncCall;
            },
            .integer => Expr.init(@as(f64, @floatFromInt(e.integer))),
            else => blk: {
                std.log.err("{s}", .{bad_call_msg});
                break :blk EvalError.BadFuncCall;
            },
        };
    } else if (std.mem.eql(u8, s.string, ExprType.String)) { // -> string
        const buffer = try state.arena_alloc.alloc(u8, 512);
        var writer = std.Io.Writer.fixed(buffer);
        var new_config = state.conf.?.*;
        new_config.writer = &writer;
        
        e.printValue(new_config) catch return Expr{.string = buffer};
        return Expr{.string = buffer[0..writer.end]};
    }

    return EvalError.BadOperation;
}

fn builtin__undef(state: *Evaluator, args: []*Expr) EvalError!Expr {
    const e = args[0].*;

    if (!e.expectType(.identifier, "@undef{ident} takes an identifier")) return EvalError.BadFuncCall;
    
    return Expr.init(state.variable_map.remove(e.identifier));
}

pub fn builtin__help(state: *Evaluator, args: []*Expr) EvalError!Expr {
    if (state.conf == null) {
        std.log.err("A config must be provided to the evaluator to use the '@help' builtin.", .{});
        return EvalError.BadConfiguration;
    }
    const w = state.conf.?.writer;
    const HelpArgs = .{
        .Funcs = "funcs",
        .Consts = "constants",
    };
    const ret = Expr{.nothing = {}};
    if (args.len == 0) {
        w.writeAll("Potential arguments to '@help':\n") catch return ret;
        const fields = @typeInfo(@TypeOf(HelpArgs)).@"struct".fields;
        inline for (fields, 0..) |f, i| { // print the HelpArgs fields
            w.print("   \"{s}\"", .{@as([]const u8, f.defaultValue().?)}) catch return ret;
            if (i < fields.len - 1) w.writeByte('\n') catch return ret;
        }

        return ret;
    }

    const arg_1 = args[0].*;
    if (!arg_1.expectType(.string, "@help{s} takes a string literal")) return EvalError.BadFuncCall;
    if (std.mem.eql(u8, arg_1.string, HelpArgs.Funcs)) {
        state.printFuncsList(w);
    } else if (std.mem.eql(u8, arg_1.string, HelpArgs.Consts)) {
        state.printConstantsList(w);
    } else {
        std.log.err("Invalid '@help' argument '{s}' (try '@help{{}}' to see legal arguments)", .{arg_1.string});
        return EvalError.BadFuncCall;
    }

    return ret;
}
