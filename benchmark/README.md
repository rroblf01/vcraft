# Benchmark: PyO3 vs vcraft vs zig-maturin

Tres proyectos independientes que implementan **las mismas siete funciones con la misma
semántica**, uno por herramienta, más una referencia en Python puro:

| carpeta | herramienta | lenguaje | módulo |
|---|---|---|---|
| [`pyo3/`](pyo3) | PyO3 0.29 + maturin 1.15 | Rust 1.98 | `bench_pyo3` |
| [`vcraft/`](vcraft) | vcraft (este repo) | V `0137eb5` | `bench_vcraft_native` |
| [`zig-maturin/`](zig-maturin) | [zig-maturin](https://github.com/rroblf01/zig-maturin) 1.0.1 | Zig 0.16 | `bench_zig` |
| [`pure_python.py`](pure_python.py) | — | Python | `pure_python` |

## Cómo se ejecuta

```console
$ ./run.sh            # build limpio de los tres, instalación en .venv y benchmark
$ ./run.sh --quick    # menos repeticiones, para comprobar el arnés
```

Necesita `uv`, `cargo`, `zig` 0.16 y un `v` compilado en el commit fijado en `docker/` en el
`PATH`. No instala nada fuera de `benchmark/.venv`. `BENCH_PYTHON` elige el intérprete
(3.13 por defecto, la versión más nueva que soportan los tres). El resultado completo se
escribe en [`results.md`](results.md) y [`results.json`](results.json).

## Qué se mide

| carga | qué mide |
|---|---|
| `add(1, 2)` | coste fijo de una llamada |
| `fib(25)` recursivo | cálculo puro: calidad del código generado |
| `count_primes(1_000_000)` | cálculo más una reserva nativa de 1 MB |
| `sum_floats(lista de 100k)` | conversión `list[float]` → nativo |
| `make_range(100_000)` | conversión nativo → `list[int]` |
| `greet('world')` | `str` de entrada, `str` nuevo de salida |
| `Counter()` / `c.increment()` | construcción de objeto y llamada a método |

- **Velocidad:** `timeit`, el mejor de 7 repeticiones, en un proceso dedicado.
- **Memoria:** cada escenario se ejecuta en un proceso nuevo y **dos veces seguidas**.
  *Peak* es el RSS máximo del proceso. *Kept* es lo que queda residente tras la primera
  tanda y `gc.collect()`. *Leak* es lo que añade la segunda tanda, idéntica a la primera:
  un heap que ya se ha estabilizado no añade nada, y una fuga sí.
- **Import:** 8 procesos. El primero se informa aparte, porque macOS verifica una vez cada
  binario recién instalado; la cifra "warm" es la mediana del resto.
- **Tamaño:** el wheel, la extensión tal como sale y la extensión tras `strip -x`.
- **Corrección:** valores esperados, incluido `2**40`, y que `2**63` lance `OverflowError`.

Cada herramienta compila con su modo release: `cargo --release` (opt-level 3),
`vcraft build --release` (`v -prod`) y `zig-maturin build --release` (`ReleaseSafe`). Los
tres mantienen las comprobaciones de límites.

## Resultados iniciales

macOS 27, Apple Silicon (arm64), CPython 3.13.15. Una sola máquina y una sola ejecución
completa; la ejecución rápida previa dio las mismas cifras con un margen del 5 %.

Esta es la foto de partida, antes de mejorar vcraft. La evolución de vcraft está en
[Progreso de vcraft](#progreso-de-vcraft), y la última ejecución completa, en
[`results.md`](results.md).

### Tamaño y build

| | PyO3 | vcraft | zig-maturin |
|---|---|---|---|
| wheel | 221 KiB | **189 KiB** | **186 KiB** |
| extensión (`strip -x`) | 414 KiB | **351 KiB** | 400 KiB |
| build release limpio¹ | 5,7 s | **2,1 s** | 8,4 s |

¹ Proyecto limpio, con las cachés de cargo y zig ya calientes (sin descargas).

### Velocidad (tiempo por llamada; menos es mejor)

| carga | PyO3 | vcraft | zig-maturin | Python |
|---|---|---|---|---|
| `add` | **29 ns** | 41 ns | 206 ns | 16 ns |
| `fib(25)` | 121 µs | **118 µs** | 164 µs | 5,20 ms |
| `count_primes(1e6)` | 2,00 ms | 3,76 ms | **1,43 ms** | 42,2 ms |
| `sum_floats(100k)` | **451 µs** | 968 µs | 496 µs | 775 µs |
| `make_range(100k)` | **833 µs** | 1,10 ms | 841 µs | 775 µs |
| `greet` | 60 ns | **39 ns** | 275 ns | 33 ns |
| `Counter()` | 36 ns | **35 ns** | 200 ns | 39 ns |
| `c.increment()` | **19 ns** | 29 ns | 194 ns | 27 ns |

### Memoria

| | PyO3 | vcraft | zig-maturin | Python |
|---|---|---|---|---|
| RSS que añade el `import` | 304 KiB | 1.088 KiB | **144 KiB** | — |
| `import` (warm) | **0,51 ms** | 3,50 ms | 0,57 ms | — |
| `greet` ×2M: kept / leak | 0 / 0 | 13,8 MiB / 0 | 0 / 0 | 0 / 0 |
| `make_range` ×200: kept / leak | 0 / 0 | **790 MiB / 772 MiB** | 0 / 0 | 0 / 0 |
| `count_primes(10M)` ×5: kept / leak | 0 / 0 | 14,7 MiB / 0 | 0 / 0 | 0 / 0 |
| `Counter()` ×1M: kept / leak | 0 / 0 | 12,9 MiB / 0,9 MiB | 0 / 0 | 0 / 0 |

### Corrección

Todo correcto salvo un caso: con `add(2**63, 0)`, zig-maturin lanza
`TypeError: expected int, got int` en lugar de `OverflowError`.

## Conclusiones

**Velocidad: los tres generan código nativo comparable.** En `fib`, la diferencia entre
PyO3 y vcraft es ruido, y Zig va algo por detrás, seguramente por `ReleaseSafe`. Las
diferencias reales están en la frontera con Python: el coste de cada llamada y el de las
conversiones. Ahí PyO3 es el más regular. vcraft queda a 1,4–1,5× en llamadas simples y es
el mejor en `greet` y en construir objetos. zig-maturin paga hoy entre 5 y 10× por llamada,
por una causa concreta que se corrige con una línea (ver abajo).

**Tamaño: empate práctico.** Entre 186 y 221 KiB por wheel. No es un criterio para elegir.

**RAM: PyO3 y zig-maturin no se distinguen de Python puro. vcraft sí.**
- El GC de Boehm añade unos 1 MiB al importar y deja un heap de 13–15 MiB que no devuelve
  al sistema. Se estabiliza; no es una fuga.
- Hay una fuga real: **vcraft no tiene hoy ninguna forma de devolver una lista sin perder
  memoria** (ver abajo). En `make_range`, cada llamada pierde la lista entera.

**¿Merece la pena vcraft?** El código que genera V es tan rápido como el de Rust. Con la
reserva fuera del GC, `count_primes` baja a 1,34 ms, mejor que los otros dos. Además el
build es el más rápido y el binario el más pequeño. Pero hoy **no está a la par de PyO3**:
le faltan piezas básicas, como devolver listas, y el GC cuesta RAM y velocidad en las
reservas grandes. La base merece la pena; los puntos de abajo son los que lo separan de
PyO3, y casi todos son acotados.

**zig-maturin** queda muy cerca de PyO3 en todo menos en el coste por llamada, y eso tiene
una corrección verificada.

**PyO3** es la referencia: el más regular y sin ningún fallo en este benchmark. A cambio,
tiene el build más pesado de los dos con toolchain propio y el wheel algo mayor.

## Qué mejorar

### vcraft

Por prioridad. Cada punto está reproducido en este benchmark.

1. ✅ *Corregido en el paso 1.* **Devolver `[]T` no compila.** El emisor genera `vcraft.to_py_list(result)` con un
   argumento, y el runtime declara `to_py_list[T](items, box)` con dos
   (`vlib/vcraft_codegen/emit.v`, `boxed_expr`).
2. ✅ *Corregido en el paso 1.* **Las alternativas para devolver una lista también fallan.** Devolver `vcraft.PyObj` o
   `PyObj` hace que el generador muera con SIGBUS (exit 138), sin ningún diagnóstico. Un
   `voidptr` bajo `@[vc_fn]` genera `result.ptr` sobre un puntero y no compila.
3. ✅ *Resuelto en el paso 1: un resultado `vcraft.PyObj` entrega su referencia.*
   **`@[vc_raw]` no puede devolver un objeto nuevo sin fugarlo.** El glue trata el
   resultado como prestado y hace `borrow(result).new_ref()`. Junto con los puntos 1 y 2,
   devolver una lista implica perder memoria; es lo que mide `make_range`.
4. ✅ *Corregido en el paso 1.* **Un campo `i64` en una clase no compila.** El getter y el `__repr__` generados llaman a
   `to_py_int` y `repr_int`, que solo aceptan `int`. Con este V, `int` ya es de 64 bits, así
   que basta con aceptar ambos tipos.
5. ✅ *Corregido en el paso 4.* **`sum_floats` es más lento que Python puro**, 2,1× por detrás de PyO3:
   `from_py_f64_seq_arg` hace `obj.item(k)` y comprobaciones por elemento, y añade al
   resultado con `<<` sobre un array del GC. Leer la lista con `PySequence_Fast` y
   `PyFloat_AsDouble` sobre los ítems directamente es lo habitual.
6. ✅ *Hecho en el paso 1, sin efecto medible.* **`to_py_list` crea la lista con
   `PyList_New(0)` y `PyList_Append`.** Reservarla con su tamaño es lo que hacen PyO3 y
   pyo3zig, pero la diferencia en `make_range` está en el punto 7.
7. ✅ *Corregido en el paso 6 (import y memoria); el diagnóstico estaba mal.* **Coste del
   GC.** Había 3,5 ms de import, frente a 0,5 ms, y un heap mínimo de 13–15 MiB. Además,
   las reservas grandes iban 2,8× más lentas que con `calloc` (3,76 frente a 1,34 ms en
   `count_primes`). Los 3 ms y los 13 MiB venían de que Boehm escaneaba todas las imágenes
   del proceso (paso 6). Lo de `calloc` no era el GC: el experimento usaba un puntero
   crudo, que se salta las llamadas por elemento con las que V compila `a[i] = x` (paso 5).
8. **Pendiente, en V:** el compilador nuevo de V convierte cada `<<` y cada `a[i] = x` en
   una llamada con `memcpy` de un elemento, y `@[direct_array_access]` no lo evita en las
   escrituras. Es lo que queda entre vcraft y PyO3 en `count_primes` y `make_range`.
9. **Pendiente:** `GC_set_free_space_divisor(1)`, el valor que fija V, hace crecer el heap
   antes que recolectar. Con 2 se retienen algo menos de memoria a cambio de un 0–3 % de
   velocidad; no lo he cambiado, pero vcraft podría ofrecerlo como opción.

### zig-maturin

1. **`setjmp` por llamada** (`pyo3zig_capi.c`). En macOS, `setjmp` guarda la máscara de
   señales con una llamada al sistema en cada entrada. Cambiarlo por `_setjmp`/`_longjmp`
   (o `sigsetjmp(env, 0)`) lo he verificado en una copia: `add` pasa de 206 a **31 ns**,
   `increment` de 194 a **22 ns** y `greet` de 275 a 98 ns.
2. **`METH_VARARGS` en lugar de `METH_FASTCALL`.** Crea una tupla por llamada; PyO3 y vcraft
   usan `FASTCALL`. No lo he medido por separado.
3. **El `build.zig` que genera `scaffold` no reenvía `-Dpython-include` a la dependencia.**
   La dependencia recurre entonces a `python3-config`, que no existe en un venv de uv, y el
   build aborta. Está corregido en [`zig-maturin/build.zig`](zig-maturin/build.zig).
4. **Desbordamiento de entero:** debería lanzar `OverflowError`, no
   `TypeError: expected int, got int`.
5. **`pz` no reexporta `PyList_SetItem`**: hay que importar el módulo de bajo nivel
   `zig-maturin` para construir una lista sin copias.
6. Sin `--release`, `zig-maturin build` compila en `Debug`. Conviene tenerlo presente al
   comparar.

### PyO3

Nada que señalar en este benchmark.

## Rodeos en el código del benchmark

Para que los tres proyectos compilen con la misma semántica:
- **zig-maturin:** `build.zig` reenvía el include de Python (punto 3) y `make_range` usa
  `zm.PyList_SetItem` (punto 5). Están comentados en el código fuente.
- **vcraft:** ninguno desde el paso 1. Antes, `make_range` usaba `@[vc_raw]` (puntos 1–3,
  y por eso fugaba) y `Counter.value` era `int` (punto 4).

## Progreso de vcraft

Las cifras de vcraft tras cada paso, con el benchmark completo. PyO3 se mantiene estable
entre ejecuciones (±2 %), así que la columna de referencia es la de la tabla inicial.

| paso | `add` | `increment` | `sum_floats` | `make_range` | `count_primes` | fuga `make_range` |
|---|---|---|---|---|---|---|
| PyO3 (referencia) | 29 ns | 19 ns | 451 µs | 833 µs | 2,00 ms | 0 |
| inicial | 41 ns | 29 ns | 968 µs | 1,10 ms | 3,76 ms | 772 MiB |
| 1. devolver listas y objetos | 40 ns | 29 ns | 970 µs | 1,09 ms | 3,76 ms | **0** |
| 2. coste fijo por llamada | **22 ns** | 29 ns | 942 µs | 1,10 ms | 3,77 ms | 0 |
| 3. métodos sobre el puntero | 23 ns | **16 ns** | 961 µs | 1,10 ms | 3,78 ms | 0 |
| 4. leer secuencias | 22 ns | 16 ns | **153 µs** | 1,10 ms | 3,78 ms | 0 |
| 5. listas numéricas en C | 22 ns | 16 ns | 152 µs | 1,03 ms | 3,77 ms | 0 |
| 6. raíces del GC (macOS) | 22 ns | 16 ns | **133 µs** | **988 µs** | 3,70 ms | 0 |

Memoria e import de vcraft en cada paso (PyO3: 0,50 ms de import, 304 KiB, 0 retenido):

| paso | `import` | RSS del `import` | retenido tras `greet` ×2M | pico `greet` ×2M |
|---|---|---|---|---|
| inicial | 3,50 ms | 1.088 KiB | 13,8 MiB | 41,8 MiB |
| 6. raíces del GC (macOS) | **0,61 ms** | 1.120 KiB | **1,0 MiB** | **29,0 MiB** |

**Paso 1** (puntos 1–4 y 6). Ya se puede devolver `[]T`, `vcraft.PyObj` y `voidptr`, y los
campos `i64` compilan. La fuga desaparece: lo que queda tras `make_range` son 18,5 MiB del
heap del GC, que se estabilizan. Reservar la lista con su tamaño no cambia el tiempo: lo
caro de `make_range` es construir antes el `[]i64` de 800 KB en el GC, el mismo coste que
en `count_primes` (punto 7).

**Paso 2.** El glue de cada función comprobaba la aridad con dos llamadas, y después de
cada una consultaba `PyErr_Occurred`. Ahora es una sola comparación de `nargs`, y el
mensaje de error solo se construye cuando falla. Además, un `int` exacto que cabe en
64 bits se lee con una sola comparación de tipo en C; antes eran dos `PyType_IsSubtype`
(uno para rechazar `bool` y otro para aceptar `int`) y otra consulta del error. `add` pasa
de 40 a **22 ns**, por delante de PyO3 (29 ns). Medido por partes en una copia del glue: la
aridad aportaba unos 6 ns, la lectura de enteros unos 10 y el guardián de pánicos
(`recover()`, un `_setjmp` por llamada) unos 5. El guardián se mantiene: sin él, un
`panic` de V termina el intérprete. `increment` no cambia porque un método copia el estado
de la instancia dentro y fuera en cada llamada; es el siguiente paso.

**Paso 3.** Los métodos, accesores y slots trabajan sobre el bloque de estado de la
instancia a través de un puntero, como PyO3 con su celda, en vez de copiar el struct entero
antes y después de cada llamada. Además, la cadena de estados que publica cada trampolín
para `vcraft.state_at` (una reserva con `PyMem_Malloc` y dos copias por llamada) solo se
emite si algún fichero del módulo llama a `state_at`. `increment` pasa de 29 a **16 ns**,
por delante de PyO3 (19 ns). Contrapartida, la misma que en PyO3: un método que hace
`panic` a medias conserva lo que ya había escrito.

**Paso 4.** Al medir apareció una fuga que el benchmark no veía: `PyObj.item` usaba
`PySequence_GetItem`, que devuelve una referencia nueva, y quien lo llamaba la trataba
como prestada. Cada elemento leído de una lista pasada como `[]T` quedaba con una
referencia de más, así que los elementos de una lista temporal nunca se liberaban. Ahora
`item` usa `PyList_GetItem`/`PyTuple_GetItem`, y el benchmark tiene un escenario que pasa
una lista nueva en cada llamada para detectarlo. Además, `[]int`, `[]i64` y `[]f64`
convierten en C, en una sola pasada, los elementos que son `int` o `float` exactos;
el resto sigue por el camino general. `sum_floats` pasa de 961 a **153 µs**, tres veces
más rápido que PyO3 (451 µs).

**Paso 5.** Una lista devuelta de `[]i64`, `[]int` o `[]f64` se construye en C en una
sola pasada, con `PyList_SET_ITEM`, en vez de llamar a una función por elemento.
`make_range` baja de 1,10 a 1,03 ms; la conversión ya cuesta lo mismo que
`list(range(n))`. Al perfilar apareció la causa real de lo que queda, y **corrige lo que
decía el punto 7**: no es el GC. El compilador nuevo de V convierte cada `<<` y cada
asignación `a[i] = x` en una llamada a función que copia un elemento con `memcpy`, y
`@[direct_array_access]` solo quita la comprobación en las lecturas. Eso es lo que separa
`count_primes` y `make_range` de PyO3, y está en V, no en vcraft.

**Paso 6.** En macOS, el GC de Boehm registraba como raíces los datos escribibles de
**todas** las imágenes del proceso (unas 400 en un Python normal), con un callback por
imagen. Eso costaba unos 3 ms de cada import y hacía que cada recolección recorriera los
datos de todas esas bibliotecas, de modo que sus páginas pasaban a contar en el RSS. Ahora
vcraft arranca el GC antes que V, sin ese registro, y registra a mano solo el segmento
`__DATA` del módulo, que es donde V guarda sus globales. El import pasa de 3,5 a
**0,61 ms**, y la memoria retenida tras 2 millones de llamadas, de 13,8 a **1,0 MiB**: lo
que parecía heap del GC eran páginas de bibliotecas del sistema. El código que reserva
mucho también va más rápido (`sum_floats` 153 → 133 µs; un bucle que solo concatena
strings, 1,8×). Linux no cambia: allí Boehm registra las bibliotecas de otra forma y no lo
he medido.

### Estado tras el paso 6

vcraft gana a PyO3 en `add` (22 frente a 29 ns), `fib`, `sum_floats` (133 frente a
451 µs), `greet` (34 frente a 60 ns), `Counter()` e `increment` (16 frente a 19 ns), y en
tamaño de wheel y tiempo de build. Pierde en `count_primes` (3,70 frente a 2,02 ms) y en
`make_range` (988 frente a 829 µs), por la forma en que V compila la escritura en arrays.
En memoria queda por encima: unos 800 KiB más al importar (el heap inicial y las
estructuras del GC) y alrededor de 1–2 MiB retenidos tras cargas grandes.
