const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

pub const TokenType = enum(u32) {
    // operator tokens
    OpFuncCall,
    OpDot,
    OpAt,

    OpPow,
    OpRoot,

    OpMul, OpDiv, OpMod,
    OpAdd, OpSub,

    OpLess, OpGreater,
    OpLessEq, OpGreaterEq,
    OpEq, OpNotEq,
    OpExactEq, OpExactNotEq,

    OpAssertEqual,

    OpNot,
    OpNegate,
    OpUnaryNothing,
    OpTilde,
    // marker token for the end of the operators (used in isOp() and friends)
    NotOp,

    // non-operator tokens
    String,
    Ident,
    BuiltinIdent,
    Number,

    Digit, // not really used
    Letter,
    Underscore,

    OpenParen,
    CloseParen,

    OpenBrace,
    CloseBrace,

    OpenBracket,
    CloseBracket,

    Dquote,
    //Squote,

    Semicolon,
    Comma,

    Pipe,

    Invalid,
    InvalidCharacter,
    Whitespace,
    Eof,

    const Self = @This();

    /// return whether the token type is an operator
    pub fn isOp(self: TokenType) bool {
        return @intFromEnum(self) < @intFromEnum(TokenType.NotOp);
    }
    /// return whether the token type is an operator that takes two operands
    pub fn isBinaryOp(self: TokenType) bool {
        return @intFromEnum(self) < @intFromEnum(TokenType.OpNot);
    }
    /// return whether the token type is an operator that takes one operand
    pub fn isUnaryOp(self: TokenType) bool {
        return self.isOp() and !self.isBinaryOp();
    }
    /// return whether the token type is an operator and the parser should evaluate it right-associatively
    pub fn isRightAssocOp(self: TokenType) bool {
        return self == .OpPow or self.isUnaryOp();
    }

    /// return a string-ified version of the token type for user-side output.
    /// return type is ?[]const u8 because it might return null in the future.
    pub fn stringify(self: Self) ?[]const u8 {
        return switch (self) {
            .OpFuncCall => "func_name{args}",
            .OpDot => "'.'",
            .OpAt => "'@'",
            .OpPow => "'^'",
            .OpRoot => "root{x}",
            .OpMul => "'*'",
            .OpDiv => "'/'",
            .OpMod => "'%'",
            .OpAdd => "'+'",
            .OpSub => "'-'",
            .OpLess => "'<'",
            .OpGreater => "'>'",
            .OpLessEq => "'<='",
            .OpGreaterEq => "'>='",
            .OpEq => "'=='",
            .OpNotEq => "'!='",
            .OpExactEq=> "'==='",
            .OpExactNotEq => "'!=='",
            .OpAssertEqual => "'='",
            .OpNot => "!x",
            .OpNegate => "-x",
            .OpUnaryNothing => "+x",
            .OpTilde => "'~'",
            .String => "any sequence of characters enclosed in double-quotes ('\"')",
            .BuiltinIdent => "an identifier prefixed by an '@' symbol",
            .Ident => "alphanumeric string that starts with a letter (can contain underscores)",
            .Number => "decimal number like 3.93",
            .Digit => "0-9",
            .Letter => "A-z",
            .Underscore => "'_'",
            .OpenParen => "'('",
            .CloseParen => "')'",
            .OpenBrace => "'{'",
            .CloseBrace => "'}'",
            .OpenBracket => "'['",
            .CloseBracket => "']'",
            .Dquote => "'\"'",
            .Semicolon => "';'",
            .Comma => "','",
            .Pipe => "'|'",
            .Whitespace => "' '",
            .Eof => "end of the input string/file",
            else => "not a valid token",
        };
    }
};

