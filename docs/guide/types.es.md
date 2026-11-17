# Tipos

Cada tipo que cruza la frontera tiene una regla, en ambos sentidos. Un tipo sin regla es un
diagnóstico en tiempo de generación que señala el fichero, línea y columna exactos, nunca
una sorpresa en ejecución.

| Tipo V | Tipo Python | Notas |
| --- | --- | --- |
| `bool` | `bool` | Cualquier objeto al entrar; `True`/`False` al salir |
| `i8`, `i16`, `i32`, `int`, `i64`, `isize` | `int` | Con comprobación de rango: fuera de rango lanza `OverflowError` |
| `u8`, `u16`, `u32`, `u64`, `usize` | `int` | Negativo o fuera de rango lanza `OverflowError` |
| `f32`, `f64` | `float` | También acepta un `int` |
| `rune` | `int` | El punto de código |
| `string` | `str` | UTF-8; prestado al entrar, válido durante la llamada |
| `[]u8` | `bytes` | Cualquier objeto bytes-like al entrar, sin copiarlo |
| `[]T` | `list` | Cualquier secuencia al entrar (lista, tupla); una `list` al salir |
| `[N]T` | `list` | Exactamente N ítems al entrar; una `list` al salir |
| `?T` | `T` o `None` | `none` es `None`, en ambos sentidos |
| `map[K]T`, `K` escalar o `string` | `dict` | Claves escalares o `str`; un dict nuevo al salir |
| `(A, B, …)`, como resultado | `tuple` | Un retorno multivalor |
| `voidptr` | cualquier objeto | Prestado; la referencia es tuya |
| `vcraft.PyObj` (resultado) | cualquier objeto | Propia; la referencia va al llamador |
| `&T`, con `T` un `@[vc_class]` | `T` | Referencia a instancia; acepta una subclase |
| un `enum` del proyecto | ese `enum.IntEnum` | Los miembros conservan nombre y valor |
| un `struct` plano del proyecto | `dict` | Los nombres de campo como claves |
| `void`, `!void` | `None` | |
| `!T` | `T`, o lanza | Ver [Errores y pánicos](errors.md) |

## Anchura de los escalares

Un entero estrecho se comprueba al entrar: `t_i8(128)` lanza `OverflowError`, y también un
campo asignado fuera de rango. Esa es la diferencia entre una regla de marshalling y un
cast.

## Los composites anidan

Un contenedor anida, en ambos sentidos, así que `?[]int`, `[][]int`, `map[string][]int` y un
campo de struct de cualquiera de ellos cruzan como `list`/`dict`/`None` anidados. Un
contenedor devuelto se boxea elemento a elemento; un parámetro se lee con las mismas reglas.

## Enums

Un `enum` de V que declara el proyecto pasa a ser un `enum.IntEnum` del mismo nombre, unido
al módulo. Un valor vuelve como el miembro, y un entero que no es miembro lanza `ValueError`
al entrar. Los valores de los miembros se leen de la fuente, así que un `= n` explícito se
respeta.

## Structs planos

Un `struct` que no es `@[vc_class]` pasa a ser un `dict` de sus campos. Un campo se boxea
con su propia regla y se lee por nombre, así que una clave ausente es `KeyError` y un tipo
de campo equivocado `TypeError`. Un campo sin regla, a cualquier profundidad, es un
diagnóstico.

## Referencias a instancias

Un `&T` donde `T` es un `@[vc_class]` pasa la instancia misma, no una copia: un parámetro
entrega a la función V un puntero al estado vivo de la instancia, y un resultado se empareja
de vuelta con la instancia a la que apunta. Ver [Clases y propiedades](classes.md).

## Structs, secuencias de struct y sumtypes

Un `struct` plano sale como `dict`. Al entrar, también acepta un namedtuple o cualquier
tupla con sus campos en orden, y un objeto que los guarde como atributos (una dataclass, un
`SimpleNamespace`). `@[vc_structseq]` sobre el struct hace que salga como una secuencia de
struct -- una tupla con campos con nombre, como `os.stat_result` -- que es más barata que un
dict y aparece como `NamedTuple` en el stub.

Un sumtype (`type Shape = int | string | Point`) cruza como la variante que contiene y se lee
probando las variantes: un `bool` solo para un `bool` real, los enteros antes que los
flotantes y después el orden declarado. El stub lo tipa como una unión.

