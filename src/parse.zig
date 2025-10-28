const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const expect = std.testing.expect;

const token = @import("token.zig");
const Token = token.Token;
const TokenType = token.TokenType;
const expr = @import("expr.zig");
const Expr = expr.Expr;

const ParserState = struct {
    string: []const u8,
    cur_pos: usize = 0,
    current_token: ?Token = null,
    peeked_token: ?Token = null,
    looking_for_int: bool = false,
    in_pipe_block: bool = false,
    arena: *ArenaAllocator,

    const Self = @This();

    pub fn init(arena: *ArenaAllocator, string: []const u8) Self {
        return .{
            .string = string,
            .arena = arena,
        };
    }

    pub fn peekToken(self: *Self) Token {
        // skip whitespace
        const next_char_after_whitespace = std.mem.indexOfNonePos(
            u8, self.string, self.cur_pos, &std.ascii.whitespace);

        self.peeked_token = Token.init(
            self.string[next_char_after_whitespace orelse self.string.len..],
            self.looking_for_int);
        return self.peeked_token.?;
    }

    pub fn nextToken(self: *Self) Token {
        const ret_tok = self.peeked_token orelse self.peekToken();
        self.cur_pos = ret_tok.string.ptr + ret_tok.string.len - self.string.ptr;
        self.current_token = ret_tok;

        if (self.peeked_token) |_| self.peeked_token = null;

        return ret_tok;
    }

    pub const ParseError = error{
        ExpectedExpr,
        NullExpr,
        UnterminatedVectorLiteral,
    } || Allocator.Error;
    pub fn parseExprRecurse(self: *Self, max_preced: u8) ParseError!*Expr {
        const alloc = self.arena.allocator();

        var tok = self.nextToken();
        var left = try alloc.create(Expr);
        errdefer alloc.destroy(left);

        if (tok.type == .OpSub or tok.type == .OpAdd or tok.isUnaryOp()) {
            const new_token_type = switch (tok.type) {
                .OpAdd => .OpUnaryNothing,
                .OpSub => .OpNegate,
                else => tok.type,
            };

            const operand = try self.parseExprRecurse(operator_precedence[@intFromEnum(new_token_type)]);
            left.* = @unionInit(Expr, "operation", .{
                .op = new_token_type,
                .left = operand,
                .right = null,
            });
        } else if (tok.type == .Ident or tok.type == .BuiltinIdent) {
            if (self.peekToken().type == .OpenBrace) { // function call
                const name_expr = try alloc.create(Expr);
                if (tok.type == .Ident) {
                    name_expr.* = @unionInit(Expr, "identifier",
                        try alloc.dupe(u8, tok.string));
                } else {
                    name_expr.* = @unionInit(Expr, "builtin_ident", 
                        try alloc.dupe(u8, tok.string));
                }

                left.* = @unionInit(Expr, "operation", .{
                    .op = .OpFuncCall,
                    .left = name_expr,
                    .right = null,
                });

                _ = self.nextToken();

                left.operation.right = try alloc.create(Expr);
                var temp_arrlist = try std.ArrayList(*Expr).initCapacity(alloc, 1);

                while (true) {
                    if (self.peekToken().type == .CloseBrace) {
                        break;
                    }
                    const next_expr = try self.parseExprRecurse(parser_max_preced);
                    try temp_arrlist.append(alloc, next_expr);

                    if (self.nextToken().type != .Comma) {
                        break;
                    }
                }

                left.operation.right.?.* = @unionInit(Expr, "vector", try temp_arrlist.toOwnedSlice(alloc));

                if (self.current_token.?.type != .CloseBrace) {
                    _ = self.nextToken();
                }
            } else {
                if (tok.type == .Ident) {
                    left.* = @unionInit(Expr, "identifier", try alloc.dupe(u8, tok.string));
                } else {
                    left.* = @unionInit(Expr, "builtin_ident", try alloc.dupe(u8, tok.string));
                }
            }
        } else if (tok.type == .OpenParen) { // parentheses
            alloc.destroy(left);
            left = try self.parseExprRecurse(parser_max_preced);
            if (self.nextToken().type != .CloseParen) {
                _ = self.nextToken();
            }
        } else if (tok.type == .OpenBracket) { // vector literal
            var temp_arrlist = try std.ArrayList(*Expr).initCapacity(alloc, 2);
            errdefer temp_arrlist.deinit(alloc);
            if (self.peekToken().type == .CloseBracket) {
                left.* = @unionInit(Expr, "vector", &[_]*Expr{});
                tok = self.nextToken();
            }
            while (tok.type != .CloseBracket) {
                const e = try self.parseExprRecurse(parser_max_preced);
                try temp_arrlist.append(alloc, e);

                tok = self.nextToken();
                if (tok.type != .CloseBracket and tok.type != .Comma) {
                    // maybe I should use zig error unions for this kind of thing...
                    std.log.err("unexpected token .{t} ({s}) found after element in vector "
                             ++ "literal (expected .CloseBracket (']') or .Comma (','))", .{
                        tok.type, tok.type.stringify() orelse "you shouldn't ever see this text; please post an issue"
                    });

                    return ParseError.UnterminatedVectorLiteral;
                }
            }

            left.* = @unionInit(Expr, "vector", try temp_arrlist.toOwnedSlice(alloc));
        } else if (tok.type == .Pipe) {
            if (self.peekToken().type == .Pipe) {
                std.log.err("expected expression in pipe block ({s})", .{
                    TokenType.Pipe.stringify() orelse "you shouldn't ever see this text; please post an issue"
                });
                return ParseError.ExpectedExpr;
            }

            self.in_pipe_block = true;

            alloc.destroy(left);
            left = try self.parseExprRecurse(parser_max_preced);

            if (self.nextToken().type != .Pipe) {
                _ = self.nextToken();
            }

            self.in_pipe_block = false;

            const opnode = try alloc.create(Expr);
            opnode.* = @unionInit(Expr, "operation", .{
                .op = .Pipe,
                .left = left,
                .right = null,
            });

            left = opnode;
        } else if (tok.type == .Number) {
			if (self.looking_for_int) {
				left.* = @unionInit(Expr, "integer", std.fmt.parseInt(i64, tok.string, 10) catch |e| blk: switch (e) {
                    std.fmt.ParseIntError.Overflow => {
                        std.log.err("integer read as '{s}' has a magnitude "
                                 ++ "larger than about 9.2 quintillion (2^63). "
								 ++ "assuming infinity.", .{tok.string});
						break :blk std.math.maxInt(i64);
                    },
                    std.fmt.ParseIntError.InvalidCharacter => {
						std.log.err("failed to read '{s}' as an integer. "
								 ++ "assuming 0.", .{tok.string});
						break :blk 0;
					},
				});
            } else {
                left.* = @unionInit(Expr, "real_number", std.fmt.parseFloat(f64, tok.string) catch blk: {
					std.log.err("failed to read '{s}' as a real number. "
						     ++ "assuming NaN (not a number).", .{tok.string});
					break :blk std.math.nan(f64);
				});
            }
            self.looking_for_int = false;
        } else if (tok.type == .String) {
            left.* = @unionInit(Expr, "string", 
                try alloc.dupe(u8, tok.string[1..tok.string.len-1]));
        } else {
            std.log.err("null expression. found token .{t} ({s})", .{
				tok.type,
				tok.type.stringify() orelse "you shouldn't ever see this text; please post an issue",
			});
            return ParseError.NullExpr;
        }

        while (true) {
            var op_tok = self.peekToken();

            const do_advance = switch (op_tok.type) {
                .Ident, .Number, .OpenParen, .OpenBracket, .Pipe => blk: {
                    if (op_tok.type == .Pipe) {
                        break :blk true;
                    }
                    op_tok.type = .OpMul;
                    break :blk false;
                },
                else => true,
            };
            if (@intFromEnum(op_tok.type) > @intFromEnum(TokenType.NotOp)) break;

            const preced = operator_precedence[@intFromEnum(op_tok.type)];
            if (preced > max_preced) break;

            if (do_advance) _ = self.nextToken();

            if (op_tok.type == .OpDot) self.looking_for_int = true;

            const right = self.parseExprRecurse(if (op_tok.isRightAssocOp()) preced else preced - 1) catch {
                std.log.err("expected expression after operator .{t} ({s})", .{
                    op_tok.type,
                    op_tok.type.stringify() orelse "you shouldn't ever see this text; please post an issue",
                });
                return ParseError.ExpectedExpr;
            };

            const opnode = try alloc.create(Expr);
            opnode.* = @unionInit(Expr, "operation", .{
                .op = op_tok.type,
                .left = left,
                .right = right,
            });

            left = opnode;
        }
        
        return left;
    }

};
pub fn parseExpr(arena: *ArenaAllocator, str: []const u8) !*Expr {
    var state = ParserState.init(arena, str);

    return try state.parseExprRecurse(parser_max_preced);
}

