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

## abi3 is not the same build with a different tag

Building against the stable ABI changes three things that have nothing to do with each
other, and each one produces a build that installs and then fails.

**The tag names the floor, not the interpreter.** PEP 425 spells an abi3 tag
`cp<floor>-abi3-<platform>`, so building 3.14 against the 3.12 stable ABI produces
`cp312-abi3-...`. Writing `cp314-cp312-...` makes every installer reject the wheel with
"no wheels with a matching Python version tag" — including on the interpreter that built
it.

**`PyModule_Create2` is not in the limited API.** Single-phase initialisation reads a
`PyModuleDef`'s fields directly, and the stable ABI hides them. An abi3 build has to use
multi-phase initialisation: `PyInit_` returns a module *spec* and the interpreter calls
back through a `Py_mod_exec` slot. The module arrives empty, so the method table has to
be installed by hand in that callback or every function is silently missing.

**The module cannot be a local of `PyInit_`.** Under multi-phase initialisation the
definition has to outlive the call that returns it, because the interpreter uses it
afterwards. A local is a dangling pointer by then.

Two smaller ones:

- `PyModuleDef_Init` is a macro of **one** argument. Declaring it with the two-argument
  form compiles and hands the interpreter's API version where it expects a definition
  pointer, so the first call segfaults inside CPython with nothing in the V source to
  explain it.
- `sizeof` works under `Py_LIMITED_API` even for a struct the ABI does not expose. A
  guard that answered "0 because the struct is hidden" looked reasonable and made every
  class fail with `tp_basicsize ... too small for base 'object'`. A guard that guesses
  is worse than no guard.

The runtime keeps one source serving both APIs and asks at run time which path to take,
because V's `$if` cannot see a `-cflags` define.

## The backend is text, not a V module

`pip install .` imports a named object from `pyproject.toml`. That object could be a V
extension, and it is not, for a reason that took a while to see clearly: a backend in V
would have to be *compiled* before it could run, so the frontend needs a working V
toolchain before it can resolve a build requirement — and resolving build requirements
is the step that decides whether V is needed at all. It cannot be a wheel for the same
reason.

So `vcraft_build.py` is generated text. It locates the binary, runs it, and returns the
artefact's name. Every hook does one thing, and the logic is in the binary where it can
be tested against a real project.

Three things in it are not obvious:

- PEP 517 wants the artefact's **name**, and pip joins it onto the directory it chose.
  Returning the path makes pip join it twice, and the error names a path with the
  directory inside itself.
- `prepare_metadata_for_build_wheel` may be omitted, but pip calls it when it is there
  and uses the answer without checking that it is a string. Returning `None` gives a
  `TypeError` inside pip's `os.path.join` with nothing pointing at the return statement.
- The sdist has to carry `pyproject.toml` and the backend. Without them it is a source
  tree with no way to build it: pip untars it, reads `pyproject.toml`, and finds
  nothing.

## A tar member is three things at once

The type flag, the padding and the field offsets each cost an afternoon, and each fails
in a way that looks like something else.

A directory written with the type flag for a regular file extracts to a zero-byte file
of the same name. `tar` lists every entry, the archive has the right length, and only
the frontend notices when it tries to create `pkg-0.1.0/src/` and finds a file there.
Python says "Not a directory".

Padding computed from the archive's running length rather than the member's own puts
every header after the first short file at the wrong offset. The reader only checks that
the checksum adds up before trusting a header, so it lists a file's contents as further
members.

And every numeric field is octal. Writing the size as decimal produces an archive that
has the right length and unpacks to files of the wrong size.

The checksum is the one field that covers itself, so it is written as eight spaces while
the sum is computed.

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
