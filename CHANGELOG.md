# Changelog

All notable changes to vcraft are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, minor releases could change the
annotation vocabulary, the `vcraft.toml` keys and the CLI.

## [1.7.0-dev] - unreleased

### Added

- **`@[vc_from_py]` and `@[vc_into_py]`.** Custom converters: `@[vc_from_py: 'fn']`
  replaces the standard reader for struct parameters, `@[vc_into_py: 'fn']` replaces
  the standard boxing of a struct result. The converter is a V function taking a
  `PyObj` (from_py) or the V value (into_py) and returning the other side, so a
  Python dict can cross as a V struct and back without manual marshalling at
  every call site.
- **`@[vc_weakref]`.** A class opts in to `weakref.ref(instance)`; vcraft turns
  on `Py_TPFLAGS_HAVE_GC` so the VM allocates a weakref list for each instance,
  even when the class holds no reference fields of its own.
- **`@[vc_dict]`.** A class gets an instance `__dict__` for arbitrary attributes,
  via managed dict (`tp_dictoffset = -1`).
- **`vcraft.PyScope` and `with_py_scope`.** Scope-based reference management:
  track temporaries with `scope.track(o)` and they are released on exit, on every
  path including a panic; `scope.keep(o)` lets a result survive the scope.
- **`from_py_bytes_borrowed`.** Naming consistency with `from_py_str_borrowed`.
- **`PyObj.type_obj()`.** Typed accessor for an object's type.
- **Sets, kwargs, PyObj convenience methods, composite readers/builders.**
  `new_set`, `set_add_owned`, `to_py_set`, `from_py_set`, `call_kw`,
  `call_method_kw`, `PyObj.call/getitem/setitem/getattr/setattr/hasattr`,
  `from_py_list`, `from_py_dict`, `to_py_obj_list`, `to_py_obj_dict`,
  `list_new`, `list_append_owned`, `list_set_owned`.

### Changed

- Documented that `released` drops the GIL and exposes V state to data races.
- Documented that `@[vc_buffer]` fields must be initialised with `buffer_new_*`.
- Documented that V closures capture by value.
- Documented memoryview ownership transfer.

## [1.6.0] - 2026-10-27

### Added

- **`to_py_obj_list` and `to_py_obj_dict`.** When the elements are already
  `PyObject *` (a decoder, a query result), the boxing closure passed to
  `to_py_list`/`to_py_dict` is the identity and costs a V call per element.
  These helpers build the list/dict directly, transferring ownership of each
  element without a per-element call.
- **`vcraft.PyObj` is a first-class parameter and result type.** A function
  can take and return `vcraft.PyObj` directly, with `!` error propagation and
  no `@[vc_raw]`: the generated glue treats it as a borrowed `PyObject *` on
  the way in and passes the owned reference through on the way out. This is the
  type for "a Python object of unknown shape" (a JSON value, a query row).
- **`from_py_list` and `from_py_dict`.** Read a list/tuple or a dict into a
  `[]PyObj` / `map[string]PyObj` of borrowed references, the counterparts of
  `to_py_obj_list`/`to_py_obj_dict`. A function walking a composite Python value
  (a decoder, a query result) no longer calls `item(i)` / `dict_items` by hand.
- **`from_py_bytes_borrowed` and `PyObj.type_obj()`.** Naming consistency with
  `from_py_str_borrowed` and a typed accessor for an object's type.
- **`list_new`, `list_append_owned`, `list_set_owned`.** Build a Python list
  incrementally without pre-sizing, transferring ownership of each appended
  item. The counterpart of `to_py_obj_list` for the streaming case.
- **`setattr` and `hasattr`.** Companions to the existing `getattr`: set an
  attribute (stealing the value) and test for one without raising.
- **Convenience methods on `PyObj`.** `call`, `call_method`, `getitem`,
  `setitem`, `getattr`, `setattr`, `hasattr` delegate to the existing helpers,
  so a function holding a `PyObj` can invoke, index and mutate it without
  dropping to `voidptr`.
- **`@[vc_setitem]`.** `instance[i] = value` now has a slot, the counterpart of
  `@[vc_getitem]`. The method takes an integer index and a value; an out-of-range
  index is the user's own `IndexError` from a `!T` method.
- **`@[vc_weakref]`.** A class opts in to `weakref.ref(instance)`; vcraft turns
  on `Py_TPFLAGS_HAVE_GC` so the VM allocates a weakref list for each instance,
  even when the class holds no reference fields of its own.
- **Sets.** `new_set`, `set_add_owned`, `to_py_set` and `from_py_set`
  mirror the list/dict helpers, plus `set_type()` and `PySet_New`/`PySet_Add`
  in the shim.
- **kwargs.** `call_kw`/`call_method_kw` (and `PyObj.call_kw`/`call_method_kw`)
  invoke a callable with keyword arguments, via `vpy_call_kw` in the shim.
- **`repr_f64` uses Python's shortest round-trip form.** It now renders
  through `PyObject_Repr`, matching `repr()`/`str()` of the equivalent Python
  float (scientific notation only when needed, non-finite values as
  `nan`/`inf`/`-inf`).

### Fixed

- **A function returning a freshly created Python object leaked one reference
  per call.** A `voidptr`/`pyobj` result was wrapped as
  `vcraft.borrow(result).new_ref().ptr`, so V had to hand back a borrowed
  pointer and could never transfer ownership of an object it had just built:
  the wrapper took a reference of its own and V's original was never released.
  The wrapper now passes the pointer through, and V returns an owned reference
  (the C extension convention). Pass-through helpers take their own reference
  before returning, so callers still receive one owned reference. Found while
  building `vjson`, where `decode` leaked ~330 bytes per call.

- **`repr()` and `str()` on `PyObj` leaked the object.** Both adopted the
  `PyObject_Repr`/`PyObject_Str` result with `steal` and never released it (the
  V string shares its memory, so a plain decref would have freed it). They now
  copy the string before decref'ing. Found while making `vjson`'s encode
  byte-identical to `orjson`.
- **`released` drops the GIL for the whole block.** Documented that this exposes
  V state to data races: the GIL protects Python objects, not V memory. Found
  while building `vgraph`'s thread-safe counter.

## [1.5.0] - 2026-10-25

### Added

- **`@[vc_opaque]`, for a function that takes or returns a native pointer.** A `voidptr`
  result reads as `pyobj` - a borrowed `PyObject *` - so returning a C pointer through one is a
  pointer CPython treats as an object, and it crashes the interpreter. The annotation makes the
  wrapper build a capsule instead, and `@[vc_opaque: 'free_fn']` names the destructor that runs
  when Python collects the handle. A `voidptr` *parameter* is unwrapped with `handle_data` the
  same way, so the function never has to call it itself; that is the symmetry the result side
  already had. A `voidptr` parameter is unchanged: unwrapping one is the callee's contract,
  and `handle_data` at the point of use says which parameter is a handle.
- **`to_py_str_list` and `to_py_bytes_list`.** The generated glue boxed a `[]string` or
  `[][]u8` result with `to_py_list` and a boxing function, which worked and cost a V
  function call and the closure's indirection for every element. The integer and float
  helpers already did the boxing in C (`vpy_list_from_i64`, `vpy_list_from_f64`); these two
  did not, and they are the ones a high-throughput extension boxes per request - headers,
  paths, chunks. `vpy_list_from_str` reads the V string's layout (24 bytes, `len` is
  `i64`) and `vpy_list_from_bytes` reads the V slice's layout (40 bytes).
