# csv_parser

A CSV parser in V that gives the same rows as Python's `csv` module (default dialect):
quoted fields, doubled quotes, separators and line breaks inside quotes, `\r\n`.
`parse(text, sep=",")` returns `list[list[str]]`, `records(text)` a `list[dict]` like
`csv.DictReader`.

```console
$ vcraft develop
$ python test_csv_parser.py     # compares with csv.reader on fixed and random tables
```

What to look at: unquoted fields are views of the input (`unsafe { tos(...) }`), valid for
the call and copied once into Python strings on return; only quoted fields go through a
builder. On 100k rows it runs about level with CPython's own C parser -- most of the time
on both sides is creating the 400k `str` objects -- which is the point for a format that
has no C implementation in the standard library.
