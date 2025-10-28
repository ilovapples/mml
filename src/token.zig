const std = @import("std");
const expect = std.testing.expect;

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

    OpNot, // this is boolean not
    OpNegate,
    OpUnaryNothing,
    OpTilde,
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
    Squote,
    Backtick,

    Colon,
    Semicolon,
    Comma,

    Hashtag,
    Question,
    Backslash,
    Dollar,
    Amper,
    Pipe,

    Invalid,
    Whitespace,
    Eof,

    const Self = @This();

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
            .Squote => "'''",
            .Backtick => "'`'",
            .Colon => "':'",
            .Semicolon => "';'",
            .Comma => "','",
            .Hashtag => "'#'",
            .Question => "'?'",
            .Backslash => "'\\'",
            .Dollar => "'$'",
            .Amper => "'&'",
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

    const Self = @This();

    pub fn init(string: []const u8, looking_for_int: bool) Self {
        return if (string.len == 0) .{.string = string, .type = .Eof} else switch (string[0]) {
            '.', '^', '+', '-', '*', '/', '%',
            '(', ')', '{', '}', '[', ']', ',', ';',
            '|', '~' => Self{.string = string[0..1], .type = toktype_by_char[string[0]]},

            '<', '>' => if (string.len > 1 and string[1] == '=') Self{
                .string = string[0..2],
                .type = switch (string[0]) {
                    '<' => .OpLessEq,
                    '>' => .OpGreaterEq,
                    else => .Invalid,
                },
            } else Self{.string = string[0..1], .type = toktype_by_char[string[0]]},

            '=', '!' => blk: {
                if ((string.len > 1 and string[1] != '=') or string.len == 1) {
                    break :blk Self{.string = string[0..1], .type = toktype_by_char[string[0]]};
                } else if (string.len > 2 and string[2] != '=') {
                    break :blk Self{.string = string[0..2], .type = switch (string[0]) {
                        '=' => .OpEq,
                        '!' => .OpNotEq,
                        else => .Invalid,
                    }};
                } else {
                    break :blk Self{.string = string[0..3], .type = switch (string[0]) {
                        '=' => .OpExactEq,
                        '!' => .OpExactNotEq,
                        else => .Invalid,
                    }};
                }
            },

            '0'...'9' => blk: {
                var index: usize = 0;
                while (index < string.len and std.ascii.isDigit(string[index])) : (index += 1) {}
                if (!looking_for_int and index < string.len and string[index] == '.') {
                    index += 1;
                    while (index < string.len and std.ascii.isDigit(string[index])) : (index += 1) {}
                }

                break :blk Self{.string = string[0..index], .type = .Number};
            },
            
            'a'...'z', 'A'...'Z', '_' => blk: {
                var index: usize = 1;
                while (index < string.len and
                    (std.ascii.isAlphanumeric(string[index]) or string[index] == '_'))
                    : (index += 1) {}

                break :blk Self{.string = string[0..index], .type = .Ident};
            },

            '@' => blk: {
                if (string[1] != '_' and !std.ascii.isAlphabetic(string[1])) {
                    break :blk Self{.string = string, .type = .Invalid };
                }
                var index: usize = 2;
                while (index < string.len and
                    (std.ascii.isAlphanumeric(string[index]) or string[index] == '_'))
                    : (index += 1) {}

                break :blk Self{.string = string[1..index], .type = .BuiltinIdent};
            },
            '"' => blk: {
                var index: usize = 1;
                while (index < string.len and string[index] != '"') : (index += 1) { }
                if (index == string.len) {
                    std.log.err("unterminated string literal", .{});
                    break :blk Self{.string = string, .type = .Invalid};
                }
                break :blk Self{.string = string[0..index+1], .type = .String};
            },
            
            else => Self{.string = string, .type = .Invalid},
        };
    }

    pub fn format(
        self: Self,
        w: *std.Io.Writer,
    ) !void {
        try w.print("{{ .string=\"{s}\", .type=.{t} }}", .{self.string, self.type});
    }

    pub fn isOp(self: Self) bool {
        return @intFromEnum(self.type) < @intFromEnum(TokenType.NotOp);
    }
    pub fn isBinaryOp(self: Self) bool {
        return @intFromEnum(self.type) < @intFromEnum(TokenType.OpNot);
    }
    pub fn isUnaryOp(self: Self) bool {
        return self.isOp() and !self.isBinaryOp();
    }
    pub fn isRightAssocOp(self: Self) bool {
        return self.type == .OpPow or self.isUnaryOp();
    }
};

test "token.Token.init" {
    try expect(Token.init(">=", null).type == .OpGreaterEq);
    try expect(Token.init("<=", null).type == .OpLessEq);
}

test "token.opSuite" {
    try expect(Token.init("+ -", null).isOp());
    try expect(!Token.init("9 .", null).isOp());
    try expect(Token.init("/", null).isBinaryOp());
    try expect(Token.init("! ", null).isUnaryOp());
    try expect(!Token.init("!", null).isBinaryOp());
    try expect(Token.init("^  ", null).isRightAssocOp());
}


pub const toktype_by_char = [_]TokenType{
    .Eof, // 0x00
    .Invalid,
    .Invalid,
    .Invalid,
    .Eof,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Whitespace,
    .Whitespace,
    .Whitespace,
    .Whitespace,
    .Whitespace,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Whitespace, // 0x20

    .OpNot, // 0x21
    .Dquote,
    .Hashtag,
    .Dollar,
    .OpMod,
    .Amper,
    .Squote,
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
    .Colon,
    .Semicolon,
    .OpLess,
    .OpAssertEqual,
    .OpGreater,
    .Question,
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
    .Backslash,
    .CloseBracket,
    .OpPow,
    .Underscore,
    .Backtick,
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
    .Invalid, // 0x7f

    .Invalid, // 0x80 onwards
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
    .Invalid,
};

test "token.toktype_by_char" {
    try expect(toktype_by_char.len == 256);
    try expect(toktype_by_char['a'] == .Letter);
    try expect(toktype_by_char['B'] == .Letter);
    try expect(toktype_by_char['('] == .OpenParen);
    try expect(toktype_by_char['_'] == .Underscore);
    try expect(toktype_by_char['`'] == .Backtick);
    try expect(toktype_by_char['\\'] == .Backslash);
    try expect(toktype_by_char['~'] == .OpTilde);
    try expect(toktype_by_char['|'] == .Pipe);
    try expect(toktype_by_char['&'] == .Amper);
}
