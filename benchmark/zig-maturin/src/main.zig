const std = @import("std");
const pz = @import("pyo3zig");
const zm = @import("zig-maturin");

// A Zig panic becomes a Python exception instead of aborting the interpreter.
pub const panic = pz.panic;

// The same nine workloads as the PyO3 and vcraft projects, with the same
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

// Method-call overhead on a native object.
const Counter = extern struct {
    value: i64,

    pub fn init() Counter {
        return .{ .value = 0 };
    }
};

fn counter_increment(self: *Counter) i64 {
    self.value += 1;
    return self.value;
}

const CounterClass = pz.PyClass(Counter, .{
    .methods = &[_]pz.PyMethodDef{
        pz.wrapMethodNamed(Counter, "increment", counter_increment),
    },
    .readonly = &.{"value"},
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
        pz.pyFnNamed("checksum", checksum),
        pz.pyFnNamed("expect_positive", expect_positive),
    },
    .classes = &[_]type{CounterClass},
});

comptime {
    pz.exportModule(Mod);
}
