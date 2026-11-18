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

Al subir un tag `v*` se ejecuta la matriz, se construye un sdist y después el job
`publish` sube los wheels y el sdist a PyPI con
[trusted publishing](https://docs.pypi.org/trusted-publishers/): el job obtiene un token
OIDC de GitHub (`permissions: id-token: write`) y PyPI lo cambia por una credencial de
corta duración, así que no se guarda ningún token ni secreto. El resto del workflow es de
solo lectura (`contents: read`).

Configuración única, en PyPI: en los ajustes de *Publishing* del proyecto (o como
publicador pendiente antes de la primera versión) añade un publicador de GitHub con tu
repositorio, el workflow `build.yml` y el entorno `pypi`. Crea el entorno `pypi` en los
ajustes del repositorio y añade revisores obligatorios ahí si una publicación debe esperar
una aprobación. Después:

```console
$ git tag v0.1.0 && git push origin v0.1.0
```

Cada fichero queda además atestiguado: el job firma su procedencia de build con
`attest-build-provenance` de GitHub (se comprueba con
`gh attestation verify <fichero> --repo <owner/repo>`), y PyPI recibe attestations PEP 740,
que muestra junto al fichero y que las herramientas pueden verificar antes de instalar.

## Los workflows como texto

Los ficheros que escribe `generate-ci` también se guardan en el repositorio, generados para
un proyecto de ejemplo, en
[`templates/ci/`](https://github.com/rroblf01/vcraft/tree/main/templates/ci): `build.yml`
(un wheel por CPython), `build-abi3.yml` y `build-free-threading.yml`. Léelos antes de
generar el tuyo, o copia uno y sustituye `mypkg_native` por tu módulo.

## Ejecutar las suites del propio proyecto

El repositorio de vcraft prueba cada afirmación de esta documentación. Si vas a contribuir,
las suites están en `tests/` (ver `AGENTS.md`).
