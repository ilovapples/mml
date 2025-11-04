### Meta-note(?):
This file will usually be empty (except for this note), unless
1. I forgot to clear it since the last time I wrote something here, or
2. I accidentally made a commit much larger than it should be, and the list of changes/additions/deletions wouldn't fit in the commit message.

## Commit Notes
(if this date is earlier than the date of the commit you're on, I forgot to clear it; it's fine, I'll get around to it)
date of writing: 25/11/03
- removed `mml-core` import so it's not a pain to import `mml` (math and stdmml still exist, they're just not a separate module in build.zig)
* updates to `arg_parse`; added short and positional options, and improved usage message printing
    - also added some short option alternatives in `src/main.zig`
- changed `src/config.zig` to `src/Config.zig`, expanding `config.Config` to just `Config` (it's the only thing in the file anyway).
- changed a bunch of source files to have a `const mml = @import("root.zig");` declaration to make them look a bit more uniform to an actual module import (is this idiomatic? I'm not sure)
- changed `Expr.format` (default `{f}` formatter) to print the AST instead of the value of an `Expr`
- changed `Token.format` (default `{f}` formatter) (even though I don't think it's ever used) to be a bit simpler (`{ "[string]", .[type] }`)
- added `src/error_msgs.zig` file for the future (it isn't done yet, and isn't being used anywhere yet, but hopefully both of those statements will become false at some point soon).
- made config optional in `Evaluator.init`
- updated [docs/README.md](./docs/README.md) with some Zig-rewrite specific updates (and a clarification about nested pipe operators)
- changed prompt to use the [mibu](https://github.com/xyaman/mibu) library to toggle terminal raw mode, to improve cross-platform compatibility
- changed `Token.init` to take TokenInitConfig, because it's less of a pain and looks better to write `.{}` than to write `false` when the field is not relevant.
- changed some tests to use `expectEqual`, and std.testing.allocator instead of std.heap.page_allocator.
- changed language in evaluator error message when calling an unknown function with zero arguments to say "with zero arguments" instead of "without zero arguments"
- added some doc comments in src/token.zig.
- made a bunch of characters that had their own TokenType entry but weren't used anywhere 'InvalidCharacter's, so error messages can be easier to understand.
- changed Alt+Right behavior in prompt to go to one character past the end of the line instead of just the last character
- added a [README.md](README.md)
