"""The thirteen benchmark workloads in plain Python: the baseline the extensions beat."""


def add(a, b):
    return a + b


def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


def count_primes(n):
    if n < 2:
        return 0
    composite = bytearray(n + 1)
    count = 0
    for i in range(2, n + 1):
        if not composite[i]:
            count += 1
            for j in range(i * i, n + 1, i):
                composite[j] = 1
    return count


def sum_squares(n):
    total = 0
    for i in range(1, n + 1):
        total += i * i
    return total


def lcg(n):
    x = 12345
    for _ in range(1, n + 1):
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    return x


def sum_floats(xs):
    total = 0.0
    for x in xs:
        total += x
    return total


def make_range(n):
    return list(range(n))


def greet(name):
    return f"Hello, {name}!"


def describe(count, step=1, label="item", unit=None):
    return f"{label}: {count * step}{unit or ''}"


def maybe_double(x=None):
    return None if x is None else x * 2


def histogram(words):
    counts = {}
    for word in words:
        counts[word] = counts.get(word, 0) + 1
    return counts


def minmax(xs):
    if not xs:
        raise ValueError("minmax() arg is an empty sequence")
    return min(xs), max(xs)


def reverse3(a):
    if len(a) != 3:
        raise ValueError("reverse3() needs exactly 3 items")
    return [a[2], a[1], a[0]]


def checksum(data):
    total = 0
    for b in data:
        total += b
    return total


def expect_positive(n):
    if n < 0:
        raise ValueError("expect_positive() expected n >= 0")
    return n


def join_strings(parts):
    return ",".join(parts)


def echo_bytes(data):
    # bytes() on a view copies exactly once; bytes(data) or data + b""
    # would return the same object.
    return bytes(memoryview(data))


class Counter:
    def __init__(self):
        self.value = 0

    def increment(self):
        self.value += 1
        return self.value

    def add(self, n):
        self.value += n
        return self.value

    @property
    def is_zero(self):
        return self.value == 0

    def __eq__(self, other):
        if isinstance(other, Counter):
            return self.value == other.value
        return NotImplemented

    def __hash__(self):
        return hash(self.value)


class Countdown:
    def __init__(self):
        self.current = 3
        self.start = 3

    def __iter__(self):
        return self

    def __next__(self):
        if self.current <= 0:
            raise StopIteration
        self.current -= 1
        return self.current + 1


class BoundedCounter(Counter):
    def __init__(self):
        super().__init__()
        self.limit = 0

    def bump(self, by):
        if self.value + by > self.limit:
            raise ValueError("the counter would pass its limit")
        self.value += by
        return self.value
