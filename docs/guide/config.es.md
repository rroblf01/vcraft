# Configuración

La configuración de empaquetado vive en `vcraft.toml` en la raíz del proyecto. `vcraft new`
escribe uno. `pyproject.toml` es el único otro fichero que vcraft toca, y lo **fusiona, no
lo reemplaza**: un build reescribe sólo la tabla `[build-system]` y deja el resto intacto,
así que las tablas propias de un proyecto (`[project]`, `[dependency-groups]` de PEP 735 —
de modo que `uv sync --group dev` funciona — y `[tool.*]`) sobreviven a `vcraft build` y
`vcraft develop`.

```toml
[package]
name = "my-extension"
version = "0.1.0"
module = "my_extension"
description = "A Python extension written in V."
license = "MIT"
requires-python = ">=3.11"
readme = "README.md"         # la página del proyecto en PyPI, en Markdown
keywords = ["fast", "parsing"]
classifiers = ["Programming Language :: Other", "Programming Language :: Python :: 3"]
dependencies = []

[build]
minimum-version = "3.11"     # CPython más antiguo para el que la matriz de CI construye
abi3 = "3.11"                # opcional: un wheel de ABI estable para 3.11 y posteriores
free-threading = false       # true: construye para un CPython free-threaded (3.13t+)
strip = false
embed-pyc = false
gc-free-space-divisor = 2    # crecimiento del heap de Boehm: 1 prima la velocidad, 2 la memoria

[urls]
Source = "https://github.com/me/my-extension"
Issues = "https://github.com/me/my-extension/issues"
```

## `[build]`

| Clave | Por defecto | Significado |
| --- | --- | --- |
| `minimum-version` | `"3.11"` | CPython más antiguo para el que `vcraft generate-ci` construye |
| `abi3` | sin definir | Suelo de ABI estable para un wheel portable, `3.11` o posterior |
| `free-threading` | `false` | Construye para un intérprete free-threaded y lo declara sin GIL |
| `strip` | `false` | Elimina símbolos de la extensión |
| `embed-pyc` | `false` | Envía `.pyc` sin fuente en vez de los `.py` del proyecto |
| `gc-free-space-divisor` | `2` | Divisor de crecimiento del heap de Boehm; `1` cambia memoria por velocidad |

## `[package]` y `[urls]`

`readme` nombra el fichero que PyPI muestra como página del proyecto (`.md` se renderiza
como Markdown, `.rst` como reStructuredText); `vcraft new` escribe un `README.md` y apunta a
él. Los classifiers deben ser de los que PyPI conoce: V no tiene ninguno propio, así que usa
`Programming Language :: Other`. Cada entrada de `[urls]` pasa a ser un enlace en la barra
lateral de PyPI.

## Combinaciones rechazadas

`vcraft build` rechaza las combinaciones que compilarían y fallarían después: un intérprete
anterior a 3.11, un suelo `abi3` por debajo de 3.11 o por encima del intérprete que
construye, `abi3` junto con `free-threading` (CPython free-threaded no tiene ABI estable), y
`free-threading` sobre cualquier cosa anterior a 3.13.

## Grafías antiguas

Antes de 1.0 las claves de build eran claves de primer nivel y los classifiers eran tablas
`[[classifier]]`; ambas se siguen leyendo en toda la serie 1.x, con un aviso que dice qué
cambiar.
