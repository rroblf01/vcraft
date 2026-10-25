# async_callback

A Python extension written in V.

## Installation

```console
$ pip install async_callback
```

## Usage

```python
>>> import async_callback as m
>>> m.greet('world')
'Hello, world!'
>>> m.add(2, 3)
5
>>> c = m.Counter()
>>> c.increment()
1
```

## Development

Written in [V](https://vlang.io) and built with [vcraft](https://github.com/rroblf01/vcraft).

```console
$ python -m venv .venv && source .venv/bin/activate
$ vcraft develop          # build and install into the active virtualenv
$ python main.py          # run the example, which imports the extension
$ python -m unittest      # run the tests under tests/
$ vcraft build --release  # write a wheel into dist/
```