- **`@[vc_handle]` and `vcraft.Owned`, for native state a class owns.** A field holds the
  pointer together with the function that releases it, and the generated `tp_dealloc` calls
  it, so the allocation's lifetime is the instance's. A `voidptr` field could not do this:
  the state block lives in CPython-allocated memory that V's collector does not scan, so
  nothing would ever free what it points at, and the object would be left holding a dangling
  address. The alternative was a capsule - a Python object per handle - and this is for the
  state that never has to be visible to Python at all. `release` is idempotent, which
  `tp_dealloc` needs because it also runs on instances whose constructor raised.
- **`vcraft.released`, the RAII form of `allow_threads`/`end_allow_threads`.** A function that
  is not `@[vc_nogil]` holds the GIL for its whole call, so a long V-only stretch blocks
  every other Python thread. `released` runs a block with the GIL released and gives it
  back in a `defer` that protects against a panic, which is what a hand-written pair does
  not do: an unbalanced pair leaves the GIL count wrong and crashes the next thread switch
  inside CPython. The manual pair stays for the cases the block form cannot cover - a
  `poll` with a 1 s timeout, or a choice between several conditions.
- **`vcraft.run_coroutine` and `vcraft.call_async`.** An extension that calls a Python
  `async def` had to drive the coroutine itself, which is where the fast path lives: a single
  `send(None)` finishes the common case in ~1.8 us instead of the 9.5 us that
  `loop.run_until_complete` costs. The fast path and the private `asyncio._set_running_loop`
  dance that makes `get_running_loop()` work during it now live in vcraft, so an extension
  depends on the private name zero times instead of once. `call_async` is the composition:
  call the callable and drive the coroutine it returns.
- **`vcraft.with_gil`, `gil_ensure` and `gil_release`.** A thread V created with `spawn`
  holds no Python thread state, so calling into Python from it was impossible: only the
  release half (`allow_threads`) was exposed. `with_gil` acquires the GIL for a block and
  gives it back on every path, panic included, which is what a hand-written pair does not
  do. Found by an ASGI server written for the proof of concept, where the alternative was
  to have Python create every thread.
- **`vcraft.bytes_view` and `buffer_view_of`.** `bytes_arg` borrowed a `[]u8` *argument*
  through the buffer protocol, but a bytes-like object Python *returned* from a call could
  only be read by copying it twice (`from_py_bytes` into a `string`, `.bytes()` into a
  `[]u8`). `bytes_view` asserts the same borrow for a result; a server writing a large body
  straight to a socket measured 1 MB responses at 1459 req/s before and ~3400 after.

- **`from_py_int_item`, `from_py_str_item` and `from_py_bytes_item`.** The argument readers
  (`from_py_*_arg`) take a trampoline's `argv` pointer and an index; these take a tuple
  or list that is already in hand, which is what a function that receives a sequence from
  Python uses. They are borrowed, so they do not release the source, and they raise
  `IndexError` when the index is out of range.
- **`examples/async_callback`.** A minimal extension that calls a Python `async def` with
  `vcraft.call_async` and drives it to completion, including the fast path, the slow path
  and the exception-propagation case.

### Fixed

- **A failed build no longer buries its error under a notice per wrapper.** The glue bound
  its arguments with `mut args := raw_args`, which V reports as a notice, and declared the
  parameters a wrapper does not read under names V then reported as well: `self` on a module
  function or a static method, `closure` on a property or a field accessor, `view` on
  `bf_releasebuffer`. In a project with ten exported functions a compile that failed for one
  real reason printed a dozen lines about vcraft's own habits first. The binding is `unsafe`
  now and the unread parameters are named with a leading underscore, so the glue compiles
  without a single notice whether or not the build succeeds.
- `buffer_resize_backing` named a local `copy`, which shadows a builtin function and made V
  say so on every compile.
- The README says what a `voidptr` result actually is. It reads as `pyobj` - the borrowed
  `PyObject *` of a fixed signature - so returning a C pointer through one is not an opaque
  handle but a pointer CPython will treat as an object and follow into a segfault. The
  mistake is easy to make and the symptom points nowhere near the return statement.

## [1.4.5] - 2026-10-18

### Fixed

- **The wheel's launcher propagates the binary's exit code.** `_launch.py` used
  `os.execv`, and on Windows the exec family does not replace the process the way it
  does on POSIX, so the child's exit code was lost: `vcraft build` that printed
  `error: no V compiler found` still exited 0, and CI saw a green step with an empty
  `dist/`. It now runs the binary with `subprocess.run` and exits with its status, which
  is also what makes a failing `vcraft toolchain install` stop looking like success.
- **V discovery is resolved to an absolute path.** `v_compiler()` now resolves the bare
  name on `PATH` (`v.exe` on Windows) instead of returning it for the caller to exec,
  and `command_exists` also tries the `.exe` spelling there.