pub fn parseStatements(arena: *ArenaAllocator, str: []const u8) ![]*Expr {
    const alloc = arena.allocator();

    var temp = try std.ArrayList(*Expr).initCapacity(alloc, 1);
    errdefer temp.deinit(alloc);

    var state = ParserState.init(arena, str);
    try temp.append(alloc, try state.parseExprRecurse(parser_max_preced));
    while (state.nextToken().type == .Semicolon) {
        try temp.append(alloc, try state.parseExprRecurse(parser_max_preced));
    }

    return try temp.toOwnedSlice(alloc);
}

test "parser.ParserState.peekToken" {
    var state = ParserState.init("hello * 9.2");
    const peeked = state.peekToken();
    try expect(peeked.type == .Ident and std.mem.eql(u8, peeked.string, "hello"));
}

test "parser.ParserState.nextToken" {
    var state = ParserState.init("print{cos{31.9} * pi^7}");

    const expected = [_]Token{
        .{ .string = "print", .type = .Ident },
        .{ .string = "{", .type = .OpenBrace },
        .{ .string = "cos", .type = .Ident },
        .{ .string = "{", .type = .OpenBrace },
        .{ .string = "31.9", .type = .Number },
        .{ .string = "}", .type = .CloseBrace },
        .{ .string = "*", .type = .OpMul },
        .{ .string = "pi", .type = .Ident },
        .{ .string = "^", .type = .OpPow },
        .{ .string = "7", .type = .Number },
        .{ .string = "}", .type = .CloseBrace },
    };

    var i: usize = 0;
    var cur_tok = state.nextToken();
    try expect(cur_tok.type == expected[i].type and
        std.mem.eql(u8, cur_tok.string, expected[i].string));
    i += 1;
    while (state.cur_pos < state.string.len) : (i += 1) {
        cur_tok = state.nextToken();
        try expect(cur_tok.type == expected[i].type and
            std.mem.eql(u8, cur_tok.string, expected[i].string));
    }
}

test "parser.parseExpr" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;

    const e = try parseExpr("x = x / 9.9", allocator);
    _ = e;
    _ = stdout;
    //try e.print(.{.writer = stdout});
}

const parser_max_preced = 15;

pub const operator_precedence = [_]u8{
    1, // OpFuncCall,
    1, // OpDot,
    1, // OpAt,

    2, // OpPow,
    2, // OpRoot,

    3, 3, 3, // OpMul, OpDiv, OpMod,
    4, 4, // OpAdd, OpSub,

    6, 6, 6, 6, // OpLess, OpGreater, OpLessEq, OpGreaterEq,
    7, 7, // OpEq, OpNotEq,
    7, 7, // OpExactEq, OpExactNotEq,

    14, // OpAssertEqual,

    2, 2, 2, 2, // OpNot, OpNegate, OpUnaryNothing, OpTilde
};
