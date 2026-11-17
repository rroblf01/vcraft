# La línea de comandos

```console
$ vcraft --help
```

| Comando | Qué hace |
| --- | --- |
| `vcraft new <nombre>` | Crea un proyecto: manifiesto, fuente V, demo, test, README |
| `vcraft init [dir]` | Añade vcraft a un proyecto Python existente (ver abajo) |
| `vcraft build` | Ejecuta el generador, compila la extensión y escribe un wheel |
| `vcraft develop` | Construye e instala en el virtualenv activo, editable por defecto |
| `vcraft develop --watch` | Lo mismo, y otra vez con cada cambio en un fichero V, C o de manifiesto (`--interval <ms>`, 500 por defecto) |
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
| `--pgo <script.py>` | `build`, `develop` | Build guiado por perfil con gcc (ver abajo) |

`vcraft info` es planificación pura: nombra el SO, la arquitectura, el tag y el compilador
sin tocar ningún toolchain, así que funciona en todas partes, incluso para un target cuyo
compilador no está instalado.

## Builds guiados por perfil: `--pgo`

```console
$ vcraft build --pgo bench_my_ext.py
pgo 1/3: instrumented build
pgo 2/3: training with bench_my_ext.py
pgo 3/3: optimized build
```

La extensión se compila una vez instrumentada, el script se ejecuta contra ella (con el
árbol Python del proyecto importable) y registra qué ramas y llamadas son calientes, y
después el build real se optimiza para ese perfil. El código que el script no ejecutó se
sigue optimizando para velocidad (`-fprofile-partial-training`). Necesita gcc como
compilador C y entrena en esta máquina con un intérprete, así que no se combina con
`--target` ni con varios intérpretes.

Es un compromiso, así que mide con tu propia carga. En el benchmark hizo 22 de 26 cargas
entre un 4 y un 31 % más rápidas (`join_strings` 0,69×, `describe(3)` 0,74×, `add`
0,88×), pero un bucle ajustado que escribe un array elemento a elemento puede perder: la
criba de primos fue 1,64× más lenta y el `fib` recursivo 1,17×. Entrena con llamadas
parecidas a las de producción, con tamaños de producción.

## Un proyecto Python existente: `vcraft init`

```console
$ cd mylib            # pyproject.toml, src/mylib/__init__.py, tests/...
$ vcraft init
$ vcraft develop --watch
```

`init` escribe `vcraft.toml`, `v.mod`, `src/<nombre>_native.v` y `vcraft_build.py`, y
nunca sobrescribe uno que ya exista. En `pyproject.toml` solo sustituye `[build-system]`,
nombrando el backend que reemplaza; `[project]` sigue siendo la fuente de los metadatos.
Encuentra el paquete Python en `python/`, `src/<pkg>` o un `<pkg>/` plano y registra los
dos últimos como `python-source` y `python-packages`, así que el wheel lleva ese paquete,
la extensión y su stub, y no los tests ni los scripts de al lado. `--name` y `--module`
cambian los nombres derivados.

`develop --watch` sigue en marcha: cada cambio recompila y reinstala, de modo que el
siguiente `import` en un proceso nuevo lo ve. Un build fallido se muestra y la vigilancia
continúa. Los ficheros Python de una instalación editable no necesitan recompilar.

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
