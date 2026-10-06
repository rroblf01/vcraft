const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zig-maturin passes these so the *target* Python's paths are used (it
    // knows them via sysconfig); fall back to python3-config on the host.
    const py_include = b.option([]const u8, "python-include", "Python include directory");
    const py_libdir = b.option([]const u8, "python-libdir", "Python library directory (Windows)");
    const py_lib = b.option([]const u8, "python-lib", "Python import library name (Windows)");

    // The include directory is forwarded to the dependency too. The scaffold does not
    // forward it, and the dependency then falls back to `python3-config`, which a uv
    // or venv interpreter does not provide, and its build panics.
    const zm_dep = if (py_include) |inc| b.dependency("zig-maturin", .{
        .target = target,
        .optimize = optimize,
        .@"python-include" = inc,
    }) else b.dependency("zig-maturin", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-maturin", .module = zm_dep.module("zig-maturin") },
            .{ .name = "pyo3zig", .module = zm_dep.module("pyo3zig") },
        },
    });

    const lib = b.addLibrary(.{
        .name = "bench_zig",
        .linkage = .dynamic,
        .root_module = mod,
    });

    // The high-level pyo3zig layer needs libc, the Python headers, and the
    // C shim that exposes Python's static symbols (PyExc_*, Py_None, ...).
    lib.root_module.link_libc = true;

    const include: std.Build.LazyPath = if (py_include) |p|
        .{ .cwd_relative = p }
    else
        getPythonInclude(b);
    lib.root_module.addIncludePath(include);
    lib.root_module.addCSourceFile(.{
        .file = zm_dep.path("pyo3zig_capi.c"),
        .flags = &.{},
    });

    // CPython symbols are resolved against the interpreter at import time, so
    // they must be left undefined at link time (mandatory on macOS Mach-O).
    lib.linker_allow_shlib_undefined = true;
    if (target.result.os.tag == .windows) {
        // PE cannot leave symbols undefined; link the Python import library.
        if (py_libdir) |d| lib.root_module.addLibraryPath(.{ .cwd_relative = d });
        if (py_lib) |l| lib.root_module.linkSystemLibrary(l, .{});
    }

    b.installArtifact(lib);
}

fn getPythonInclude(b: *std.Build) std.Build.LazyPath {
    var exit_code: u8 = 0;
    const result = b.runAllowFail(&.{ "python3-config", "--includes" }, &exit_code, .inherit) catch {
        @panic("python3-config not found or failed; is Python installed?");
    };
    const output = std.mem.trim(u8, result, " \n\r");
    var iter = std.mem.tokenizeScalar(u8, output, ' ');
    while (iter.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-I")) {
            const path = flag[2..];
            if (path.len > 0) {
                return .{ .cwd_relative = b.pathFromRoot(path) };
            }
        }
    }
    @panic("python3-config returned no -I flag");
}
