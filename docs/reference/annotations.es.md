# Referencia de anotaciones

Todas las anotaciones a las que reacciona el generador. Cualquier otra cosa en el espacio
`vc_` es un diagnóstico, no una omisión silenciosa.

| Anotación | Aplica a | Efecto |
| --- | --- | --- |
| `@[vc_fn]` | `pub fn` | Exporta la función como callable de módulo. `new_<clase>` es un constructor. |
| `@[vc_class]` | `pub struct` | Crea un tipo Python respaldado por el struct V. |
| `@[vc_method]` | métodos | Añade el método a la clase de su receptor. |
| `@[vc_field]` | campos | Expone el campo como atributo de lectura/escritura. Escalares (o `@[vc_ref]`). |
| `@[vc_buffer]` | campos | Un `[]T` nativo persistente de escalares, liberado al dealloc. |
| `@[vc_buffer_typed]` | campos | Con `@[vc_buffer]`: lo expone como `memoryview` tipado. |
| `@[vc_property]` | métodos | Registra el método como `property`. |
| `@[vc_static]` | métodos | Registra el método como `staticmethod`. |
| `@[vc_classmethod]` | métodos | Registra el método como `classmethod`. |
| `@[vc_base]` | `pub struct` | Hace que la clase herede de la indicada. |
| `@[vc_ref]` | campos | Expone el campo como referencia fuerte a otra instancia. |
| `@[vc_error]` | `pub struct` | Hace el struct utilizable como error de una función `!T`. |
| `@[vc_len]` | métodos | `__len__` (`len(instance)`, veracidad). Sin argumentos, resultado entero. |
| `@[vc_getitem]` | métodos | `__getitem__` (`instance[i]`). Un argumento entero. |
| `@[vc_contains]` | métodos | `__contains__` (`x in instance`). Un argumento, resultado bool. |
| `@[vc_iter]` | métodos | Hace de la instancia su propio iterador (`__iter__`). |
| `@[vc_next]` | métodos | Un ítem por llamada (`__next__`). |
| `@[vc_eq]` | `pub fn` | `__eq__` / `__ne__`. |
| `@[vc_lt]`, `@[vc_le]`, `@[vc_gt]`, `@[vc_ge]` | `pub fn` | El operador de orden correspondiente. |
| `@[vc_hash]` | `pub fn` | `__hash__`. |
| `@[vc_add]`, `@[vc_sub]`, `@[vc_mul]`, `@[vc_truediv]`, `@[vc_floordiv]`, `@[vc_mod]`, `@[vc_pow]` | `pub fn` | El operador aritmético correspondiente. |
| `@[vc_lshift]`, `@[vc_rshift]`, `@[vc_and]`, `@[vc_or]`, `@[vc_xor]` | `pub fn` | El operador de bits correspondiente. |
| `@[vc_radd]`, `@[vc_rsub]`, … | `pub fn` | La forma reflejada, usada cuando la instancia es el operando derecho. |
| `@[vc_neg]`, `@[vc_pos]`, `@[vc_abs]`, `@[vc_invert]` | `pub fn` | El operador unario. |
| `@[vc_const]` | `pub const` | Expone la constante como atributo de módulo (literal int, float, bool o string). |
| `@[vc_defaults]` | `pub fn`, métodos | Valores por defecto: `@[vc_defaults: 'step=1, name="x"']`. |
| `@[vc_raw]` | `pub fn` | Sin marshalling; recibes y devuelves `voidptr`. |
| `@[vc_nogil]` | `pub fn` | Ejecuta la llamada con el GIL liberado. |
| `@[vc_memoryview]` | `pub fn`, métodos | Devuelve un slice nativo como `memoryview` escribible (sin copia). |

## Firmas

Algunas anotaciones esperan una forma concreta, y el generador reporta el desajuste en vez
de emitir pegamento que no compila.

- **Comparación y orden** (`@[vc_eq]`, `@[vc_lt]`, …) son funciones libres sobre dos
  punteros de estado, porque V permite un receptor por método y una comparación necesita dos
  operandos. El cuerpo carga el estado con `vcraft.load_state`.
- **`@[vc_hash]`** toma un puntero de estado y devuelve un entero.
- **Operadores numéricos** son funciones libres `(self &T, operando) -> resultado`: el
  operando es un escalar (`int`, `u64`, `f64`, `bool`) u otro `&T`, y el resultado es un
  número o un `T` nuevo que vcraft reserva y rellena. El nombre empieza por el nombre
  snake_case de la clase.
- **`@[vc_len]`** no toma argumentos y devuelve un entero; **`@[vc_getitem]`** toma un
  entero; **`@[vc_contains]`** toma un argumento y devuelve un bool.
- **`@[vc_iter]`** y **`@[vc_next]`** van juntas: un iterador que no puede producir ítems es
  una trampa, y los ítems sin iterador son inalcanzables.

## Nombres

Los nombres Python son los nombres V, tal cual. Los comentarios de documentación pasan a
`__doc__`, la firma marshalizada a `__text_signature__`, y la misma fuente escribe un stub
`.pyi`. `@[vc_methods]` es la grafía pre-1.0 de `@[vc_method]` y sigue funcionando, con un
aviso.
