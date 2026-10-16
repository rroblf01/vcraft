# Clases y propiedades

Un `struct` con `@[vc_class]` pasa a ser un tipo Python respaldado por el struct V. El
estado vive dentro del objeto (tras la cabecera PyObject), así que construir paga una sola
reserva y un método no sigue ningún puntero.

## Campos

`@[vc_field]` expone un campo como atributo de lectura/escritura. Los campos deben ser
escalares (o una referencia a instancia, ver abajo): un `string` o un `[]T` en memoria
propiedad de CPython sería un puntero que el recolector de V no ve. Los strings van detrás
de métodos, que marshalling a/desde `str`.

```v
@[vc_class]
pub struct Counter {
mut:
	@[vc_field] value int
	@[vc_field] step  int
}
```

## Constructores

`new_<clase>` es el constructor, que corre en `tp_new`. Puede tomar argumentos, enlazados
con las mismas reglas de marshalling que un método. Se crea una instancia llamando al tipo:

```v
@[vc_fn]
pub fn new_counter() &Counter {
	return &Counter{ step: 1 }
}
```

## Métodos y propiedades

El receptor de un método nombra su clase. `@[vc_property]` lo convierte en un atributo de
sólo lectura; `@[vc_static]` y `@[vc_classmethod]` son las dos formas a nivel de clase.

```v
@[vc_method]
pub fn (mut c Counter) increment() int {
	c.value += c.step
	return c.value
}

@[vc_method]
@[vc_property]
pub fn (c &Counter) is_zero() bool {
	return c.value == 0
}
```

## Herencia

`@[vc_base]` hace que una clase herede de otra. El estado es el struct de la base seguido
del de la subclase, así que un método de la base lee los mismos bytes en una instancia de
la subclase, y una cadena se publica al recolector de CPython.

## Referencias a instancias

Un parámetro o resultado `&T` pasa la instancia misma. Un parámetro entrega a la función V
un puntero al estado vivo de la instancia, así que lee y escribe los mismos bytes que un
método; un resultado vuelve como la instancia a la que apunta el puntero, emparejada por
dirección contra el receptor y los argumentos `&T` de la llamada.

```v
@[vc_method]
pub fn (c &Counter) self_ref() &Counter {
	return c
}
```

Un resultado `&T` que apunta a cualquier otro sitio lanza `RuntimeError`: vcraft no adivina
un objeto que no posee.

## Operadores

`@[vc_eq]`, `@[vc_lt]` y los demás llenan los slots de comparación. Los operadores numéricos
(`@[vc_add]`, `@[vc_mul]`, `@[vc_neg]`, …) llenan los slots numéricos de CPython: un
operador es una función libre cuyo nombre empieza por el nombre snake_case de la clase y
cuyo primer parámetro es `&T`.

```v
@[vc_add]
pub fn counter_add(a &Counter, n int) Counter {
	return Counter{ value: a.value + n, step: a.step }
}
```

Un escalar a la izquierda (`2 + counter`) llega a la función reflejada `@[vc_radd]`, o a la
directa si el operador es conmutativo. Ver la
[referencia de anotaciones](../reference/annotations.md).
