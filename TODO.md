# todo list 
- [x] check for unterminated string literal <br />
- [x] add ~~'root'~~, ~~'atan2'~~, ~~'logb'~~ to lib/math and ~~'sort'~~ to lib/stdmml <br />
- [x] add 'sign' function to lib/math <br />
- [x] finish fully implementing builtin functions/constants <br />
- [x] actually add the prompt because that initial commit message was a lie and it doesn't exist yet <br />
- [x] change Expr printing functions to catch printing errors themselves because that's annoying <br />
- [x] make evaluation return a smaller set of errors (i should be catching more of them) <br />
- [ ] also functions at some point would be good, but they're not a priority <br />
- [x] add error message for unrecognized characters in a token (like '&' doesn't print an error message, it just returns a null/invalid token; not sure how that works) <br/>
- [ ] return errors (not error unions, but the specific problems) in a way that can be stored in a variable/struct and 'rendered' into a string
- [ ] special codes (new Expr type) stored in constants that can interact with certain parts of the application (such as the prompt)
- [ ] fix the error message in [tests/bug1.log](tests/bug1.log)
- [ ] add debug output to indicate when parsing and evaluation are complete and how long it took (with `--debug` flag)
- [ ] @undef(ident) builtin to undefine a user-defined identifier
- [x] somehow fix print{...} printed stuff showing up to the left of the output bars (maybe remove the bars?)
- [x] copy contents of strings need into the Expr.string field, instead of just saving their position

# todos from [maths](https://github.com/ilovapples/maths)
- [x] negation operator!! negative numbers are annoying without it <br />
- [x] insert multiplication operation between consecutive values between which there is no operation (so 3i would parse the same as 3*i) <br />
- [x] variable assignment (statements?) <br />
- [x] assigned variables in the prompt can't be accessed on a line past their definition as the right value, but they can as the left value (so `print{x}` would say `x` is undefined) <br />
- [x] fix memory leaks caused by adding variable assignment (memory leaks for literally everything?), then rebase dev back into main <br />
- [x] fix segfault when using `--set_var:` to insert a variable when the variable value string is empty (e.g. `--set_var:A=`) <br />
- [x] syntax guide and other documentation <br />
- [x] === operator for exact equality (do away with --no-estimate-equality) <br />
- [x] interactive prompt (like python's IDLE) (pretty much done) <br />
- [ ] add history to interactive prompt <br />
- [x] fix 'ans' returning the last value evaluated rather than the output of the last prompt <br />
- [x] change prompt to use MML_parse_stmts~~_to_ret~~ to maybe fix variables not working past their definition? <br />
- [x] fix random memory leaks (probably caused by evaluator but I can't figure out the root cause) <br />
- [x] fix the identifier 'a' having inexplicable bugs (--set_var doesn't work with it, it never flags an 'undefined variable' error even when it should, etc.) <br />
- [x] vector literals have regressed; each element is (null) or the first thing that was evaluated (no idea why) (forgot to add a memcpy when transitioning to arena but we're good now) <br />
- [x] 'Nothing' type to return from stuff like `println` (basically `void`) <br />
- [x] improve `MML_print_expr` to print the AST in a more similar format to the syntax used with `tests/ast_test.h` <br />
- [ ] add Type type so I can add a `cast{type, val}` function <br />
- [ ] fix prompt so it reads data in 1 byte minimum chunks (now it's 8 bytes for one character read,
      so stdin doesn't work unless you're currently the one using the prompt via shell input or something) <br />
- [x] add check for recursive variable definition (currently segfaults from stack overflow)
