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

## Errores de sistema

La familia `OSError` también está en `PyExc` (`.os_error`, `.file_not_found_error`,
`.permission_error`, `.timeout_error`, `.connection_refused_error`, ...). Tras una llamada
C fallida, `vcraft.raise_last_errno('contexto')` lanza la subclase que CPython elige para el
`errno` actual (ECONNREFUSED es `ConnectionRefusedError`), con `errno` y `strerror`
definidos; `vcraft.raise_errno(codigo, 'contexto')` recibe el número explícitamente.

## Logging

`vcraft.log_debug/info/warning/error(mensaje)` escribe en el `logging` de Python mediante el
logger con el nombre del módulo, desde cualquier hilo, tomando el GIL para la llamada.

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

El traceback nombra la función V donde ocurrió el pánico, con su fichero y su línea, y
muestra la línea de V cuando el fichero se puede leer desde el directorio de trabajo:

```text
Traceback (most recent call last):
  File "app.py", line 6, in <module>
    t.add_then_fail(3)
  File "src/hello_native.v", line 1030, in add_then_fail
    pub fn (mut t Tally) add_then_fail(by i64) {
RuntimeError: panic in V code: failed after writing
```

La línea es la de la declaración de la función: V da el mensaje del pánico pero no en qué
punto del cuerpo ocurrió. Un pánico cuesta unos 40 µs más por el frame; las llamadas
normales y los `error()` no cambian.

## Siguiente

- [La línea de comandos](cli.md)
- [Wheels](wheels.md)