The tool wheel suite now builds through the installed wheel with `VCRAFT_V`/`VCRAFT_HOME`
removed (the action's environment, where V has to be found on `PATH`), and checks that
the launcher returns the binary's non-zero status.

## [1.4.4] - 2026-10-16

### Fixed

- **The macOS wheel is self-contained.** The `vcraft` binary linked Boehm's
  `libgc.dylib` dynamically and V baked the *build machine's* path as an rpath
  (`/private/tmp/v-src/thirdparty/tcc/lib`), which only existed on the machine that
  built the wheel: installing it elsewhere failed with
  `dyld: Library not loaded: @rpath/libgc.dylib`. The wheel now carries `libgc.dylib`
  next to the binary, the dependency is rewritten to `@loader_path/libgc.dylib`, the
  build-machine rpath is dropped and the binary is re-signed, so it runs wherever it is
  installed. Linux and Windows were unaffected.

### Changed

- **The tool wheel suite now builds a project through the installed wheel.** `pip
  install vcraft`, then the console script scaffolds and builds an abi3 project -- the
  path the published action takes. The cli suite runs `bin/vcraft` directly, so it never
  covered the wheel's launcher, which is where a Windows-only failure hides.

## [1.4.3] - 2026-10-16

### Added

- **`[build] cflags` and `[build] ldflags`.** Extra compiler and linker flags can now be
  persisted in `vcraft.toml`, passed to V as `-cflags`/`-ldflags` after vcraft's own. This
  is how a project opts into something like `-march=x86-64-v2` once instead of passing
  `--cflags` on every build; a CLI `--cflags`/`--ldflags` adds to the manifest's flags
  rather than replacing them, and `vcraft info` reports both. A wheel built with `-march`
  inherits that CPU requirement, so it belongs in a private build or a deliberate platform
  baseline, not in a wheel meant to run on any x86-64.

## [1.4.2] - 2026-10-16

### Fixed

- **A method's signature is resolved by its receiver, not by its name.** Two structs that
  declare a method with the same name made the exported one take the *first* declaration's
  parameters, so its trampoline and `.pyi` used the wrong signature: the build failed with
  `cannot use int as Color` when the types differed, or bound the wrong argument types when
  they did not. A free function and a method sharing a name are kept apart too.
- **A field is looked up inside its own struct.** Two structs with a field of the same name
  made the second read the first one's source line, so its `@[vc_field]` was not seen and
  the field silently disappeared from the instance and the stub.
- **Enum members in the `.pyi` are typed as the enum** (`red: Color`, not `red: int`), so
  `Color.red` satisfies a `Color` parameter for a type checker such as ty or mypy.

## [1.4.1] - 2026-10-16

### Fixed

- **`--strip` (and `[build] strip`) actually strips.** The flag was parsed and written to
  the manifest but never acted on, so the extension kept its symbol table. It is applied as
  a linker flag (`-Wl,-s`, or `-Wl,-x` on macOS) when the extension is linked, so it shows
  up in `--dry-run` and needs no `strip` binary on `PATH`. The dynamic symbol table is
  kept, so `PyInit_` is still exported.
- **`vcraft sdist` no longer drops source files.** It carried only `src/<module>.v`, so a
  project that splits its V code across files (`linalg.v`, `state.v`, ...) rebuilt from its
  sdist into a module missing most of its API — silently, because the generator only sees
  the files it is given. The sdist now carries every `.v` under `src/`, except the
  generated glue.
- **An enum or plain struct declared in a file that sorts after its use now resolves.** The
  types were registered as their file was read while the signature that named them was
  validated in the same pass, so file order decided whether the project built; the registry
  is now filled before any signature is validated.
- **Enums are declared in the `.pyi`.** They were attached to the module at runtime but a
  type checker could not see them; each enum is now a generated `enum.IntEnum` subclass in
  the stub.
- **`vcraft <command> --help` prints help and does not run the command.** `--help` was
  parsed as an ordinary flag the command ignored, so `vcraft build --help` ran a build.
- The README's Requirements section lists Windows.

## [1.4.0] - 2026-10-16

### Added

- **Numeric operators.** `@[vc_add]`, `@[vc_sub]`, `@[vc_mul]`, `@[vc_truediv]`,
  `@[vc_floordiv]`, `@[vc_mod]`, `@[vc_pow]`, `@[vc_lshift]`, `@[vc_rshift]`, `@[vc_and]`,
  `@[vc_or]` and `@[vc_xor]` fill CPython's number slots so a class can define `+`, `-`,
  `*`, `/`, `//`, `%`, `**`, `<<`, `>>`, `&`, `|` and `^`; `@[vc_neg]`, `@[vc_pos]`,
  `@[vc_abs]` and `@[vc_invert]` are the unary ones. Each is a free function
  `(self &T, operand) -> result`, where the operand is a scalar or another `&T` and the
  result is a number or a new `T` that vcraft allocates and fills. A scalar on the left
  (`2 + counter`) reaches the reflected `@[vc_radd]`-style function, or the forward one for
  a commutative operator; an operand the function does not accept returns `NotImplemented`.
- **Maps with non-string keys.** `map[K]T` marshals to a `dict` when `K` is a scalar or a
  string (`bool`, an integer, a float or `str`), not only `str`, both as a parameter and
  as a result.
- **Enums.** A V `enum` the project declares crosses as a generated `enum.IntEnum` of the
  same name, attached to the module, so `Color.red` is the V `Color.red` and a value reads
  back as the member rather than as a bare int. An integer that is not a member is refused
  on the way in with `ValueError`. Member values are read from the source, so an explicit
  `= n` is honoured; a value that is not an integer literal is a diagnostic.
- **Plain structs.** A V `struct` the project does not annotate `@[vc_class]` crosses as
  a Python `dict` of its fields, both ways: a field is boxed by its own rule and read back
  by name, so a missing key is a `KeyError` and a wrong field type a `TypeError`. A field
  with no marshalling rule, at any depth, is a diagnostic at the signature.
- **Nested composites, both ways.** A composite nests: `?[]int`, `[][]int` and
  `map[string][]int` cross as nested `list`, `dict` and `None`, as a parameter and as a
  result. A parameter reads through generated generic converters (V gives a generic called
  across modules no forward declaration), so a wrong element type raises `TypeError`
  naming the parameter.
- **Windows (`win_amd64`).** `vcraft build` links the `.pyd` against the interpreter's own
  import library and folds the MinGW runtime in with `-static`, so the wheel imports on a
  machine that has no compiler on `PATH`; the CLI, `vcraft toolchain install` (through
  `makev.bat`), `vcraft generate-ci` and the action run on `windows-latest`, and the suites
  that were POSIX-only — packaging, wheel, docs and the CLI — run there as well. An abi3
  extension is named `.pyd` on Windows, the only suffix the loader will import there.
  `release-v` publishes a prebuilt Windows V and `release-vcraft` a `win_amd64` wheel.
- **Documentation site.** A guide and a reference in English and Spanish, built with MkDocs
  Material and published to GitHub Pages, covering everything needed to use vcraft. The
  README stays the source of truth and keeps every V example tested.

## [1.3.0] - 2026-10-15

### Added

- **Instance references: a `&T` parameter or result passes the instance itself.** A
  parameter typed `&T`, where `T` is a `@[vc_class]`, accepts an instance of `T` or of a
  subclass and hands the V function a pointer into that instance's live state, so it reads
  and writes the same bytes a method would; passing anything else raises `TypeError`. A
  `&T` result is handed back to Python as the instance the pointer belongs to, matched by
  address against the receiver and the `&T` arguments of the call, and a pointer into
  anything else raises `RuntimeError` rather than guessing. A plain function returning `&T`
  therefore needs a `&T` parameter to resolve against, which is a diagnostic; the stub and
  `__text_signature__` name the class, and a constructor may take instance references too.
  The offset is the immediate base's state size, computed from the layout the generator
  emitted rather than read from the type object.
- **Class protocols: `len()`, `obj[i]`, `in`, ordering and classmethods.** `@[vc_len]`,
  `@[vc_getitem]` and `@[vc_contains]` fill CPython's `sq_length`, `sq_item` and
  `sq_contains`, so `len(instance)` and `bool(instance)`, `instance[i]` and
  `x in instance` reach ordinary methods; unlike the `@[vc_iter]`/`@[vc_next]` pair the
  three are independent and a class may define any subset. `@[vc_lt]`, `@[vc_le]`,
  `@[vc_gt]` and `@[vc_ge]` join `@[vc_eq]` in `tp_richcompare`, so `<`, `sorted()` and
  `heapq` work, and an operator a class does not define still returns `NotImplemented`.
  `@[vc_classmethod]` registers a `fn Class.name` with `METH_CLASS`, so CPython passes the
  class and a subclass calling it sees itself. Each is validated at generation time: a
  `__len__` with arguments, a non-integer index, a `__contains__` that is not a bool, and
  a second operator of the same kind are diagnostics.
- **Module-level constants.** `@[vc_const]` on a `pub const` whose value is an int, a
  float, a bool or a string literal exposes it as a module attribute of the same name,
  declared in the `.pyi` too. The value is read at generation time, so anything else is a
  diagnostic rather than glue that does not compile.
- **Callbacks: calling Python from V.** `vcraft.call(callee, args)` runs a Python callable
  with borrowed positional arguments and returns a new reference, `vcraft.call_owned`
  releases arguments built for the call, and `vcraft.getattr` / `vcraft.call_method` reach
  an object's methods. The callee is a `voidptr` (a `@[vc_raw]` parameter, or a `PyObj`
  field). Re-entry is safe: the per-thread state chain is restored around each trampoline,
  and a Python exception from the callback is a pending exception the trampoline returns
  null for.
