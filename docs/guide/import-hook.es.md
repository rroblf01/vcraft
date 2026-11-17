# Importar ficheros `.v` y notebooks

No todo fragmento de V necesita un proyecto. Para un script, un experimento o un notebook,
el paquete `vcraft_tool` que trae `pip install vcraft` puede compilar un único fichero V al
importarlo, como hace `pyximport` con Cython.

## `import vcraft_tool.auto`

```python
import vcraft_tool.auto   # instala el import hook
import fastmath           # compila fastmath.v encontrado en sys.path y lo importa

print(fastmath.square(12))
```

`fastmath.v` es el módulo completo:

```v
@[vc_fn]
pub fn square(x int) int {
	return x * x
}
```

- Si no tiene línea `module`, se añade; si la tiene, debe nombrar el módulo que se importa.
- El build se guarda en caché en `$VCRAFT_HOME/auto` (si no, `$XDG_CACHE_HOME/vcraft/auto`,
  y si no, `~/.cache/vcraft/auto`), con clave el código, el intérprete, la plataforma y la
  versión de vcraft. La primera importación compila (segundos); las siguientes cargan el
  módulo de la caché.
- Editar el fichero lo recompila en la siguiente importación de un proceso nuevo. Un
  módulo de extensión no se puede recargar dentro de un intérprete en marcha.
- Los builds son `--release`. Un error de compilación se lanza como `ImportError` con el
  mensaje del compilador.
- `vcraft_tool.auto.build(source, name)` compila código V guardado en una cadena y
  devuelve la ruta de la extensión; `vcraft_tool.auto.load(path, name)` la importa.

El binario que se usa es `$VCRAFT_BIN` si está definido; si no, el incluido en el paquete
`vcraft` instalado; y si no, `vcraft` en el `PATH`.

## Jupyter e IPython: `%%vcraft`

```python
%load_ext vcraft_tool.jupyter
```

```v
%%vcraft
@[vc_fn]
pub fn add(a int, b int) int {
	return a + b
}
```

Tras ejecutar la celda, `add` es un nombre del notebook. Cada nombre público que exporta la
celda se copia al espacio de nombres del usuario; `%%vcraft mod` además asocia el propio
módulo a `mod`. Cada texto de celda distinto es su propio módulo (`vcraft_cell_<hash>`),
así que editar y volver a ejecutar una celda carga el código nuevo sin reiniciar el kernel.

Cuando el código ya no cabe en una celda, `vcraft new` (o `vcraft init` en un proyecto
Python existente) lo convierte en un paquete con su wheel.
