const std = @import("std");

pub const core = @import("mml-core/root.zig");
pub const expr = @import("expr.zig");
pub const Config = @import("Config.zig");
pub const token = @import("token.zig");
pub const parse = @import("parse.zig");
pub const Evaluator = @import("Evaluator.zig");
pub const error_msgs = @import("error_msgs.zig");

/// Struct that holds allocators used by the library. Must be initialized with
/// the same allocator for both 'expr_pool' and 'arena'.
///
/// 'expr_pool' is a memory pool to make Expr allocations faster. 'arena' is
/// used for any other allocations.
pub const Allocators = struct {
    expr_pool: std.heap.MemoryPool(expr.Expr),
    arena: std.heap.ArenaAllocator,

    pub fn init(alloc: std.mem.Allocator) Allocators {
        return .{
            .expr_pool = .init(alloc),
            .arena = .init(alloc),
        };
    }
    pub fn deinit(allocs: *Allocators) void {
        allocs.expr_pool.deinit();
        allocs.arena.deinit();
    }
};

test {
    std.testing.refAllDecls(@This());
}
