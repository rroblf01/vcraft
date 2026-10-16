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

## Estado

1.4.0. El vocabulario de anotaciones, las claves de `vcraft.toml` y la CLI sólo cambian
con un periodo de deprecación. Mira el [roadmap](https://github.com/rroblf01/vcraft/blob/main/ROADMAP.md)
para lo que queda, y [`DECISIONS.md`](https://github.com/rroblf01/vcraft/blob/main/DECISIONS.md)
para lo que se aparcó y por qué.
