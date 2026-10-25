# vcraft

**Bindings de CPython escritos en V.** vcraft es para el lenguaje V lo que PyO3 + maturin
es para Rust: un generador de código que convierte anotaciones `@[vc_*]` en el pegamento
de una extensión, y un escritor de wheels que empaqueta el resultado. Sin Rust, C++ ni
zlib en la cadena.

```v
module hello_native

import vcraft

@[vc_fn]
pub fn greet(name string) string {
	return 'Hello, ${name}!'
}
```

```python
import hello_native
print(hello_native.greet("world"))  # Hello, world!
```

## Lo destacado

- **Un fichero V es la API.** Anotas una función, una clase o un campo y el generador
  escribe el pegamento, los stubs de tipos y el wheel.
- **Toda la cadena es V y Python.** El compilador es V; el escritor de wheels construye
  DEFLATE, ZIP, tar, SHA-256 y METADATA desde cero, sin `zlib`.
- **Rendimiento cercano a PyO3**, con el estado de la instancia dentro del propio objeto.
- **Todos los CPython soportados**, de 3.11 a 3.15 más los builds free-threaded, en Linux
  (glibc y musl), macOS y Windows.

## Por dónde seguir

- [Primeros pasos](getting-started.md) — instalar la CLI y construir tu primera extensión.
- [El vocabulario de anotaciones](guide/annotations.md) — qué hace cada `@[vc_*]`.
- [Tipos](guide/types.md) — cómo se mapean los tipos de V y Python.
- [Clases y propiedades](guide/classes.md) — `@[vc_class]`, campos, constructores.
- [La línea de comandos](guide/cli.md) y [Wheels](guide/wheels.md) — build, develop,
  publish, abi3 y free-threading.

## Hecho con vcraft

[vqubit](https://pypi.org/project/vqubit/) es un framework de computación cuántica para
Python, sin dependencias y al estilo de [Cirq](https://quantumai.google/cirq): su álgebra
lineal, las matrices de las puertas y los simuladores están escritos en V. Se publica como
un único wheel abi3 por plataforma, para CPython 3.11 y posteriores, y no arrastra nada más
— un buen ejemplo completo de un proyecto hecho con vcraft
([fuente](https://github.com/rroblf01/vqubit), [docs](https://rroblf01.github.io/vqubit/)).

## Estado

1.5.0. Novedades: `@[vc_handle]` para estado nativo del que una clase es dueña, `@[vc_opaque]`
para punteros que viajan en cápsulas (resultado y parámetro), `vcraft.with_gil` / `released` /
`gil_ensure` / `gil_release` para control del GIL desde hilos V, `bytes_view` para lecturas sin
copia de resultados bytes-like, `to_py_str_list` / `to_py_bytes_list`, y `run_coroutine` /
`call_async` para conducir una corrutina de Python desde V. Ver el
[changelog](https://github.com/rroblf01/vcraft/blob/main/CHANGELOG.md) para la lista completa.

El vocabulario de anotaciones, las claves de `vcraft.toml` y la CLI sólo cambian
con un periodo de deprecación. Mira el [roadmap](https://github.com/rroblf01/vcraft/blob/main/ROADMAP.md)
para lo que queda, y [`DECISIONS.md`](https://github.com/rroblf01/vcraft/blob/main/DECISIONS.md)
para lo que se aparcó y por qué.
