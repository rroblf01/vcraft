"""The nine benchmark workloads in plain Python: the baseline the extensions beat."""


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


def sum_floats(xs):
    total = 0.0
    for x in xs:
        total += x
    return total


def make_range(n):
    return list(range(n))


def greet(name):
    return f"Hello, {name}!"


def checksum(data):
    total = 0
    for b in data:
        total += b
    return total


def expect_positive(n):
    if n < 0:
        raise ValueError("expect_positive() expected n >= 0")
    return n


class Counter:
    def __init__(self):
        self.value = 0

    def increment(self):
        self.value += 1
        return self.value
