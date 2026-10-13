const std = @import("std");
const pz = @import("pyo3zig");
const zm = @import("zig-maturin");

// A Zig panic becomes a Python exception instead of aborting the interpreter.
pub const panic = pz.panic;

// The same thirteen workloads as the PyO3 and vcraft projects, with the same
// semantics and 64-bit integers throughout.

// Call overhead: two ints in, one int out.
fn add(a: i64, b: i64) i64 {
    return a + b;
}

// Pure compute: naive recursion.
fn fib(n: i64) i64 {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

// Compute plus a native heap allocation of n + 1 bytes.
fn count_primes(n: i64) !i64 {
    if (n < 2) return 0;
    const size: usize = @intCast(n + 1);
    const composite = try std.heap.c_allocator.alloc(bool, size);
    defer std.heap.c_allocator.free(composite);
    @memset(composite, false);
    var count: i64 = 0;
    var i: usize = 2;
    while (i < size) : (i += 1) {
        if (!composite[i]) {
            count += 1;
            var j = i * i;
            while (j < size) : (j += i) composite[j] = true;
        }
    }
    return count;
}

// A Python list of floats converted into a native slice.
fn sum_floats(xs: []const f64) f64 {
    var total: f64 = 0;
    for (xs) |x| total += x;
    return total;
}

// A native sequence returned as a Python list of ints. Built as a PyList so the
// list owns its items and nothing is left allocated on the Zig side.
fn make_range(n: i64) !pz.PyList {
    const list = try pz.PyList.withSize(@intCast(n));
    var i: i64 = 0;
    while (i < n) : (i += 1) {
        // PyList_SetItem steals the new reference.
        _ = zm.PyList_SetItem(list.borrow(), @intCast(i), zm.PyLong_FromLongLong(i));
    }
    return list;
}

// A str in, a freshly allocated str out.
fn greet(name: []const u8) !pz.PyString {
    const text = try std.fmt.allocPrint(std.heap.c_allocator, "Hello, {s}!", .{name});
    defer std.heap.c_allocator.free(text);
    return pz.PyString.init(text);
}

// A count formatted with a defaulted step and label: keywords and defaults.
fn describe(count: i64, step: i64, label: []const u8, unit: ?[]const u8) !pz.PyString {
    const suffix = unit orelse "";
    const text = try std.fmt.allocPrint(std.heap.c_allocator, "{s}: {d}{s}", .{ label, count * step, suffix });
    defer std.heap.c_allocator.free(text);
    return pz.PyString.init(text);
}

// A value doubled, or null: an optional parameter and result.
fn maybe_double(x: ?i64) ?i64 {
    return if (x) |v| v * 2 else null;
}

// How often each word appears: a dict result. Built directly as a PyDict so no
// native map is left allocated after the call.
fn histogram(words: []const []const u8) !pz.PyDict {
    const dict = try pz.PyDict.new();
    for (words) |word| {
        const key = try std.heap.c_allocator.dupeZ(u8, word);
        defer std.heap.c_allocator.free(key);
        const current = zm.PyDict_GetItemString(dict.borrow(), key);
        const count: i64 = if (current) |v| zm.PyLong_AsLongLong(v) + 1 else 1;
        const value = zm.PyLong_FromLongLong(count);
        defer zm.Py_XDECREF(value);
        _ = zm.PyDict_SetItemString(dict.borrow(), key, value);
    }
    return dict;
}

// The smallest and largest value: a multi-value (tuple) result.
const MinMax = struct { i64, i64 };
fn minmax(xs: []const i64) !MinMax {
    if (xs.len == 0) {
        zm.PyErr_SetString(zm.PyExc_ValueError(), "minmax() arg is an empty sequence");
        return error.EmptySequence;
    }
    var lo: i64 = xs[0];
    var hi: i64 = xs[0];
    for (xs) |x| {
        if (x < lo) lo = x;
        if (x > hi) hi = x;
    }
    return .{ lo, hi };
}

// Three values reversed: a fixed-size array in and out.
fn reverse3(a: [3]i64) [3]i64 {
    return .{ a[2], a[1], a[0] };
}

// A list of str in, one new str out.
fn join_strings(parts: []const []const u8) !pz.PyString {
    const text = try std.mem.join(std.heap.c_allocator, ",", parts);
    defer std.heap.c_allocator.free(text);
    return pz.PyString.init(text);
}

// Bytes in, a fresh copy out.
fn echo_bytes(data: []const u8) !pz.PyBytes {
    return pz.PyBytes.init(data);
}

// Bytes in without copying, one int out.
fn checksum(data: []const u8) u64 {
    var total: u64 = 0;
    for (data) |b| total += b;
    return total;
}

// The error path: a bad value raises instead of returning. The exception is
// set here and the error value only signals failure; the wrapper keeps an
// already-set exception.
fn expect_positive(n: i64) !i64 {
    if (n < 0) {
        zm.PyErr_SetString(zm.PyExc_ValueError(), "expect_positive() expected n >= 0");
        return error.NegativeValue;
    }
    return n;
}

// Method-call overhead on a native object, with a property, value equality and a
// hash, and a subclass below.
const Counter = extern struct {
    value: i64,

    pub fn init() Counter {
        return .{ .value = 0 };
    }

    pub fn __eq__(a: *const Counter, b: *const Counter) bool {
        return a.value == b.value;
    }

    pub fn __hash__(self: *const Counter) isize {
        return @intCast(self.value);
    }
};

fn counter_increment(self: *Counter) i64 {
    self.value += 1;
    return self.value;
}

fn counter_add(self: *Counter, n: i64) i64 {
    self.value += n;
    return self.value;
}

fn counter_is_zero(self: *const Counter) bool {
    return self.value == 0;
}

const CounterClass = pz.PyClass(Counter, .{
    .methods = &[_]pz.PyMethodDef{
        pz.wrapMethodNamed(Counter, "increment", counter_increment),
        pz.wrapMethodNamed(Counter, "add", counter_add),
    },
    .properties = &.{
        .{ .name = "is_zero", .get = counter_is_zero },
    },
    .readonly = &.{"value"},
});

// Its own iterator: yields start, start-1, ... 1. A null return ends the iteration
// (CPython's StopIteration contract for the slot).
const Countdown = extern struct {
    current: i64,
    start: i64,

    pub fn init() Countdown {
        return .{ .current = 3, .start = 3 };
    }

    pub fn __next__(self: *Countdown) !?i64 {
        if (self.current <= 0) return null;
        self.current -= 1;
        return self.current + 1;
    }
};

const CountdownClass = pz.PyClass(Countdown, .{});

// A Counter that refuses to pass a limit. The derived struct's first field is the
// base's struct, which is how `PyClass` inheritance is declared.
const BoundedCounter = extern struct {
    base: Counter,
    limit: i64,

    pub fn init() BoundedCounter {
        return .{ .base = Counter.init(), .limit = 0 };
    }
};

fn bounded_bump(self: *BoundedCounter, by: i64) !i64 {
    if (self.base.value + by > self.limit) {
        zm.PyErr_SetString(zm.PyExc_ValueError(), "the counter would pass its limit");
        return error.WouldPassLimit;
    }
    self.base.value += by;
    return self.base.value;
}

const BoundedCounterClass = pz.PyClass(BoundedCounter, .{
    .base = CounterClass,
    .methods = &[_]pz.PyMethodDef{
        pz.wrapMethodNamed(BoundedCounter, "bump", bounded_bump),
    },
});

const Mod = pz.pyModule("bench_zig", .{
    .doc = "Benchmark workloads written in Zig.",
    .functions = &[_]pz.PyMethodDef{
        pz.pyFnNamed("add", add),
        pz.pyFnNamed("fib", fib),
        pz.pyFnNamed("count_primes", count_primes),
        pz.pyFnNamed("sum_floats", sum_floats),
        pz.pyFnNamed("make_range", make_range),
        pz.pyFnNamed("greet", greet),
        pz.pyFnKw("describe", describe, .{
            .args = &.{ "count", "step", "label", "unit" },
            .defaults = .{ .step = 1, .label = "item", .unit = null },
        }),
        pz.pyFnNamed("maybe_double", maybe_double),
        pz.pyFnNamed("histogram", histogram),
        pz.pyFnNamed("minmax", minmax),
        pz.pyFnNamed("reverse3", reverse3),
        pz.pyFnNamed("checksum", checksum),
        pz.pyFnNamed("expect_positive", expect_positive),
        pz.pyFnNamed("join_strings", join_strings),
        pz.pyFnNamed("echo_bytes", echo_bytes),
    },
    .classes = &[_]type{ CounterClass, CountdownClass, BoundedCounterClass },
});

comptime {
    pz.exportModule(Mod);
}
