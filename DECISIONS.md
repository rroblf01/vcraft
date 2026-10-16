# Decisions

A log of decisions that are easy to revisit, each with the reasoning that led to it, so a
future reconsideration starts from the analysis rather than from scratch. `ROADMAP.md`
tracks what is planned; this file records what was set aside and why.

## Subinterpreters: deferred

Decided 2026-10-16. Not part of 1.4.0; to be raised again later.

### What "support" would require

A subinterpreter has its own modules, types and state. For a module to load in several:

1. **Multi-phase initialisation (PEP 489).** `PyInit_` returns a `PyModuleDef` with a
   `Py_mod_exec` slot, and every import builds its own module object. vcraft already does
   this for abi3 builds, not for the rest.
2. **Per-interpreter state.** A heap type from `PyType_FromSpec` is per-interpreter from
   CPython 3.12, and sharing a type object between interpreters is no longer allowed. The
   same goes for the thread-local key of the state chain, the shim's registries and any
   cached pointers.
3. **An explicit declaration.** The `Py_mod_multiple_interpreters` slot (3.12+), plus
   `Py_mod_gil` for free-threading, which vcraft already sets.
4. **No shared C state** that assumes a single interpreter.

The blocker is the state model: the runtime keeps the type objects (`g_vc_type_*`) and the
module in **process-wide V globals**, and V has no per-interpreter globals (they are C
`static`s). A second import overwrites them and the first interpreter's instances point at
a foreign type. Boehm is process-wide too and cannot be made per-interpreter.

### The options considered

1. **Real support.** Move the runtime's state into per-interpreter storage (module state
   instead of globals) and prove no V object escapes its interpreter. Honest capability,
   but a deep rewrite of the state model, a permanent invariant every future trampoline
   must keep, a per-call lookup on the hot path, and testing across the `_xxsubinterpreters`
   / `_interpreters` / `interpreters` API churn. Boehm itself stays shared.
2. **Declare and verify.** Move every build to multi-phase init and declare the real level
   (likely `NOT_SUPPORTED`) so an import in a subinterpreter fails with a clean
   `ImportError` instead of undefined behaviour. Cheap and strictly better than today, but
   it does not deliver the capability.
3. **Defer.** Spend the effort on the remaining 1.x work instead.

### Performance and safety, against writing V directly

Neither option speeds up a single call; option 1 even adds a per-interpreter lookup.

- **Performance** only changes for the *Python* side: with `Py_MOD_PER_INTERPRETER_GIL_SUPPORTED`
  and PEP 684, several subinterpreters in one process hold independent GILs, which is
  parallelism without processes. V run directly already has real threads and no GIL, so for
  raw compute V is faster; the subinterpreter only matters for parallel *Python* that keeps
  its objects. Free-threading (PEP 703, `Py_mod_gil NOT_USED`, already set) is the more
  relevant route for parallelism in one interpreter.
- **Safety** splits three ways. *Memory safety* — subinterpreters do not give it; a bad C
  access still kills the process, and only separate processes contain that. *State
  isolation* — option 1 gives it, and nothing in V code gives it within a process short of
  processes. *Failure containment* — option 2's only real gain, turning a crash into a clean
  error. V code is also safer for the compute itself (bounds checks, GC) than the C the
  boundary is written in.

The honest summary: for performance and safety *of the computation*, running V directly
(or in a subprocess) is better on both axes and avoids the boundary entirely. A
subinterpreter earns its keep only for many isolated Python tenants in one process, and
that is worth revisiting only if the per-interpreter state move proves tractable.

### Decision

Deferred. V run directly already covers the parallelism and isolation cases more strongly,
and the one thing subinterpreters add is not worth the state-model rewrite today.

## Documentation site: deferred

The long-form guide and reference stay in `README.md` for now; no site generator or Pages
workflow is added. If a site is built later, the plan is a `docs/` tree (guide + reference)
with `README.md` reduced to a quickstart, and `tests/docs/test_readme.py` extended to
compile the ` ```v ` blocks of every page so every claim stays backed by a test.
