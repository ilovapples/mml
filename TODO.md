# todo list 
- [x] check for unterminated string literal
- [x] add ~~'root'~~, ~~'atan2'~~, ~~'logb'~~ to lib/math and ~~'sort'~~ to lib/stdmml
- [x] add 'sign' function to lib/math
- [x] finish fully implementing builtin functions/constants
- [x] actually add the prompt because that initial commit message was a lie and it doesn't exist yet
- [x] change Expr printing functions to catch printing errors themselves because that's annoying
- [x] make evaluation return a smaller set of errors (i should be catching more of them)
- [x] also functions at some point would be good, but they're not a priority
- [x] add error message for unrecognized characters in a token (like '&' doesn't print an error message, it just returns a null/invalid token; not sure how that works)
- [ ] return errors (not error unions, but the specific problems) in a way that can be stored in a variable/struct and 'rendered' into a string
- [x] fix the error message in ~~[tests/bug1.log](tests/bug1.log)~~
- [x] add debug output to indicate when parsing and evaluation are complete and how long it took (with `--debug` flag)
- [x] @undef(ident) builtin to undefine a user-defined identifier
- [x] somehow fix print{...} printed stuff showing up to the left of the output bars (maybe remove the bars?)
- [x] copy contents of strings need into the Expr.string field, instead of just saving their position
* [x] can merge prompt branch
    - [x] special codes (new Expr type) stored in constants that can interact with certain parts of the application (such as the prompt) (like `exit` and `clear` and such)
- [x] add a (zig) function to assert that an Expr is of a certain type and log an error if not
- [x] fix the issue in ~~[tests/bug2.log](tests/bug2.log)~~
- [x] fix out-of-bounds with `@` as the input string.
* [ ] documentation related features
    - [x] partially automated generation of a list of all functions that are implemented (with a command-line option to show it)
    - [x] copy over syntax guide from [maths](https://github.com/ilovapples/maths) because it's basically the same thing, but update with new stuff (and rewrite the first paragraph, it's practically illegible)
* [ ] other features for prompt/REPL
    - [ ] autocompletion/suggestions
    - [ ] history (like up and down arrow on a shell)
        * [x] up arrow
        * [ ] down arrow
* [ ] other features (misc.)
    - [x] some way to put the output of `@dbg{expr}` into a `string` from MML.
    - [ ] make `{}` a proper operation on `function`-type expressions.
- [ ] make argument parser read arguments as they're requested. will help it know how to deal with stuff like '-h 9', where '-h' is a bool option and
      9 shouldn't be considered its value, but is. it's impossible for it to know how to deal with it right now. (partially implemented but not in this repo yet)
- [x] fix bug in ~~[tests/bug3.log](tests/bug3.log)~~ (seems to happen when taking the absolute value of a nested vector)
- [x] also the annoying bug in [tests/bug4.log](tests/bug4.log). seems like `@dbg_ident` doesn't check that expression passed to it is an identifier
    


# todos from [maths](https://github.com/ilovapples/maths)
- [x] negation operator!! negative numbers are annoying without it
- [x] insert multiplication operation between consecutive values between which there is no operation (so 3i would parse the same as 3*i)
- [x] variable assignment (statements?)
- [x] assigned variables in the prompt can't be accessed on a line past their definition as the right value, but they can as the left value (so `print{x}` would say `x` is undefined)
- [x] fix memory leaks caused by adding variable assignment (memory leaks for literally everything?), then rebase dev back into main
- [x] fix segfault when using `--set_var:` to insert a variable when the variable value string is empty (e.g. `--set_var:A=`)
- [x] syntax guide and other documentation
- [x] === operator for exact equality (do away with --no-estimate-equality)
- [x] interactive prompt (like python's IDLE) (pretty much done)
- [x] fix 'ans' returning the last value evaluated rather than the output of the last prompt
- [x] change prompt to use MML_parse_stmts~~_to_ret~~ to maybe fix variables not working past their definition?
- [x] fix random memory leaks (probably caused by evaluator but I can't figure out the root cause)
- [x] fix the identifier 'a' having inexplicable bugs (--set_var doesn't work with it, it never flags an 'undefined variable' error even when it should, etc.)
- [x] vector literals have regressed; each element is (null) or the first thing that was evaluated (no idea why) (forgot to add a memcpy when transitioning to arena but we're good now)
- [x] 'Nothing' type to return from stuff like `println` (basically `void`)
- [x] improve `MML_print_expr` to print the AST in a more similar format to the syntax used with `tests/ast_test.h`
- [x] ~~add Type type so I can add a `cast{type, val}` function~~ we're just using strings for those (check out `ExprType` in `builtin_as` in `src/mml-core/stdmml.zig`), might change though
- [x] fix prompt so it reads data in 1 byte minimum chunks (now it's 8 bytes for one character read,
      so stdin doesn't work unless you're currently the one using the prompt via shell input or something)
- [ ] add check for recursive variable definition (currently segfaults from stack overflow)
- [x] support scientific notation in floating constants
- [x] support underscore separators in numerical constants
