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

## Next

- [The command line](cli.md)
- [Wheels](wheels.md)
