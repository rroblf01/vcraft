# Anotaciones

La API de una extensión vcraft es un fichero fuente V. Marcas con anotaciones `@[vc_*]` las
declaraciones que Python debe ver; el generador las lee de la fuente y escribe el
pegamento, los stubs de tipos y el módulo.

```v
module my_extension_native

import vcraft

// greet devuelve un saludo para `name`.
//
// El comentario de documentación pasa a ser el `__doc__` de Python.
@[vc_fn]
pub fn greet(name string) string {
	return 'Hello, ${name}!'
}

// Counter es una clase. Los campos son escalares y pasan a ser atributos de
// lectura/escritura; los métodos son métodos; una propiedad es un atributo de
// sólo lectura.
@[vc_class]
pub struct Counter {
mut:
	@[vc_field] value int
	@[vc_field] step  int
}

// new_counter es el constructor. Se crea una instancia llamando al tipo.
@[vc_fn]
pub fn new_counter() &Counter {
	return &Counter{ step: 1 }
}

// increment suma step a value y devuelve el total nuevo.
@[vc_method]
pub fn (mut c Counter) increment() int {
	c.value += c.step
	return c.value
}
```

## Cómo funcionan los nombres

Los nombres en Python se toman de la declaración V, tal cual. El receptor de un método
declara la clase a la que pertenece, y `new_<clase>` es el constructor. Los comentarios de
documentación pasan a `__doc__`, la firma marshalizada a `__text_signature__`, y la misma
fuente produce un stub `.pyi`, así que `help()` y un type checker ven lo mismo.

## El vocabulario de un vistazo

| Anotación | Aplica a | Efecto |
| --- | --- | --- |
| `@[vc_fn]` | `pub fn` | Exporta la función como un callable de módulo |
| `@[vc_class]` | `pub struct` | Crea un tipo Python respaldado por el struct V |
| `@[vc_method]` | métodos | Añade el método a la clase de su receptor |
| `@[vc_field]` | campos | Expone el campo como atributo |
| `@[vc_property]` | métodos | Registra el método como `property` |
| `@[vc_static]` | métodos | Registra el método como `staticmethod` |
| `@[vc_classmethod]` | métodos | Registra el método como `classmethod` |
| `@[vc_base]` | `pub struct` | Hereda de la clase indicada |
| `@[vc_ref]` | campos | Una referencia fuerte a otra instancia |
| `@[vc_weakref]` | `pub struct` | Permite `weakref.ref(instancia)` sobre instancias de la clase |
| `@[vc_dict]` | `pub struct` | Da a las instancias un `__dict__` de atributos arbitrarios |
| `@[vc_buffer]` | campos | Un `[]T` nativo persistente de escalares |
| `@[vc_error]` | `pub struct` | Un tipo de error `!T` con `msg()`/`code()` |
| `@[vc_len]` / `@[vc_getitem]` / `@[vc_setitem]` / `@[vc_contains]` | métodos | `len()`, `obj[i]`, `obj[i] = v`, `x in obj` |
| `@[vc_mapping]` | `pub struct` | Activa el protocolo de mapeo (`obj[key]`, `obj[key] = v`, `del obj[key]`, `len(obj)`) |
| `@[vc_map_getitem]` / `@[vc_map_setitem]` / `@[vc_map_delitem]` | métodos | Handlers del protocolo de mapeo |
| `@[vc_iter]` / `@[vc_next]` | métodos | `__iter__` / `__next__` |
| `@[vc_eq]` / `@[vc_lt]` … | `pub fn` | Comparación y orden |
| `@[vc_hash]` | `pub fn` | `__hash__` |
| `@[vc_add]` … `@[vc_invert]` | `pub fn` | Operadores aritméticos, de bits y unarios |
| `@[vc_const]` | `pub const` | Una constante de módulo |
| `@[vc_defaults]` | `pub fn`, métodos | Valores por defecto de argumentos |
| `@[vc_handle]` | campos de struct | Estado nativo del que la clase es dueña: un puntero y su liberador, liberado en dealloc |
| `@[vc_opaque]` | `pub fn` | Un resultado `voidptr` viaja en cápsula, y cada parámetro `voidptr` se desenvuelve de una |
| `@[vc_nogil]` | `pub fn` | Se ejecuta con el GIL liberado (métodos incluidos) |
| `@[vc_raw]` | `pub fn` | Sin marshalling; tú manejas `PyObject *` |
| `@[vc_mapping]` | `pub struct` | Activa el protocolo de mapeo (`obj[key]`, `obj[key] = v`, `del obj[key]`) |
| `@[vc_pass_module]` | `pub fn` | Pasa el objeto módulo como primer argumento |
| `@[vc_rename: 'name']` | `pub fn`, `pub struct`, campos | Renombra el nombre del lado Python |
| `@[vc_from_py: 'fn']` | `pub fn` | Reemplaza el reader estándar de cada parámetro por un conversor custom |
| `@[vc_into_py: 'fn']` | `pub fn` | Reemplaza el boxing estándar del resultado por un conversor custom |
| `@[vc_memoryview]` | `pub fn`, métodos | Devuelve un slice nativo como `memoryview` escribible |

La lista completa, con la firma exacta que espera cada una, está en la
[referencia de anotaciones](../reference/annotations.md).


## Argumentos sin copia y el patrón de syscalls

`bytes_arg` es el helper de runtime que hace que un parámetro `[]u8` aliasa el argumento
sin copiar: un `bytes` exacto no cuesta nada, cualquier otra cosa va por una vista que fija
al exportador, y el slice no debe sobrevivir a la llamada. Es la contraparte de
`bytes_view` para resultados. El glue generado lo usa para cada parámetro `[]u8`, así que
el V escrito a mano sólo lo necesita cuando lee un objeto bytes-like que Python devolvió.

`@[vc_nogil]` se aplica también a métodos, no sólo a funciones de módulo: un método que
sólo toca estado V puede ejecutarse con el GIL liberado, y el receptor es un puntero al
estado vivo de la instancia como en cualquier otro método. Úsalo junto con `vcraft.released`
para el patrón de syscalls - una función `@[vc_nogil]` que hace la llamada bloqueante, y
trabajo V puro envuelto en `released` alrededor - para que una operación larga no bloquee
a los demás hilos Python. El bloque pasado a `released` no debe llamar a Python.

## Siguiente

- [Tipos](types.md)
- [Clases y propiedades](classes.md)
- [Errores y pánicos](errors.md)
