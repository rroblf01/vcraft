# La línea de comandos

```console
$ vcraft --help
```

| Comando | Qué hace |
| --- | --- |
| `vcraft new <nombre>` | Crea un proyecto: manifiesto, fuente V, demo, test, README |
| `vcraft build` | Ejecuta el generador, compila la extensión y escribe un wheel |
| `vcraft develop` | Construye e instala en el virtualenv activo, editable por defecto |
| `vcraft info` | Muestra lo que resolvería un build: módulo, sufijo, tag, toolchain |
| `vcraft clean` | Borra `dist/` y la salida del build editable |
| `vcraft generate-ci` | Escribe un workflow de GitHub Actions que construye y comprueba los wheels |
| `vcraft publish` | Sube los wheels construidos (rechaza un build editable) |
| `vcraft toolchain` | Informa del compilador V que usa vcraft y si es el pin |
| `vcraft toolchain install` | Instala el V pin en la caché propia de vcraft: el archivo precompilado donde se publica, compilado desde el código fuente si no (`--from-source` lo fuerza) |
| `vcraft version` / `--version` | Imprime la versión |

## Flags habituales

| Flag | Aplica a | Efecto |
| --- | --- | --- |
| `--release` | `build` | Build optimizado (`-prod`) |
| `--target <nombre>` | `build`, `info` | Cross target: `linux-x86_64-gnu`, `windows-amd64`, … |
| `--platform <tag>` | `build` | Fuerza el tag de plataforma; debe concordar con `--target` |
| `--manylinux <ver>` / `--musllinux <ver>` | `build` | Declara una política de distribución Linux |
| `--abi3 <versión>` | `build` | Un wheel de ABI estable para `versión` y posteriores |
| `--free-threading` | `build` | Construye contra la ABI free-threaded |
| `--interpreter <ruta>` | `build`, `info` | El intérprete contra el que construir; `a,b,c` construye un wheel por cada uno |
| `--find-interpreter` | `build` | Un wheel por cada CPython soportado en el `PATH` |
| `--debug` | `build`, `develop` | `-g`: números de línea de V en gdb y en los informes de fallo |
| `--sanitize` | `build`, `develop` | ASan y UBSan; indica cómo ejecutar Python con el runtime precargado |
| `--out-dir <dir>` | `build` | Dónde se escribe el wheel |
| `--dry-run` | `build`, `develop` | Imprime el plan sin ejecutarlo |

`vcraft info` es planificación pura: nombra el SO, la arquitectura, el tag y el compilador
sin tocar ningún toolchain, así que funciona en todas partes, incluso para un target cuyo
compilador no está instalado.

## Ejemplos

```console
$ vcraft build --release
$ vcraft build --target linux-aarch64-gnu --manylinux 2_17
$ vcraft build --abi3 3.11
$ vcraft build --interpreter /opt/python/cp312-cp312/bin/python
$ vcraft info --target windows-amd64
```

Ver [Wheels](wheels.md) para tags y políticas, e [Integración continua](ci.md) para
`generate-ci`.
