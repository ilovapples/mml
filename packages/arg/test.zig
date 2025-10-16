const std = @import("std");

var usage_column2: usize = 30;

pub const ArgParser = struct {
    alloc: std.mem.Allocator,
    fields: std.StringHashMap([]const u8),
    usage_str: std.ArrayList(u8),
    program_name: []const u8,

    const Self = @This();
    
    pub fn parse(allocator: std.mem.Allocator, args: []const [:0]u8) !Self {
        var pa = Self{
            .alloc = allocator,
            .fields = .init(allocator),
            .usage_str = try .initCapacity(allocator, 50),
            .program_name = args[0],
        };

        try pa.usage_str.print(pa.alloc, "usage: {s} [options]\n\noptions:\n", .{pa.program_name});

        var consume_next: bool = false;
        for (args[1..], 1..) |cur, i| {
            if (consume_next) {
                consume_next = false;
                continue;
            }
            if (std.mem.eql(u8, cur[0..2], "--")) {
                const eql_idx = std.mem.indexOfScalar(u8, cur, '=');
                if (eql_idx) |delim| { // --field=value
                    const up_to = cur[2..delim];
                    if (up_to.len != 0) {
                        try pa.fields.put(up_to, cur[delim+1..]);
                    }
                } else { // --field value
                    if (i >= args.len - 1) { // '--field' means a true boolean
                        try pa.fields.put(cur[2..], args[i][0..0]);
                    } else { // `--field value`
                        try pa.fields.put(cur[2..], args[i+1]);
                    }
                    consume_next = true;
                }
            }
        }

        return pa;
    }
    pub fn deinit(self: *Self) void {
        self.fields.deinit();
        self.usage_str.deinit(self.alloc);
    }

    pub fn option(
        self: *Self,
        comptime T: type,
        comptime name: []const u8,
        comptime desc: []const u8) ?T {
        self.usage_str.print(self.alloc, "  --{s} {s}\x1b[{}G{s}\n", .{
            name,
            if (T == bool) "" else "value",
            usage_column2,
            desc
        }) catch {};

        const str_val = self.fields.get(name) orelse return null;
        _ = self.fields.remove(name);

        return switch (@typeInfo(T)) {
            .int => std.fmt.parseInt(T, str_val, 10) catch null,
            .float => std.fmt.parseFloat(T, str_val) catch null,
            .bool => blk: {
                if (str_val.len == 0) break :blk true;
                if (std.mem.eql(u8, str_val, "true")) break :blk true;
                if (std.mem.eql(u8, str_val, "false")) break :blk false;
                break :blk null;
            },
            .pointer => if (T == []const u8) str_val else null,
            else => null,
        };
    }

    pub fn finalize(self: Self) bool {
        if (self.fields.count() > 0) {
            warnArgError("found unidentified argument(s) with values:", .{});
            self.printFields();
            return false;
        }

        return true;
    }

    fn warnArgError(comptime fmt: []const u8, args: anytype) void {
        std.log.warn("argument error: " ++ fmt, args);
    }

    pub fn printFields(self: Self) void {
        var it = self.fields.iterator();
        while (it.next()) |e| {
            std.debug.print("\"{s}\": \"{s}\",\n", .{e.key_ptr.*, e.value_ptr.*});
        }
    }
    
    pub fn printUsage(self: Self, writer: *std.Io.Writer) void {
        writer.writeAll(self.usage_str.items) catch return;
    }
};
