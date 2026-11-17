# fuzzy_match

Fuzzy string matching in V, the hot loop that pure-Python libraries such as `jellyfish`
spend their time in: `levenshtein`, `similarity` (1 − distance / longer length),
`jaro_winkler`, and `extract(query, choices, limit=5, scorer="similarity")`, which returns
the best matches as tuples with named fields `(choice, score, index)`, like
`rapidfuzz.process.extract`. Everything works on code points, as Python does.

```console
$ vcraft develop
$ python test_fuzzy_match.py   # checks against pure Python, then times both
```

```python
>>> import fuzzy
>>> fuzzy.extract("appel", ["apple", "ample", "maple", "apply"], limit=2)
[Match(choice='apple', score=0.6, index=0), Match(choice='apply', score=0.6, index=3)]
```

On 20,000 words the search takes about 7 ms where the same algorithm in pure Python takes
about 350 ms, some 50x; the test prints the ratio on your machine. What makes the
difference besides compiled code: an ASCII pair is compared byte by byte with no code point
conversion, the distance rows are reused across choices, and only the `limit` best are
kept (`extract` in `src/fuzzy.v`).
