# Referencia de tipos

La tabla de tipos, en ambos sentidos. Cualquier cosa que no esté aquí es un diagnóstico en
tiempo de generación que nombra fichero, línea y columna.

| Tipo V | Tipo Python | Sentido y notas |
| --- | --- | --- |
| `bool` | `bool` | Cualquier objeto al entrar (test de veracidad); `True`/`False` al salir |
| `i8`, `i16`, `i32`, `int`, `i64`, `isize` | `int` | Con rango comprobado; el desbordamiento lanza `OverflowError` |
| `u8`, `u16`, `u32`, `u64`, `usize` | `int` | Negativo o desbordamiento lanza `OverflowError` |
| `f32`, `f64` | `float` | También acepta un `int` |
| `rune` | `int` | El punto de código |
| `string` | `str` | UTF-8 |
| `[]u8` | `bytes` | Bytes-like al entrar sin copiar; un `bytes` nuevo al salir |
| `[]T` | `list` | Cualquier secuencia al entrar; una `list` al salir |
| `[N]T` | `list` | Exactamente N ítems al entrar; una `list` al salir |
| `?T` | `T` o `None` | `none` ↔ `None` |
| `map[K]T` (`K` escalar o `str`) | `dict` | Claves escalares/`str`; un `dict` nuevo al salir |
| `(A, B, …)` (resultado) | `tuple` | Sólo retorno multivalor |
| `math.complex.Complex` | `complex` | |
| `voidptr` | cualquiera | Prestado; la referencia es tuya |
| `vcraft.PyObj` (resultado) | cualquiera | Propia; la referencia va al llamador |
| `&T` (`T` un `@[vc_class]`) | `T` | Referencia a instancia; acepta una subclase |
| un `enum` | ese `enum.IntEnum` | Miembro al entrar/salir; un no-miembro lanza `ValueError` |
| un `struct` plano | `dict` | Los nombres de campo como claves |
| `void`, `!void` | `None` | |
| `!T` | `T` o lanza | Ver [Errores y pánicos](../guide/errors.md) |

## Elementos de composite

Un elemento de un contenedor puede ser a su vez un contenedor, un enum o un struct plano:
`?[]int`, `[][]int`, `map[string][]int`, `[]Color`, `[]Point` cruzan todos. El elemento de
`[]u8` se trata aparte como `bytes`; un elemento `u8` en otro sitio no tiene reader.

## Campos

Un campo de `@[vc_class]` sigue la tabla pero se limita a escalares y referencias
`@[vc_ref]`: un `string` o `[]T` en memoria propiedad de CPython sería un puntero que el
recolector de V no ve. Un campo de un `struct` plano puede ser cualquier tipo con regla,
comprobado recursivamente.
