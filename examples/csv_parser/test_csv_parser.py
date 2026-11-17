"""Run with the built extension importable: `vcraft develop`, then `python test_csv_parser.py`.

Compares the V parser with Python's own `csv` module, then times both.
"""

import csv
import io
import random
import time

import csvfast

SAMPLE = 'name,quote,n\r\nada,"said ""hi"", twice",1\n\nbob,"two\nlines",2\nempty,,\n'

assert csvfast.parse(SAMPLE) == list(csv.reader(io.StringIO(SAMPLE, newline=""))), csvfast.parse(SAMPLE)
assert csvfast.parse("a;b\n1;2", sep=";") == [["a", "b"], ["1", "2"]]
assert csvfast.records(SAMPLE) == [dict(r) for r in csv.DictReader(io.StringIO(SAMPLE, newline=""))]

for bad, needle in (('a,"open\n', "line 1"), ("x", None)):
    try:
        csvfast.parse(bad)
    except ValueError as exc:
        assert needle and needle in str(exc), exc
    else:
        assert needle is None
try:
    csvfast.parse("a", sep='"')
except ValueError:
    pass
else:
    raise AssertionError("a quote separator was accepted")

# Random tables survive a round trip through csv.writer.
rng = random.Random(7)
alphabet = 'ab ,"\n\r1é'
for _ in range(200):
    rows = [["".join(rng.choice(alphabet) for _ in range(rng.randrange(6)))
             for _ in range(rng.randrange(1, 5))] for _ in range(rng.randrange(1, 6))]
    buf = io.StringIO(newline="")
    csv.writer(buf).writerows(rows)
    text = buf.getvalue()
    assert csvfast.parse(text) == list(csv.reader(io.StringIO(text, newline=""))), text

big = "".join(f'{i},"name {i}",{i * 0.5},"x, y"\n' for i in range(100_000))
start = time.perf_counter()
mine = csvfast.parse(big)
v_time = time.perf_counter() - start
start = time.perf_counter()
theirs = list(csv.reader(io.StringIO(big, newline="")))
py_time = time.perf_counter() - start
assert mine == theirs
print(f"ok csv_parser (100k rows: V {v_time * 1000:.0f} ms, the C csv module {py_time * 1000:.0f} ms)")