- **`@[vc_memoryview]` returns a slice as a writable `memoryview`.** A `@[vc_fn]` or
  `@[vc_method]` that returns a slice of buffer scalars (`bool`, an integer or a float)
  now hands it to Python as a `memoryview` over the same memory instead of a list of boxed
  elements. The function must return a native-backed slice -- built by `buffer_new_*` or
  `buffer_resize_*` -- because the view takes ownership and frees the backing through the
  same allocator when Python collects it; an ordinary V array would be freed by the wrong
  allocator. The element type sets the view's `format` and `itemsize`, the view is
  writable, and the `.pyi` stub and `__text_signature__` say `memoryview`.
- **A base constructor may take arguments, and a subclass forwards them.** A `new_<class>`
  on a base used to be limited to no parameters, because `newstate` built the base's half
  with no arguments and a subclass had nowhere to get them. A subclass's `tp_new` now
  binds the base's parameters too, and `newstate` forwards the leading ones to the base's
  constructor and hands the rest to the subclass's own: `Mid(10, 3)` builds `Root` with
  10 and `Mid` with 3, and a subclass with no constructor of its own still accepts its
  base's parameters. A parameter name shared by the base and the subclass is reported,
  since both travel in the one Python signature the subclass binds.
- **A field annotation on the line above the field is reported.** A field annotation
  belongs on the field's own line (`@[vc_field] value int`). V also accepts an attribute
  on the line above, where `@[vc_field]`, `@[vc_ref]` and `@[vc_buffer]` are silently
  dropped and the field is left unexposed; the generator now warns and names the field,
  and still builds.
- **`@[vc_buffer_typed]` exposes a native buffer as a typed `memoryview`.** Written beside
  `@[vc_buffer]` (in one block: `@[vc_buffer; vc_buffer_typed]`), it changes what
  `memoryview(instance)` reports from the default 1-D byte view (`format "B"`, `itemsize`
  1) to a typed one: format and itemsize from the element type, one item per element. A
  `[]f64` reports `format "d"` and `itemsize 8` with a length in elements, so
  `list(memoryview(x))` and `struct.unpack` read the values directly. The annotations are
  opt-in and the default is unchanged.

### Changed

- **The instance state lives inside the object.** `tp_basicsize` is now the PyObject
  header plus the class's state struct, laid out inside the object, instead of a header
  plus a pointer to a separate `PyObject_Malloc` block. A fresh instance pays one
  allocation instead of two, a method reaches the state without following a pointer, and
  a live instance is smaller by the second block's allocator overhead. On the benchmark,
  `Counter()` drops ~106 → ~100 ns and `Vector(1000)` ~306 → ~290; a controlled
  before/after finds construction ~13% faster and method and attribute access ~5–8%
  (`c.value`, `c.increment`, `c.set_step`, a subclass property). `PyType_GenericAlloc`
  zeroes the state, so an instance a Python subclass produced without running a vcraft
  constructor still reads as the V zero value, and the per-trampoline "no state" branch
  is gone. The 16-byte GIL header and the 32-byte free-threaded one are both handled,
  since the offset comes from the interpreter.
- **The state is one contiguous region, not a block behind a pointer.** `storage_of`
  names it, `instance_storage` returns it, and `class_dealloc` no longer frees it
  separately: `tp_free` releases the whole object. `instance_alloc`, `instance_free` and
  `instance_set_storage` are gone, along with the shim they wrapped.
- **A wrapper no longer allocates to report an exception.** `set_error` raised with
  `PyErr_SetString`, which needs a NUL-terminated C string, so every error copied the V
  string into a fresh buffer first: one malloc, one copy, one free, and a `strlen` inside
  CPython, on every failure. The message now goes across as a pointer and its length
  (`PyUnicode_FromStringAndSize` + `PyErr_SetObject`, a new `vpy_set_error_utf8` shim), and
  the copy and the free are gone.
- **A construction allocates nothing for its parameter names or slots.** `tp_new` built
  the parameter-name and optional arrays as literals -- `new_array_from_c_array` on every
  `Class(...)` -- and put the argument slots in a heap slice. The names are now a
  module-level global (as they already were for a function), and the slots are a fixed
  array on the stack (`unsafe { [N]voidptr{} }`, which V lowers to `void* bound[N]`), so a
  positional construction allocates neither. Together with the removal of the extra copy in
  a base-less `newstate`, `Vector(1000)` falls from 1.23× PyO3 to 1.17× and `Vector(1)`
  from 1.47× to ~1.10× on the benchmark.
- **`tp_iternext` checks for a pending exception once, not twice.** The `!T` branch and the
  shared tail each emitted an `error_is_set` after the call, so every item of an iterator
  paid two `PyErr_Occurred`. `list(Countdown())` falls from ~1.27× PyO3 to ~1.19×.

### Fixed

- **A class whose constructor failed leaked the object.** `tp_new` allocates the object
  with `tp_alloc` and owns it until it returns it; when the user's constructor raised --
  a Python exception set through `raise`, or a panic -- vcraft returned nil without
  releasing it, leaking the object on every failed construction. It now decrefs the
  half-built instance, which runs the generated `tp_dealloc` and frees whatever the
  constructor had already stored, and does the same when a panic unwinds through
  `tp_new`. The state is zeroed before the constructor runs, so the dealloc is safe on
  the panic path. Covered by a new memory scenario that builds and drops a failing
  constructor 50,000 times without growth.

## [1.2.0] - 2026-10-14

### Added

- **Persistent native buffers in `@[vc_class]`.** A field annotated `@[vc_buffer]` holds a
  `[]T` of scalars whose backing lives for the object's lifetime, is not copied per call,
  and is freed exactly once at dealloc. State that used to be rebuilt or batched per call
  can now live in V: a stabilizer tableau, a state vector, a scratch workspace. The
  `vcraft.buffer_new_*` helpers allocate the backing, `memoryview(instance)` exposes the
  first buffer of a class with no copy, `vcraft.buffer_resize_*` grows or shrinks it, and a
  resize is refused with `BufferError` while a memoryview is open. A class holding both a
  buffer and a `@[vc_ref]` is collectable and frees both.
- **Constructors that take arguments.** `new_<class>` may declare parameters; `tp_new`
  binds Python's positional and keyword arguments with the same marshalling rules a method
  uses, so `Vector(4)` calls `new_vector(4)` and the signature reaches the `.pyi` stub as
  `__init__`. A subclass runs its base's constructor with no arguments, so an
  argument-taking constructor is allowed only on a class whose base chain is argument-free;
  the generator reports the other case.
- **Capsules.** `vcraft.new_handle(value, destructor)` wraps an arbitrary native pointer in
  a `PyCapsule` and `vcraft.handle_data(capsule)` recovers it, as the escape hatch next to
  `@[vc_raw]` for state that is not a plain slice.
- **`@[vc_static]` and `@[vc_raw]` methods.** A static method is written
  `fn Class.name(...)` with no receiver and becomes a Python `staticmethod`; `@[vc_raw]` is
  now allowed on a method, where the arguments arrive as borrowed `PyObject`s and the
  receiver still works on the instance's state.