## Fechas, decimales, enteros grandes y JSON

`time.Time` es un `datetime.datetime` (naive en ambos sentidos; uno con zona horaria se
convierte a UTC al entrar) y `time.Duration` un `datetime.timedelta`. `vcraft.Decimal` es un
`decimal.Decimal` guardado exactamente como su texto. `big.Integer` es un `int` de Python de
cualquier tamaño. `json2.Any` acepta cualquier valor con forma de JSON -- None, bool, int,
float, str, listas y dicts con claves str -- de forma recursiva, en ambos sentidos. El glue
importa `time`, `math.big` o `json2` solo cuando una firma los usa.

## NumPy y arrays N-dimensionales

`vcraft.NdArray` como parámetro acepta cualquier exportador de buffer (un array de NumPy,
`array.array`, `memoryview`) sin copiar y sin depender de NumPy, con su `kind`, `shape`,
`strides`, `readonly` y `c_contiguous`. `f64s()`, `f32s()`, `i64s()`, `i32s()` y `u8s()`
aliasan un array C-contiguo como slice de V; `at_f64(i, j)` sigue los strides de cualquier
otro. `vcraft.NdOut` como resultado (`vcraft.nd_out_f64(shape)`) se devuelve como un
`memoryview` N-dimensional que `numpy.asarray` envuelve sin copia.

## Strings prestados

Un `str` no se copia al entrar. Un parámetro `string`, los elementos de un `[]string`, las
claves y valores de un `map[string]T` y el valor que recibe un setter de propiedad o
`__setitem__` apuntan al buffer UTF-8 del propio objeto `str`. Son válidos durante la
llamada, también mientras `@[vc_nogil]` tiene el GIL liberado, porque el llamador mantiene
el `str`. Todo lo que se guarde más allá de la llamada - en un mapa, un campo de struct, un
global, un canal - hay que copiarlo antes con `.clone()`, o apunta a memoria que Python
libera en cuanto desaparece el `str`. Con `@[vc_nogil]`, los elementos de una lista que
otro hilo modifica durante la llamada también pueden desaparecer a mitad de la llamada.

## Helpers sin copia

Las demás reglas anteriores copian los números y construyen contenedores nuevos. Tres
helpers existen para el camino caliente donde copiar un buffer no es aceptable:

- `vcraft.bytes_arg` (para un parámetro `[]u8`) aliasa el argumento sin copiar: un `bytes`
  exacto no cuesta nada; cualquier otra cosa va por una vista cuya referencia fija al
  exportador. El slice no debe sobrevivir a la llamada.
- `vcraft.bytes_view` hace lo mismo para un valor bytes-like que Python *devolvió* de una
  llamada. Un `bytes` exacto se aliasa (el llamador mantiene el objeto vivo mientras use
  el slice); cualquier otra cosa va por una vista que fija al exportador. `release` la
  devuelve.
- `vcraft.to_py_bytes_slice` va en la otra dirección y copia, porque los `bytes` de Python
  tienen almacenamiento inmutable propio. Un retorno sin copia a Python es `@[vc_memoryview]`,
  que entrega el slice native-backed como un `memoryview` escribible.

## Helpers del GIL

- `vcraft.with_gil(fn () {})` adquiere el GIL para un bloque y lo devuelve en todos los
  caminos, panic incluido. Úsalo dentro de un hilo V creado con `spawn` antes de tocar
  Python.
- `vcraft.released(fn () {})` es la imagen especular: ejecuta un bloque con el GIL
  *liberado*, para trabajo V puro, y lo re-adquiere en un `defer`. El bloque no debe llamar
  a Python.
- `vcraft.gil_ensure()` / `vcraft.gil_release(state)` son el par manual, para los casos que
  las formas de bloque no cubren (un `poll` con timeout, una elección entre condiciones).

## Llamar a corrutinas de Python

`vcraft.run_coroutine(coro)` y `vcraft.call_async(callee, args)` conducen una corrutina de
Python hasta el final en el hilo actual. El camino rápido es un único `send(None)` (~1.8
us); el bucle sólo se entra cuando la corrutina suspende. El GIL se mantiene durante toda
la llamada, así que V puede liberarlo con `released` para trabajo V puro, pero la corrutina
no se pausa mientras V trabaja. Ver `examples/async_callback` para el caso canónico.
