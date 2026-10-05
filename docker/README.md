# The images

Two images, each built for x86_64 and aarch64 on native runners and published as
multi-arch manifests:

| Image | Base | Wheels |
| ----- | ---- | ------ |
| `vcraft-manylinux` | `quay.io/pypa/manylinux_2_28` | `manylinux_2_28` |
| `vcraft-musllinux` | `alpine:3.23` | `musllinux_1_2` |

Each carries the same three things: a C toolchain, CPython with its headers, V
built from source, and vcraft compiled from the repository. Everything else --
the interpreters in manylinux, auditwheel -- comes from the base image.

## Why V is built from source

The V release binary does not run in either image: on manylinux it links a newer
glibc than the base provides, and on musl it does not run at all. A V compiled
in the image links the image's libc, which is also what makes the extensions it
compiles match the claimed tag rather than merely carry it.

Two pins keep that source build reproducible. `V_COMMIT` is the V revision, pinned
because the release tag predates the V this repository was developed against.
`VC_COMMIT` is the `vc` bootstrap snapshot, pinned to a commit contemporary with
it, because a newer bootstrap enforces checker rules the V sources predate. When
the host's V moves, both move to commits from just before its date.

The prebuilt tcc bundle is deliberately not used: its compiler binary does not
run on an older glibc or on musl, and its `libgc.a` then fails to link with an
`undefined reference to sigsetjmp` and nothing naming the bundle. tinycc and
Boehm are compiled from source with the system compiler instead -- except on
musl, where V links the system's Boehm itself and tcc is skipped, because
tinycc's bounds checker uses glibc-isms that do not compile on musl.

## Building and publishing

```console
$ docker build -f docker/manylinux.Dockerfile \
    --build-arg VCRAFT_REF=$(git rev-parse HEAD) \
    -t vcraft-manylinux:local .
$ docker run --rm -v "$PWD:/work" -w /work vcraft-manylinux:local \
    vcraft build --target linux-x86_64-gnu --manylinux 2_28
```

`VCRAFT_REF` is the revision being baked in. A different revision always rebuilds
vcraft without rebuilding V, so a stale binary can never ship with fresh sources.

Publishing is `.github/workflows/release-images.yml`, triggered by an
`images/v*` tag. Each architecture builds on a native runner -- there is no QEMU
anywhere, because emulating a compiler is how a build becomes unreproducible --
and the per-architecture tags are merged into one multi-arch manifest. The same
workflow verifies each image by building a fresh project inside it and importing
the result, so a published image is one that compiled that day, not one that
built when its Dockerfile was written.
