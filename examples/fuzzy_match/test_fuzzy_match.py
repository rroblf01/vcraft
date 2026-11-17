"""Run with the built extension importable: `vcraft develop`, then `python test_fuzzy_match.py`.

Checks every function against straightforward pure-Python versions (the algorithms
`jellyfish` and `difflib`-style code use), then times the best-match search both ways.
"""

import random
import time

import fuzzy


def py_levenshtein(a: str, b: str) -> int:
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def py_similarity(a: str, b: str) -> float:
    longest = max(len(a), len(b))
    return 1.0 if longest == 0 else 1.0 - py_levenshtein(a, b) / longest


def py_jaro_winkler(a: str, b: str) -> float:
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    window = max(max(len(a), len(b)) // 2 - 1, 0)
    a_hit, b_hit = [False] * len(a), [False] * len(b)
    matches = 0
    for i, ca in enumerate(a):
        for k in range(max(0, i - window), min(i + window + 1, len(b))):
            if not b_hit[k] and ca == b[k]:
                a_hit[i] = b_hit[k] = True
                matches += 1
                break
    if matches == 0:
        return 0.0
    transpositions, k = 0, 0
    for i, ca in enumerate(a):
        if a_hit[i]:
            while not b_hit[k]:
                k += 1
            transpositions += ca != b[k]
            k += 1
    m = matches
    jaro = (m / len(a) + m / len(b) + (m - transpositions / 2) / m) / 3
    prefix = 0
    while prefix < 4 and prefix < min(len(a), len(b)) and a[prefix] == b[prefix]:
        prefix += 1
    return jaro + prefix * 0.1 * (1 - jaro)


def py_extract(query, choices, limit=5, scorer=py_similarity):
    scored = [(c, scorer(query, c), i) for i, c in enumerate(choices)]
    scored.sort(key=lambda m: (-m[1], m[2]))
    return scored[:limit]


assert fuzzy.levenshtein("kitten", "sitting") == 3
assert fuzzy.levenshtein("café", "cafe") == 1  # code points, not bytes
assert round(fuzzy.jaro_winkler("MARTHA", "MARHTA"), 4) == 0.9611
assert fuzzy.similarity("", "") == 1.0

rng = random.Random(3)
alphabet = "abcdeéñ "
for _ in range(2000):
    a = "".join(rng.choice(alphabet) for _ in range(rng.randrange(12)))
    b = "".join(rng.choice(alphabet) for _ in range(rng.randrange(12)))
    assert fuzzy.levenshtein(a, b) == py_levenshtein(a, b), (a, b)
    assert abs(fuzzy.jaro_winkler(a, b) - py_jaro_winkler(a, b)) < 1e-12, (a, b)

words = ["".join(rng.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(rng.randrange(4, 14)))
         for _ in range(20_000)]
query = "fuzzymatching"
best = fuzzy.extract(query, words, limit=5)
assert [(m.choice, m.index) for m in best] == [(c, i) for c, _, i in py_extract(query, words)]
assert best[0].score >= best[-1].score and isinstance(best[0], tuple) and best[0].choice == best[0][0]
jw = fuzzy.extract(query, words, limit=3, scorer="jaro_winkler")
assert [m.index for m in jw] == [i for _, _, i in py_extract(query, words, 3, py_jaro_winkler)]
try:
    fuzzy.extract(query, words, scorer="cosine")
except ValueError:
    pass
else:
    raise AssertionError("an unknown scorer was accepted")

start = time.perf_counter()
fuzzy.extract(query, words, limit=5)
v_time = time.perf_counter() - start
start = time.perf_counter()
py_extract(query, words)
py_time = time.perf_counter() - start
print(f"ok fuzzy_match (best of 20k words: V {v_time * 1000:.1f} ms, "
      f"pure Python {py_time * 1000:.0f} ms, {py_time / v_time:.0f}x)")