- **Complex numbers.** `math.complex.Complex` (or `complex.Complex`) marshals to and from a
  Python `complex`, and a real is accepted where a complex is expected.
- **Authors and maintainers.** `[package] authors` and `maintainers` in `vcraft.toml` reach
  `METADATA`, and a licence file at the project root travels in the wheel and the sdist.
- **Multi-line arrays in `vcraft.toml`.** A `classifiers` or `dependencies` list may span
  several lines instead of one very long one.
- **Element-typed sequence stubs.** Generated stubs type `[]int` as `Sequence[int]` rather
  than `Sequence[Any]`.
- **`ty` configuration** in the scaffold, beside the pyright and mypy hints.

### Changed

- **The state chain no longer allocates per call.** A module that publishes the chain —
  any class with a base whose methods reach it through `vcraft.state_at` — allocated a
  snapshot of it with `PyMem_Malloc` on every trampoline and freed it after. It is now a
  per-thread stack of frames in native thread-local storage, and the accessors are
  inlined, so leaving is a decrement.
- **The chain is published only where it can be observed.** `state_at(level>=1)` reaches
  an ancestor, so only a subclass's trampolines need to publish; a class with no base
  now publishes nothing unless the project uses `state_at(0)`. This takes the chain off
  every method of a base-less class.
- **Arguments are bound without a per-call allocation.** A call with keywords or a left
  out parameter built its name and optional arrays, and a left out parameter also built a
  slot array, on every call. The arrays are module globals, and a positional-only call
  keeps the raw argument array and checks each parameter's presence, so it builds no
  slot array either.
- **Complex numbers are recognised by type, not by name.** `vpy_is_complex` compared the
  type's name on every conversion; a full build now uses `PyComplex_Check`.

  On the benchmark `Counter` and friends: `c.add` 79 → 72 ns, `c.value` 53 → 34,
  `c.increment` 65 → 50, `describe(3)` 261 → 125, `complex_scale` 149 → 96. The
  per-thread state stack is also halved, to 16 frames.

### Fixed

- **`pyproject.toml` is merged, not overwritten.** `vcraft build` and `vcraft develop`
  used to replace the whole file with vcraft's template, silently deleting a project's own
  `[project]`, `[dependency-groups]` (PEP 735, so `uv sync --group dev` works) and
  `[tool.*]` tables. A build now rewrites only vcraft's `[build-system]` table and leaves
  every other table, comment and ordering in place; a file that does not exist yet is
  created from the full template.
- **`!void` functions and methods.** A result type of `!` (may fail, returns no value) was
  read as `voidptr`, and the wrapper tried to box a value the function never produced,
  which failed to compile. It is now treated as `void`.
- **Constructor name matching** now accepts the snake-cased spelling of a multi-word class,
  so `TallyBuffer` is built by `new_tally_buffer` as well as `new_tallybuffer`.
- **`PyExc.buffer_error`** added, so a buffer-protocol failure can name `BufferError`.
- **`vcraft develop` builds against the active virtualenv's interpreter.** It installed
  into the virtualenv but compiled with whatever `python3` was first on `PATH`, so the
  extension could be built for one CPython and installed into another.
- **Interpreter probes read past stderr.** The version and platform queries captured
  stdout and stderr together, so a stray warning became the answer and a working
  interpreter was reported as unsupported.
- **The editable pointer is silent and `vcraft clean` removes it.** A `.pth` naming a
  removed build directory no longer warns on every interpreter start, and cleaning drops
  the pointer and its `.dist-info` from the active environment.
- **`vcraft toolchain` reports the compiler it actually resolved** and a build warns when
  it is not the pinned commit, instead of printing a toolchain directory that may not
  exist.

## [1.1.1] - 2026-10-13

### Fixed

- **`vcraft new` normalises the name into a valid module.** A hyphen or an uppercase
  letter — both ordinary in a PyPI name — produced `module my-extension_native` or
  `module MyExt_native`, which V rejects, so the project did not compile. The derived
  module is now lowercased with `-` and `.` turned into `_`, the test file follows it,
  and a name that is not an identifier (a leading digit, a bad `--module`) is refused
  before anything is written.
- **`vcraft new` points type checkers at `python/`.** The generated `pyproject.toml`
  carries `[tool.pyright] extraPaths = ["python"]` and `[tool.mypy] mypy_path =
  "python"`, so `import <name>` is not reported missing by Pylance before the package
  is installed; after `vcraft develop`, the extension's `.pyi` stub sits beside the
  package and the re-export resolves too.
- **`vcraft develop` without an active virtualenv fails before the build**, with the
  command to create and activate one, instead of building first and then reporting "no
  interpreter at python3".

## [1.1.0] - 2026-10-13

### Added

- **A new project ships a runnable demo and a test.** `vcraft new` now writes `main.py`,
  which imports the extension and calls into it, and `tests/test_<name>.py` with
  `unittest` cases, so `python main.py` and `python -m unittest` work right after
  `vcraft develop`. Both travel in the sdist; neither is packaged into the wheel, so the
  demo is for the development loop rather than part of the distribution.
- **A new project is importable under its own name.** `vcraft new` writes a Python
  package `python/<name>/` that re-exports the native module, with a `py.typed` marker,
  so `import <name>` is the public name and a type checker sees the API. The native
  module `<name>_native` stays importable as an implementation detail. Hand-written
  Python under a project's `python/` directory was already packaged; the `py.typed`
  marker now travels with it.

### Fixed

- **The generated type stub ships in the wheel.** It was written to
  `python/<module>/_stubs.pyi`, which is not where a type checker looks for a
  top-level extension module, and the wheel packer dropped every `.pyi`, so an
  installed wheel offered no type information. The stub is now `python/<module>.pyi`
  and travels in the wheel next to the extension.
- **The list-conversion error path no longer leaks.** `type_name()` read a type's
  `__name__` with `PyObject_GetAttrString`, which builds a temporary Python str for the
  attribute key on every call, so a hot failure path that named the offending type — a
  list element that is not a float — lost about 48 bytes per call. It now reads the name
  with `PyType_GetName` and `PyUnicode_AsUTF8AndSize` through the C shim, allocating
  nothing. `sum_floats(['x'])` called 200,000 times went from a 9.2 MiB leak to 0,
  measured by the benchmark's error-path memory scenario.

### Changed

- **`vcraft new` prints the importable module and the first commands.** It names the
  extension module (which differs from the distribution name), shows the virtualenv
  step, and points at `python main.py` and `python -m unittest`. The README's quick
  start, "How it works" diagram and generated-layout section now match the files that
  are actually written.
- **The benchmark probes edge cases, reference retention and error paths.** The
  correctness matrix now covers integer limits and overflow, an embedded NUL and a
  non-BMP code point in a `str`, empty and negative sizes, wrong-typed arguments and
  every buffer-like object; a `sys.getrefcount` probe checks that no borrowed argument
  is retained; and the memory scenarios include calls that raise on every iteration. A
  case that aborts its process is re-run on its own instead of losing the run. The new
  probes found a leak in vcraft's list-conversion error path (~48 bytes per call) and
  three zig-maturin deviations (embedded-NUL truncation, a `str` read as bytes, and
  `OverflowError` reported as `TypeError`).
