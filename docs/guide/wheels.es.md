# Wheels

`vcraft build` escribe un wheel completo, desde cero: DEFLATE, ZIP, tar, SHA-256, CRC32,
`METADATA`, `WHEEL` y `RECORD`, sin `zlib`.

```console
$ vcraft build --release
dist/my_extension-0.1.0-cp314-cp314-linux_x86_64.whl
```

## Tags

El tag nombra el intérprete, la ABI y la plataforma. Un build contra un intérprete
free-threaded se etiqueta `cp314t`; un cross build se etiqueta para el target, no para el
host.

## ABI estable (abi3)

`--abi3 <versión>` construye un wheel usable desde `versión` en adelante, así que un solo
wheel cubre varios CPython:

```console
$ vcraft build --abi3 3.11
dist/my_extension-0.1.0-cp311-abi3-linux_x86_64.whl
```

El tag nombra el suelo, no el intérprete que lo construyó. Una extensión abi3 es `.abi3.so`
en Unix y `.pyd` a secas en Windows, porque es el único sufijo que el cargador de Windows
importa.

## Políticas de Linux

Un wheel para Linux debería nombrar la libc contra la que se enlazó. Declararlo
explícitamente:

```console
$ vcraft build --target linux-x86_64-gnu --manylinux 2_17
$ vcraft build --target linux-x86_64-musl --musllinux 1_2
```

Sin política, el tag es `linux_x86_64`, que PyPI rechaza.

## Compilación cruzada

`--target` construye para otra plataforma cuando su compilador está presente:

```console
$ vcraft build --target linux-aarch64-gnu --manylinux 2_17
$ vcraft build --target windows-amd64
```

La misma lista de `--target` funciona en `vcraft.toml` (ver [Configuración](config.md)) y en
la CI generada.

## Publicar

```console
$ vcraft publish
```

`publish` rechaza un build editable antes de elegir un uploader, así que una ruta local no
puede llegar a PyPI por accidente.
