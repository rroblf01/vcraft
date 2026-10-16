# Wheels

`vcraft build` writes a complete wheel, from scratch: DEFLATE, ZIP, tar, SHA-256, CRC32,
`METADATA`, `WHEEL` and `RECORD`, with no `zlib`.

```console
$ vcraft build --release
dist/my_extension-0.1.0-cp314-cp314-linux_x86_64.whl
```

## Tags

The tag names the interpreter, the ABI and the platform. A build against a free-threaded
interpreter is tagged `cp314t`; a cross build is tagged for the target, not the host.

## Stable ABI (abi3)

`--abi3 <version>` builds one wheel usable from `version` onwards, so a single wheel covers
several CPythons:

```console
$ vcraft build --abi3 3.11
dist/my_extension-0.1.0-cp311-abi3-linux_x86_64.whl
```

The tag names the floor, not the interpreter that built it. An abi3 extension is
`.abi3.so` on Unix and plain `.pyd` on Windows, because that is the only suffix the Windows
loader imports.

## Linux policies

A wheel for Linux should name the libc it was linked against. Claiming it explicitly:

```console
$ vcraft build --target linux-x86_64-gnu --manylinux 2_17
$ vcraft build --target linux-x86_64-musl --musllinux 1_2
```

Without a policy, the tag is `linux_x86_64`, which PyPI refuses.

## Cross-compilation

`--target` builds for another platform when its compiler is present:

```console
$ vcraft build --target linux-aarch64-gnu --manylinux 2_17
$ vcraft build --target windows-amd64
```

The same `--target` list works in `vcraft.toml` (see [Configuration](config.md)) and in the
generated CI.

## Publishing

```console
$ vcraft publish
```

`publish` refuses an editable build before choosing an uploader, so a local path cannot
reach PyPI by accident.
