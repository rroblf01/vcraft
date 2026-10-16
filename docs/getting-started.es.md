# Primeros pasos

## Requisitos

- **Un CPython soportado**: de 3.11 a 3.15, o un free-threaded 3.13t/3.14t/3.15t.
- **Un compilador de C** (gcc o clang) y las cabeceras de CPython, que la mayoría de las
  instalaciones de Python ya incluyen.
- **git y make**, una vez, para construir el compilador de V con el que vcraft se prueba.

## 1. Instalar vcraft

```console
$ pip install vcraft
$ vcraft --version
```

## 2. Instalar el compilador de V

`pip` trae la herramienta, no el toolchain, igual que maturin necesita Rust. vcraft
necesita un V más nuevo que la release 0.5.2, así que construye en su propia caché el
commit con el que se prueba (unos cinco minutos, una sola vez):

```console
$ vcraft toolchain install
$ vcraft toolchain          # qué compilador usa vcraft y si es el pin
```

vcraft lo encuentra ahí solo. `VCRAFT_V=/path/to/v` usa otro V.

## 3. Crear, desarrollar y construir un proyecto

```console
$ vcraft new my_extension
$ cd my_extension
$ python -m venv .venv && source .venv/bin/activate
$ vcraft develop                      # construye e instala en el venv activo
$ python main.py                      # el ejemplo que escribió `vcraft new`
$ python -m unittest                  # el test de tests/
$ vcraft build --release              # dist/my_extension-0.1.0-cp314-cp314-<platform>.whl
```

`vcraft new` escribe un paquete Python `my_extension` que reexporta el módulo nativo
`my_extension_native`, de modo que `import my_extension` es el nombre público. Pasa
`--module my_extension` si prefieres no tener un módulo nativo aparte.

## 4. Publicarlo

`vcraft generate-ci` escribe un workflow de GitHub Actions que construye un wheel por cada
Python y plataforma soportados, instala e importa cada uno, y queda listo para publicar en
PyPI.

```console
$ vcraft generate-ci
```

## La forma de un proyecto

```text
my_extension/
├── vcraft.toml          # el manifiesto: package, build, wheel, ci
├── v.mod                # el módulo V
├── src/
│   └── my_extension_native.v   # tu fuente V, y la API
├── python/
│   ├── my_extension/__init__.py
│   ├── my_extension/py.typed
│   └── my_extension_native.pyi # escrito por el generador
├── tests/test_my_extension.py
└── main.py
```

Los ficheros generados (`src/_vcraft_generated.v`, `python/*.pyi`) se escriben en cada
build; no los edites a mano.

## Siguiente

- [El vocabulario de anotaciones](guide/annotations.md)
- [Tipos](guide/types.md)
- [La línea de comandos](guide/cli.md)