pub const Token = struct {
    string: []const u8,
    type: TokenType,

    const TokenInitConfig = struct {
        looking_for_int: bool = false,
    };

    /// construct a token from a string (primary function to construct a token)
    pub fn from(string: []const u8, tic: TokenInitConfig) Token {
        return if (string.len == 0) .{.string = string, .type = .Eof} else switch (string[0]) {
            // single character operator/syntax tokens
            '.', '^', '+', '-', '*', '/', '%',
            '(', ')', '{', '}', '[', ']', ',', ';',
            '|', '~' => .{.string = string[0..1], .type = toktype_by_char[string[0]]},

            // relational operators
            '<', '>' => if (string.len > 1 and string[1] == '=') .{
                .string = string[0..2],
                .type = switch (string[0]) {
                    '<' => .OpLessEq,
                    '>' => .OpGreaterEq,
                    else => .Invalid,
                },
            } else .{.string = string[0..1], .type = toktype_by_char[string[0]]},

            // equality operators
            '=', '!' => blk: {
                if ((string.len > 1 and string[1] != '=') or string.len == 1) {
                    break :blk .{.string = string[0..1], .type = toktype_by_char[string[0]]};
                } else if (string.len > 2 and string[2] != '=') {
                    break :blk .{.string = string[0..2], .type = switch (string[0]) {
                        '=' => .OpEq,
                        '!' => .OpNotEq,
                        else => .Invalid,
                    }};
                } else {
                    break :blk .{.string = string[0..3], .type = switch (string[0]) {
                        '=' => .OpExactEq,
                        '!' => .OpExactNotEq,
                        else => .Invalid,
                    }};
                }
            },

            // number (integer or decimal depending on tic.looking_for_int)
            '0'...'9' => blk: {
                var index: usize = 0;
                while (index < string.len and std.ascii.isDigit(string[index])) : (index += 1) {}
                if (!tic.looking_for_int and index < string.len and string[index] == '.') {
                    index += 1;
                    while (index < string.len and std.ascii.isDigit(string[index])) : (index += 1) {}
                }

                break :blk .{.string = string[0..index], .type = .Number};
            },
            
            // normal identifiers (ex. 'x', 'a', 'ba_9')
            'a'...'z', 'A'...'Z', '_' => blk: {
                var index: usize = 1;
                while (index < string.len and
                    (std.ascii.isAlphanumeric(string[index]) or string[index] == '_'))
                    : (index += 1) {}

                break :blk .{.string = string[0..index], .type = .Ident};
            },

            // builtin identifiers (ex. '@dbg')
            '@' => blk: {
                if (string[1] != '_' and !std.ascii.isAlphabetic(string[1])) {
                    break :blk .{.string = string, .type = .Invalid };
                }
                var index: usize = 2;
                while (index < string.len and
                    (std.ascii.isAlphanumeric(string[index]) or string[index] == '_'))
                    : (index += 1) {}

                break :blk .{.string = string[1..index], .type = .BuiltinIdent};
            },

            // strings (ex. '"hello"')
            '"' => blk: {
                var index: usize = 1;
                while (index < string.len and string[index] != '"') : (index += 1) { }
                if (index == string.len) {
                    std.log.err("unterminated string literal", .{});
                    break :blk .{.string = string, .type = .Invalid};
                }
                break :blk .{.string = string[0..index+1], .type = .String};
            },
            
            else => .{ .string = &.{}, .type = .InvalidCharacter },
        };
    }

    /// format a token (for debugging)
    pub fn format(
        self: Token,
        w: *std.Io.Writer,
    ) !void {
        try w.print("{{ \"{s}\", .{t} }}", .{self.string, self.type});
    }
};

test "token.Token.from" {
    try expectEqual(.OpGreaterEq, Token.from(">=", .{}).type);
    try expectEqual(.OpLessEq, Token.from("<=", .{}).type);
    try expectEqual(.Number, Token.from("921.43", .{}).type);
}

test "token.opSuite" {
    try expect(Token.from("+ -", .{}).type.isOp());
    try expect(!Token.from("9 .", .{}).type.isOp());
    try expect(Token.from("/", .{}).type.isBinaryOp());
    try expect(Token.from("! ", .{}).type.isUnaryOp());
    try expect(!Token.from("!", .{}).type.isBinaryOp());
    try expect(Token.from("^  ", .{}).type.isRightAssocOp());
}


pub const toktype_by_char = [_]TokenType{
    .Eof, // 0x00
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .Eof, // literal EOF (ctrl+d)
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .Whitespace,
    .Whitespace,
    .Whitespace,
    .Whitespace,
    .Whitespace,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .Whitespace, // 0x20

    .OpNot, // 0x21
    .Dquote,
    .InvalidCharacter, // hashtag '#'
    .InvalidCharacter, // dollar sign '$'
    .OpMod,
    .InvalidCharacter, // ampersand '&'
    .InvalidCharacter, // single quote '\''
    .OpenParen,
    .CloseParen,
    .OpMul,
    .OpAdd,
    .Comma,
    .OpSub,
    .OpDot,
    .OpDiv,
    .Digit,
    .Digit,
    .Digit,
    .Digit,
    .Digit,
    .Digit,
    .Digit,
    .Digit,
    .Digit,
    .Digit,
    .InvalidCharacter, // colon ':'
    .Semicolon,
    .OpLess,
    .OpAssertEqual,
    .OpGreater,
    .InvalidCharacter, // question mark '?'
    .OpAt,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .OpenBracket,
    .InvalidCharacter, // backslash '\'
    .CloseBracket,
    .OpPow,
    .Underscore,
    .InvalidCharacter, // backtick '`'
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .Letter,
    .OpenBrace,
    .Pipe,
    .CloseBrace,
    .OpTilde,
    .InvalidCharacter, // 0x7f

    .InvalidCharacter, // 0x80 onwards
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
    .InvalidCharacter,
};

test "token.toktype_by_char" {
    try expectEqual(256, toktype_by_char.len);
    try expectEqual(.Letter, toktype_by_char['a']);
    try expectEqual(.Letter, toktype_by_char['B']);
    try expectEqual(.OpenParen, toktype_by_char['(']);
    try expectEqual(.Underscore, toktype_by_char['_']);
    try expectEqual(.InvalidCharacter, toktype_by_char['`']);
    try expectEqual(.InvalidCharacter, toktype_by_char['\\']);
    try expectEqual(.OpTilde, toktype_by_char['~']);
    try expectEqual(.Pipe, toktype_by_char['|']);
    try expectEqual(.InvalidCharacter, toktype_by_char['&']);
    try expectEqual(.Digit, toktype_by_char['9']);
}