- **The benchmark covers keyword arguments and defaults.** A `describe` workload with
  two defaults and an optional parameter is exercised positionally, by keyword, mixed,
  and with missing, unknown and surplus arguments. It surfaced a zig-maturin bug: an
  unknown keyword is silently ignored instead of raising `TypeError`.
- **The benchmark covers optional values, maps, tuples and fixed-size arrays.** New
  workloads exercise `?T` in and out (`maybe_double`), a `dict` result built from a
  `list[str]` (`histogram`), a multi-value tuple result (`minmax`) and a `[N]T` in and
  out (`reverse3`), with the empty, wrong-type and wrong-length cases alongside. A
  plain dict expected value and a per-backend expectation table are now distinct
  (`PerBackend`), so `histogram` can be checked against a dict.
- **The benchmark covers the class surface.** Counter grows a read-only property, value
  equality and a hash; a `Countdown` class is its own iterator, with the exhaustion path
  checked against `StopIteration`; and a `BoundedCounter` exercises single inheritance,
  including an inherited field, an inherited method, `isinstance` both ways and the
  refusal path. All four backends pass.
- **The benchmark measures thread scaling.** An `lcg` workload — a serial integer loop
  with no vectorisation and no allocation — runs from 1 to 8 threads on each backend.
  It releases the GIL through PyO3's `detach`, Zig's `allowThreads` and vcraft's
  `@[vc_nogil]`, and the table reports the parallel speedup. All three scale on this
  12-core machine (vcraft 6.5×, zig-maturin 7.6×, PyO3 5.4× at eight threads), so
  thread registration and GIL release hold; the pure-Python reference, which cannot
  release the GIL, is not measured.
- **Python 3.15 support.** CPython 3.15.0 joined `supported_pythons`, the CI matrix, the
  wheel classifiers and the matrix `vcraft generate-ci` writes; the free-threaded list
  adds 3.15t. The GIL build needed no runtime changes — the slot ids, the layout check
  and the conversions already match 3.15's headers. The free-threaded build did: 3.15's
  `PyModuleDef_Init` rejects a definition whose head does not carry
  `_Py_STATICALLY_ALLOCATED_FLAG`, which only `PyModuleDef_HEAD_INIT` sets, so the
  module definition's head is now copied from a static one before its fields are filled
  in. The full suite passes on 3.15, and a free-threaded 3.15t wheel imports with the
  GIL disabled.
- **Small cleanups.** A local variable shadowing the module `version` constant was
  renamed, removing a V compiler warning. The benchmark's Performance note no longer
  counts "thirteen" workloads, its stale "Threads: what this benchmark did not measure"
  section now points at the thread-scaling table, and the roadmap's threaded-workloads
  item is checked off.
- **No deprecated process APIs.** Every `os.execute`/`os.system` call was replaced with
  `os.exec`/`os.system_args` (an argument array, no shell), removing the 23 V compiler
  deprecation warnings. `command -v` now uses `os.find_abs_path_of_executable`, the
  interpreter probes pass their script as one argument instead of building a quoted
  shell string, and `vcraft publish` passes the files in `dist/` as arguments. The
  `--dry-run` plan still prints the compiler command shell-quoted, so it can be pasted.

## [1.0.0] - 2026-10-09

The first stable release: from here on the annotation vocabulary, the `vcraft.toml`
keys and the CLI change only with a deprecation period. Upgrading from 0.x is
described in [MIGRATING.md](MIGRATING.md).

### Renamed (the old names keep working throughout 1.x, with a warning)

- **`@[vc_gil]` is now `@[vc_nogil]`**: it releases the GIL, which the old name read
  as the opposite of.
- **`@[vc_methods]` is now `@[vc_method]`**: it goes on one method at a time.
- **Build settings moved into a `[build]` table** in `vcraft.toml` (`minimum-version`,
  `abi3`, `free-threading`, `strip`, `embed-pyc`, `gc-free-space-divisor`). As
  top-level keys they had to precede every table, and written after `[package]` they
  were silently ignored; the same keys found under `[package]` are now reported.
- **Classifiers are written `classifiers = [...]`** in `[package]`; `[[classifier]]`
  tables are still read.

The public surface and the deprecation policy are written down under *Stability* in
the README.

### Added

- **Keyword arguments and defaults.** Every parameter can be passed by name, in any
  order; a `?T` parameter may be left out and arrives as `none`; and
  `@[vc_defaults: 'step=1, label="item"']` gives other bool, integer, float and string
  parameters defaults. Errors match Python's (missing, repeated, unknown and surplus
  arguments), signatures and stubs show the defaults, and a fully positional call
  costs what it did before. The README used to say keywords were supported; now they
  are.
- **Optional, dict, tuple and fixed-array conversions.** `?T` of a scalar or string
  maps to `T | None` both ways; `map[string]T` to a `dict` with `str` keys; a
  multi-value result `(A, B)` to a `tuple`; and `[N]T` takes any sequence of exactly
  N items and returns a `list`. Stubs name the precise types (`int | None`,
  `dict[str, int]`, `tuple[int, str]`). Other composites stay a diagnostic.
- **`vcraft toolchain install`** builds the V compiler vcraft is tested with into
  `~/.cache/vcraft` (or `$VCRAFT_HOME`), and vcraft finds it there by itself;
  `vcraft toolchain` reports which compiler is used and whether it is the pinned
  commit. `vcraft build` without any V now says how to get one. Building V takes a
  few minutes and about 6 GB of memory at its peak. On musl (Alpine), where the last
  step of V's Makefile fails to link at the pinned commit after the compiler is
  built, a compiler that reports the pin is accepted with a warning; the musllinux
  image does the same.

### Fixed

- **Cross-compiling to x86_64 from an aarch64 machine produced a mislabelled wheel.**
  vcraft named a cross compiler for aarch64 targets but none for `linux-x86_64-gnu`, so
  from an aarch64 host the build used the host's own `cc`, compiled an aarch64
  extension and tagged it x86_64. It now uses `x86_64-linux-gnu-gcc`, and refuses to
  build when that is missing.
- **A misspelt annotation was silently ignored.** The check for unknown annotations
  looked for a `vc.` prefix, which none has, so `@[vc_fnn]` left its function out of
  the module without a word. It is now an error naming the annotation.
- **The compilers vcraft runs inherited its VEXE.** A binary V compiles sets
  VEXE to the compiler that built it, and V locates its own vlib and thirdparty
  through VEXE: a pip-installed vcraft pointed the user's V at the release build's
  compiler path, which does not exist on their machine. vcraft now clears it.
- **Calling an extension from any thread but the importing one crashed Python.**
  V's garbage collector only knew the thread that imported the module, so the first
  collection triggered from another thread aborted the process with
  `Collecting from unknown thread`. A single worker thread, a `ThreadPoolExecutor`,
  `asyncio.to_thread` or a threaded web server was enough. With the GIL released
  (`@[vc_gil]`) or on free-threaded CPython the collector also neither stopped those
  threads nor scanned their stacks. Every function in the generated glue now
  registers the calling thread with the collector on its first call (one
  thread-local check afterwards), and the thread is unregistered when it exits.
  **Rebuild your extensions** to pick this up.
