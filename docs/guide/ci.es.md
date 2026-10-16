# Integración continua

`vcraft generate-ci` escribe un workflow de GitHub Actions que construye un wheel por cada
Python y plataforma soportados, instala e importa cada uno, y queda listo para publicar en
PyPI.

```console
$ vcraft generate-ci
wrote .github/workflows/build.yml
```

La matriz sale del manifiesto. Sin `abi3`, un wheel por intérprete; con `abi3 = "3.11"`, un
wheel por plataforma que cubre todos los CPython desde el suelo. Free-threading añade celdas
`3.13t`, `3.14t` y `3.15t`.

## Qué hace el workflow

- Construye dentro de las imágenes publicadas `vcraft-manylinux` / `vcraft-musllinux`, así
  que un wheel de Linux lleva la política de libc correcta.
- Ejecuta las celdas aarch64 en runners arm.
- Etiqueta macOS con la arquitectura realmente construida (`macosx-arm64`).
- Instala e importa cada wheel antes de subirlo, así que un wheel que construye pero no
  carga hace fallar la ejecución.
- Usa la [acción de vcraft](https://github.com/rroblf01/vcraft/tree/main/actions/vcraft-action)
  para instalar el toolchain y construir.

## Publicar desde la CI

El workflow generado está listo para publicar. Añade un token (un secreto
`PYPI_API_TOKEN` o trusted publishing) y el paso de release sube los wheels que produjo la
matriz.

## Ejecutar las suites del propio proyecto

El repositorio de vcraft prueba cada afirmación de esta documentación. Si vas a contribuir,
las suites están en `tests/` (ver `AGENTS.md`).
