# Errors and panics

A V function returning `!T` becomes a Python call that either returns the value or raises.
How the failure is reported is up to the V code.

## Built-in exceptions

`vcraft.raise_domain(.value_error, 'message')` raises a specific built-in. This is what
lets `except ValueError` keep matching when the marshalling code would otherwise make
every failure a `RuntimeError`.

```v
@[vc_fn]
pub fn parse_int(text string) !int {
	mut value := 0
	mut seen := false
	for ch in text {
		if ch < `0` || ch > `9` {
			return vcraft.raise_domain(.value_error, 'invalid literal for int()')
		}
		seen = true
		value = value * 10 + int(ch - `0`)
	}
	if !seen {
		return vcraft.raise_domain(.value_error, 'invalid literal for int()')
	}
	return value
}
```

## System errors

The `OSError` family is in `PyExc` too (`.os_error`, `.file_not_found_error`,
`.permission_error`, `.timeout_error`, `.connection_refused_error`, ...). After a failed
C call, `vcraft.raise_last_errno('context')` raises the subclass CPython picks for the
current `errno` (ECONNREFUSED is `ConnectionRefusedError`), with `errno` and `strerror`
set; `vcraft.raise_errno(code, 'context')` takes the number explicitly.

## Logging

`vcraft.log_debug/info/warning/error(message)` writes to Python's `logging` through the
logger named after the module, from any thread, taking the GIL for the call.

## Custom exception types

`@[vc_error]` on a struct makes it usable as the error of a `!T` function. It needs a
`msg()` method that returns the message shown to Python, and may define `code()` to name
the exception class Python sees.

```v
@[vc_error]
pub struct ParseError {
pub:
	text string
}

@[vc_method]
pub fn (e &ParseError) msg() string {
	return 'cannot parse `${e.text}`'
}
```

## Panics

A V panic calls `exit(1)` by default; a trampoline wraps the call so a panic becomes a
Python exception instead of taking the interpreter down. The object a half-built
constructor allocated is released on the way out, so a failed construction does not leak.

The traceback names the V function where the panic happened, with its file and line, and
shows the V line when the file is readable from the working directory:

```text
Traceback (most recent call last):
  File "app.py", line 6, in <module>
    t.add_then_fail(3)
  File "src/hello_native.v", line 1030, in add_then_fail
    pub fn (mut t Tally) add_then_fail(by i64) {
RuntimeError: panic in V code: failed after writing
```

The line is the function's declaration: V reports a panic's message but not where in
the body it happened. A panic costs about 40 µs more for the frame; ordinary calls and
`error()` returns are unchanged.

## Next

- [The command line](cli.md)
- [Wheels](wheels.md)