- **Narrow scalar parameters did not compile.** A function or method taking `i8`,
  `i16`, `i32`, `u8`, `u16`, `u32` or `f32` was accepted by the generator, which then
  wrote glue the V compiler rejected. They now read through range-checked
  conversions: an out-of-range value raises OverflowError.
- **Narrow class fields were written with the wrong width.** Assigning to an `f32`
  field stored the low bytes of a double (`2.0` read back as `0.0`), and an `i8` or
  `u8` field silently truncated out-of-range values. They now convert to their own
  width and raise OverflowError when the value does not fit.
- **An allocation V refused surfaced as RuntimeError.** V reports it with a panic;
  the glue now raises MemoryError for it, like any failed allocation in CPython.
- **Extensions exported more than their init function on musl.** V's own
  `backtrace`, `backtrace_symbols` and `backtrace_symbols_fd` reached the dynamic
  symbol table, where another library in the process could bind to them. Linux builds
  now link with a version script that exports only `PyInit_<module>`, on glibc and
  musl alike.
- **The README promised conversions that did not exist.** `map[string]V`, `?T`,
  enums, fixed arrays, plain structs, V function types and `&T` in plain functions
  are rejected by the generator; the type table now says so, `rune` is documented
  as the `int` code point it is, and every row is exercised by the CLI suite.

### Changed

- **Actions run on Node 24**, which GitHub is moving every action to: checkout v5,
  setup-python v6, cache v5, upload-artifact v6, download-artifact v7,
  build-push-action v7, setup-buildx-action v4, login-action v4, action-gh-release v3,
  in this repository's workflows, the action and the workflow `vcraft generate-ci`
  writes. The action keys its V cache on the runner image, not just its OS.
- **`SECURITY.md`** says how to report a vulnerability and how to verify a download;
  **`MIGRATING.md`** walks a 0.x project to 1.0.
- **V pinned to `36be926`** (vc snapshot `6851aaf`), from `0137eb5`. Every suite
  passes with it; it also stops V picking tcc implicitly on macOS 27. CI, the release,
  the action, both images and `vcraft toolchain install` move together; the musl CI
  job keeps the 0.2.0 image, and its older V, until the images are re-released.
- **README examples are built in CI** (`tests/docs/test_readme.py`). The
  `raise_custom` example called a helper the README never defined; it is complete now.
- **Sanitizer runs in CI**: the runtime, codegen and fuzz suites also run against
  extensions built with AddressSanitizer and UndefinedBehaviorSanitizer
  (`scripts/run-sanitized.sh`).
- **Fuzzed conversions run in CI**: `tests/fuzz/test_fuzz.py` sends seeded hostile
  arguments through every reader and fails on a crash or an unexpected exception.
- **Leak checks run in CI**: a new suite, `tests/memory/test_leaks.py`, fails on
  leaked Python objects, unbounded memory growth or drifting reference counts.
- **macOS builds run on `macos-26`**: the vcraft release and the workflows
  `vcraft generate-ci` writes moved off `macos-14`, which GitHub has deprecated.
  Wheels still target macOS 11.0. Regenerate your workflow with
  `vcraft generate-ci`.
- **The benchmark has a Linux run** and documents the threading crash and its fix
  (`benchmark/README.md`).

## [0.2.0] - 2026-10-07

Faster string and bytes arguments, complete PyPI pages for vcraft and for the
projects it builds, and a fix that let new projects be published at all.

### Added

- **PyPI project pages for your packages**: `readme` in `[package]` (default
  `README.md`, which `vcraft new` writes) becomes the long description PyPI shows,
  typed from its extension so Markdown renders as Markdown. `keywords` and a `[urls]`
  table (`Source = "https://..."`) fill in the sidebar. Wheels and sdists carry all
  three.
- **`vcraft --version`** and `-V`, alongside `vcraft version`.
- **A real PyPI page for vcraft itself**: the README as description, licence,
  project links, keywords and classifiers. Repository links in the README point at
  the release on GitHub so they resolve from pypi.org.

### Changed

- **Borrowed `str` sequences**: a `[]string` argument aliases each item's UTF-8
  buffer instead of copying it, so a 10k-item list costs no per-item
  allocation. The slice must not outlive the call, the same documented contract
  as `[]u8`; safe against mutation because `str` is immutable. Scalar `str`
  parameters still copy.
- **Cheaper `bytes` arguments**: the exact-`bytes` branch of
  `bytes_arg` reads the buffer and length with one C call into locals instead
  of through `bytes_of`, whose 8-byte result struct V allocated per call. Small
  `bytes` calls match PyO3 call-for-call.
- **The scaffolded README reads as a project page**: installation and usage first,
  development instructions last, since it is now what PyPI shows.

### Fixed

- **New projects could not be uploaded to PyPI**: `vcraft new` declared the
  classifier `Programming Language :: V`, which PyPI does not know, and PyPI rejects
  an upload with any unknown classifier. New projects use
  `Programming Language :: Other` and `Implementation :: CPython`. Existing projects
  should replace the `Programming Language :: V` entry in their `vcraft.toml`.

### Upgrading

Replace `text = "Programming Language :: V"` in `vcraft.toml` with
`text = "Programming Language :: Other"`. Workflows written by
`vcraft generate-ci` name the 0.2.0 images: regenerate them with
`vcraft generate-ci` after upgrading.

## [0.1.0] - 2026-10-07

The first release. vcraft builds native CPython extensions from V source and
packages them as wheels, with no Rust, C++ or zlib involved.

### Supported platforms

- CPython 3.11, 3.12, 3.13 and 3.14, plus free-threaded 3.13t and 3.14t. CI tests
  every one of them on Linux x86_64 and macOS arm64.
- Linux wheels for manylinux and musllinux, x86_64 and aarch64, built in the
  published container images. macOS wheels are arm64 and target macOS 11.0 or
  newer.
- Windows is not supported. `vcraft build` and the action refuse it explicitly.
- Building needs a V compiler built from source at the commit pinned in `docker/`.
  The V 0.5.2 release is too old for the flags vcraft passes.

### Added

- **Runtime (`vlib/vcraft`)**: CPython bindings written in V, covering module
  construction, argument parsing for `METH_FASTCALL` and keyword arguments, type
  marshalling, and translation of errors and panics into Python exceptions.
- **Code generator**: turns `@[vc_fn]`, `@[vc_class]`, `@[vc_methods]`,
  `@[vc_field]`, `@[vc_property]` and the other annotations into CPython glue written
  in V. It also writes a `.pyi` stub with signatures and docstrings.
- **Classes**: instances, read/write fields, methods, properties, `__repr__`,
  `__eq__`, `__ne__` and `__hash__`.
  - Inheritance between V classes with `@[vc_base]`.
  - Cycle collection for reference fields with `@[vc_ref]`.
- **Errors**: `!T` results become Python exceptions. `raise_domain` raises a specific
  built-in exception, and `@[vc_error]` maps custom V error types to their own
  exception classes.
- **Zero-copy buffers**: `[]u8` parameters alias any object that supports the buffer
  protocol instead of copying it.
- **GIL and iterators**: `@[vc_gil]` releases the GIL around a call, and
  `@[vc_iter]`/`@[vc_next]` implement the iterator protocol.
- **Wheel writer**: writes DEFLATE, the ZIP container, `METADATA`, `WHEEL`, `RECORD`
  with SHA-256, compatibility tags and PEP 427 file names, all from scratch.
