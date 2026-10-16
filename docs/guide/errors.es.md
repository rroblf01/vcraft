# Errores y pánicos

Una función V que devuelve `!T` pasa a ser una llamada Python que o devuelve el valor o
lanza. Cómo se reporta el fallo lo decide el código V.

## Excepciones incorporadas

`vcraft.raise_domain(.value_error, 'mensaje')` lanza una excepción incorporada concreta.
Esto es lo que permite que `except ValueError` siga coincidiendo cuando, si no, el código de
marshalling convertiría todo fallo en `RuntimeError`.

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

## Tipos de excepción propios

`@[vc_error]` sobre un struct lo hace utilizable como el error de una función `!T`.
Necesita un método `msg()` que devuelva el mensaje que ve Python, y puede definir `code()`
para nombrar la clase de excepción que ve Python.

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

## Pánicos

Un pánico de V llama a `exit(1)` por defecto; el trampolín envuelve la llamada para que un
pánico se convierta en una excepción Python en vez de tumbar el intérprete. El objeto que
un constructor a medio construir reservó se libera al salir, así que una construcción
fallida no filtra.

## Siguiente

- [La línea de comandos](cli.md)
- [Wheels](wheels.md)
