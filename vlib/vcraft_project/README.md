# vcraft_project

Reading `vcraft.toml`, scaffolding a project, and driving a build.

`vcraft_project` knows nothing about CPython or about the annotation vocabulary. It
reads a configuration, writes a directory of files, invokes the code generator, invokes
the compiler, and hands the result to the wheel writer. That separation is what lets
each piece be tested on its own: the TOML parser is tested against strings, the wheel
writer against `zipfile`, and the CLI against a real project.

## `vcraft.toml`, not `v.mod`

`v.mod` is V's manifest and names the V module. A wheel also needs a distribution name,
a version, a licence and a `Requires-Python`, and none of those belong to V: adding a
key to `v.mod` would mean teaching V a field it has no use for. So the packaging
configuration lives here, and `v.mod` is left alone.

## The TOML subset

The parser handles tables, arrays of tables, strings, booleans, integers and arrays of
strings, and refuses the rest with a line number. That is the entire grammar a build
configuration needs. It is not a general TOML parser on purpose: a packaging tool that
cannot build a project because a transitive dependency could not be fetched is a
packaging tool with a very confusing failure mode, and the configuration it reads is
hand-written by the person using it.

Values are looked up with a default rather than checked. A missing or mistyped key takes
its fallback, which is what makes `vcraft develop` work in a project that never
mentions `strip`.

## V 0.5.2 constraints, and the ones that cost the afternoon

**A struct literal leaves an omitted field at 0, not at 1.** The parser's line counter
started at 0 and the first thing it did was read `lines[at - 1]`, which is
`lines[-1]`. The failure is an index-out-of-range with a *negative* index, which says
nothing about a counter being off by one.

**A descending range literal is rejected as empty.** `count - 1 .. 0` never executes,
so `write_code` in the wheel writer compiled, ran, and silently emitted no bits: every
output was a bare block header. Written as an explicit countdown.

**V copies a struct on assignment.** This is the one that shaped the parser's design.
Keeping a `root`, a `current` and a collected list in step needs a write-back after
every key, and a write-back that looks correct can still leave a stale copy: the
symptom is a key that parses without error and reads back empty. So there is exactly one
table under construction, and a nested table is filed when the next header or the end of
the file is reached.

**A field reached through a loop variable is read-only.** `entries[i].value.tables << t`
needs three `mut`s, a pointer and, at the end, `unsafe`. Every list that grows is
therefore rebuilt and reassigned rather than appended to in place. The version that
compiles with a pointer loses the append on a repeated `[[name]]`, so the first table
survives and the rest are dropped without an error.

**A public struct with a private field type compiles, and then reads as garbage** across
a module boundary.

## `PyInit_` is named after the module

The code generator takes both a `module` and a `package`, and `package` is what
`PyInit_` is named. For a single extension module those are the same thing, and passing
the distribution name produces a shared object that exports `PyInit_<distribution>`:
the interpreter loads it and then reports "does not define module export function" the
moment anything imports it. The build passes the module name.

## A class constructor needs `@[vc_fn]`

`link_classes` finds a class's constructor by looking for a `new_<Class>` among the
exported functions. Without the annotation it is an ordinary helper, the lookup misses,
and `tp_new` returns an instance whose state block is whatever the allocator left. No
error anywhere: `repr(c)` prints two large integers and `c.is_zero` is `False`.

The generator then removes the constructor from the exported set, because a `new_*` is
the type's `tp_new` rather than something Python can call.

## The interpreter tag has no separator

`sys.version_info` gives `3.14` and the tag wants `314`. A tag of
`cp3.14-cp314-linux_x86_64` is not one pip knows, and it rejects the wheel with "no
matching distribution". The platform tag comes from `sysconfig.get_platform()` rather
than from `uname`, which is how a wheel ends up tagged `linux_x86_64` instead of
`manylinux_2_17_x86_64`.

## Shell arguments are quoted

The compiler is invoked through the shell, because `-cflags` takes several values at
once. `-path` takes `dir|@vlib`, and an unquoted `@` is a word the shell tries to run:
the error is "not found", naming a directory that exists. Every argument is quoted.

## `develop` copies rather than installs

It writes the extension into the active environment's `platlib` rather than running
`pip install` on the wheel. A local wheel install needs a build-isolation environment
for a package with no dependencies, which is more moving parts than copying one file.
The `.dist-info` is deliberately left out: `develop` is for working on an extension, not
for a dependency graph, and a half-written `dist-info` confuses `importlib.metadata`
more than a missing one.

`VIRTUAL_ENV` is read rather than inferred, because a `develop` that installs into the
system Python while the user is in a virtualenv is the most annoying thing a build tool
can do.

## Tests

```console
$ ./scripts/build-vcraft.sh
$ python3 tests/cli/test_cli.py
```

Every step runs the real binary against a real project in a temporary directory:
scaffold, build, install with `pip`, install with `develop`, use. Nothing is stubbed,
because the failures worth catching are the ones where the pieces disagree — a tag the
installer rejects, a `PyInit_` that does not match the file name, a constructor that
never ran — and a stubbed test cannot see any of them.