- **Source distributions**.
- **PEP 517 and PEP 660 build backend**: `pip install .`, `pip install <sdist>` and
  `pip install -e .` all work.
- **abi3 builds**: a single stable-ABI wheel covers every CPython from its floor
  upwards. The lowest floor is 3.11.
- **Free-threaded builds**: the build checks that the interpreter really is
  free-threaded, and the module declares itself GIL-free.
- **CLI**: `vcraft new`, `build`, `develop` (editable by default, or `--copy`),
  `sdist`, `publish`, `info`, `generate-ci`, `clean` and `version`.
- **Cross-compilation planning**: `--target` accepts canonical names and Rust-style
  triples. Also adds `--manylinux`/`--musllinux` policies, `--cc`, `--cflags` and
  `--ldflags`, and `--dry-run`.
- **`vcraft generate-ci`**: writes a GitHub Actions workflow with one cell per
  supported CPython from the project's `minimum-version` up. An abi3 project gets one
  cell per platform, and a free-threaded project gets 3.13t and 3.14t cells. Each
  cell installs and imports its wheel in the image or interpreter it was built for.
- **`vcraft-action`**: a composite GitHub Action that builds on the runner or inside
  an image. It caches the V compiler between runs.
- **Container images**: manylinux and musllinux images with V and vcraft
  preinstalled.
- **Returning lists and objects**: functions and methods can return `[]T`
  (boxed into a Python list), `vcraft.PyObj` (its reference is handed to the
  caller) and `voidptr` (borrowed, increfed for the caller).
- **`i64` throughout**: class fields, method parameters and sequence parameters
  accept `i64` as well as `int` (with this V compiler, `int` is already 64 bits).
- **Narrow sequence parameters**: `[]i8`, `[]i16`, `[]i32`, `[]isize`, `[]rune`,
  `[]u16`, `[]u32`, `[]usize`, `[]f32` and `[]bool` convert with the same
  TypeError/OverflowError behaviour as scalar parameters. A sequence element
  with no reader is a diagnostic with file, line and column instead of a
  compile error in the generated glue.
- **Collector tuning**: `gc-free-space-divisor` in `vcraft.toml` sets Boehm's heap
  growth divisor (default 2: roughly half a MiB less stays resident after large
  workloads than with V's own 1, for a few percent of allocation-heavy
  throughput; set 1 to favour speed).
- **Distribution of vcraft itself**: `pip install vcraft` installs the tool on
  Python 3.11 or newer, as a platform wheel for Linux x86_64 (`manylinux_2_28`)
  or macOS arm64 (macOS 11.0+).

### Changed

- **Methods work in place**: methods, accessors and slots operate on the
  instance's state block through a pointer, as PyO3 works through its cell,
  instead of copying the struct in and out per call. As in PyO3, a method that
  fails halfway keeps the fields it already wrote.
- **Cheaper calls**: each trampoline checks arity with a single comparison, reads
  an exact `int` argument with one type check in C, and keeps one `_setjmp`
  panic guard per call (about 5 ns) so a V panic becomes a Python exception
  instead of killing the interpreter.
- **One-pass conversions**: `[]int`, `[]i64` and `[]f64` arguments are filled in
  a single C pass, and returned lists of those element types are built in a
  single C pass with `PyList_SET_ITEM`.
- **No-view fast path for exact `bytes`**: a `[]u8` argument that is exactly
  `bytes` aliases the object directly instead of allocating, acquiring and
  releasing a buffer view. Anything else bytes-like still goes through the
  view, which pins the exporter for the call.
- **Smaller per-call state**: the `state_at` chain is only published when the
  project calls `vcraft.state_at`.
- **Faster imports on macOS**: vcraft starts Boehm before V with only the
  module's own `__DATA` registered as roots, instead of scanning every loaded
  image. Import falls from about 3.5 ms to about 0.6 ms and the memory kept
  after two million calls from about 14 MiB to about 1 MiB. Linux builds do the
  same with the module's own writable segments (not yet measured there). See
  `benchmark/README.md` for the full before/after tables.

### Fixed

- **Leaked list items**: `PyObj.item` on lists and tuples borrows instead of
  returning a new reference the caller treated as borrowed, so the items of a
  sequence passed on every call are freed again.
- **Leaked results**: a raw result takes its reference instead of handing Python
  a pointer nobody owned, which used to crash the interpreter on exit.
- **Method diagnostics**: an unsupported parameter or return type on a
  `@[vc_methods]` method is reported with file, line and column instead of
  failing later as a compile error in the generated glue.
- **Lost C-level conversion errors**: when a CPython conversion set an exception
  while reading an argument, the runtime consumed it for its own message and
  the call failed with `SystemError: ... returned NULL without an exception
  set`. The original exception (e.g. OverflowError for a negative `u64`) now
  reaches the caller.
- **`u64` results**: a function returning an unsigned width never compiled; the
  result local starts as `u64(0)`.
- **Dead `bytes_of`**: `from_py_bytes`'s helper called
  `PyBytes_AsStringAndSize` with two arguments instead of three, which never
  compiled wherever V kept it. It now passes the buffer and length out-pointers
  and reports failure with a null pointer.
- **Abandoned buffer backing**: `buffer_bytes` allocated a `[]u8` of the
  argument's length and then overwrote its `data` with the exporter's pointer,
  so every `[]u8` call left a GC block of the argument's size behind for the
  collector. The slice header is now built from an empty literal.
- **`--dry-run` hid flags**: a release dry run printed the compiler invocation
  before `-prod` and the project root were added to it, so the shown command
  was not the one a real build runs. The plan now renders the full command.
- **Linux builds failed to compile**: the collector pre-initialiser uses
  `struct dl_phdr_info`, which glibc only declares with `_GNU_SOURCE`.
  `vcraft build` now passes `-D_GNU_SOURCE` for Linux targets, and
  `vlib/vcraft/cpython.c.v` carries `#flag linux -D_GNU_SOURCE` so the example
  script and manual `v` builds get it too. A `#define` in the header itself
  comes too late, because the generated translation unit has already included
  system headers by then.

### Build safeguards

`vcraft build` refuses these combinations before compiling, instead of producing a
wheel that fails later:

- an interpreter older than CPython 3.11;
- an `abi3` floor below 3.11, or above the interpreter running the build;
- `abi3` combined with `free-threading`, because free-threaded CPython has no stable
  ABI;
- `free-threading` on CPython older than 3.13;
- a free-threaded tag on a GIL interpreter, or a GIL tag on a free-threaded one.

On macOS the build sets `MACOSX_DEPLOYMENT_TARGET` to the version in the wheel's
platform tag, so the binary loads on every macOS the tag claims. If you set the
variable yourself, the tag follows your value. A `universal2` interpreter tag
becomes the single architecture that was actually compiled.

[Unreleased]: https://github.com/rroblf01/vcraft/compare/vcraft/v1.0.0...HEAD
[1.0.0]: https://github.com/rroblf01/vcraft/compare/vcraft/v0.2.0...vcraft/v1.0.0
[0.2.0]: https://github.com/rroblf01/vcraft/compare/vcraft/v0.1.0...vcraft/v0.2.0
[0.1.0]: https://github.com/rroblf01/vcraft/releases/tag/vcraft/v0.1.0
