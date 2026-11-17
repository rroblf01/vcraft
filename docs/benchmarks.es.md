# Benchmarks

Todos los números de esta página se pueden reproducir desde el repositorio: el banco de
pruebas, los tres proyectos equivalentes (PyO3, vcraft, zig-maturin) y una referencia en
Python puro están en
[`benchmark/`](https://github.com/rroblf01/vcraft/tree/main/benchmark), y cada ejecución
guardada registra el toolchain que la produjo.

## vcraft 1.8.0 frente a PyO3 0.29

Linux x86_64, CPython 3.13, builds release de ambos (`cargo --release`,
`vcraft build --release`), ambos con comprobación de límites. Medido con
`benchmark/ab.py`, cinco rondas intercaladas, mejor cifra por variante. Tiempo por
llamada, menos es mejor; en la última columna, por debajo de 1,00 vcraft es más rápido.

| carga | PyO3 | vcraft | vcraft/PyO3 |
|---|---|---|---|
| add | 69 ns | 60 ns | 0.87× |
| fib(25) | 227.6 µs | 109.5 µs | 0.48× |
| count_primes(1e6) | 1.93 ms | 2.12 ms | 1.10× |
| sum_floats(100k) | 833.3 µs | 234.8 µs | 0.28× |
| make_range(100k) | 2.18 ms | 2.30 ms | 1.05× |
| greet | 131 ns | 108 ns | 0.83× |
| describe(3) | 165 ns | 121 ns | 0.73× |
| histogram(10k) | 718.4 µs | 570.9 µs | 0.79× |
| minmax(100k) | 1.09 ms | 555.9 µs | 0.51× |
| reverse3([1,2,3]) | 193 ns | 157 ns | 0.81× |
| checksum(100kB) | 13.5 µs | 12.7 µs | 0.94× |
| echo_bytes(100kB) | 3.6 µs | 1.8 µs | 0.49× |
| join_strings(10k) | 483.5 µs | 300.5 µs | 0.62× |
| expect_positive(err) | 218 ns | 209 ns | 0.96× |
| Counter() | 94 ns | 70 ns | 0.74× |
| c.increment() | 57 ns | 44 ns | 0.78× |
| c.add(1) | 62 ns | 57 ns | 0.92× |
| c.value | 46 ns | 41 ns | 0.89× |
| c.is_zero | 36 ns | 38 ns | 1.08× |
| c == c | 47 ns | 26 ns | 0.57× |
| list(Countdown()) | 348 ns | 237 ns | 0.68× |
| Vector(1000) | 221 ns | 221 ns | 1.00× |
| vector.total() | 786 ns | 792 ns | 1.01× |
| complex_scale(1+2j, 3) | 89 ns | 83 ns | 0.93× |
| Counter.zero() | 59 ns | 53 ns | 0.90× |
| import (median of 30) | 0.591 ms | 0.592 ms | 1.00× |

vcraft es más rápido en 20 de las 26 filas, empata en tres y es más lento en tres:
`count_primes` (10 %, un bucle de criba ajustado con una reserva de 1 MB), `make_range`
(5 %, dentro del ruido de los bucles largos) y la lectura de la propiedad `c.is_zero`
(2 ns). Las ventajas grandes están en las conversiones (`sum_floats`, `minmax`,
`echo_bytes`, `join_strings`) y en el `fib` recursivo.

## Cómo leer una diferencia

Dos builds del mismo código difieren hasta un 5 % en llamadas cortas y un 10 % en bucles
largos de una ejecución a otra en la misma máquina. Un único `run.sh` no puede distinguir
una diferencia menor que esa; por eso las comparaciones se hacen con `ab.py`, que ejecuta
todas las variantes ronda tras ronda, intercaladas, y se queda con el mejor tiempo de cada
una, de modo que la carga o los cambios de frecuencia afectan a todas por igual.

## Reproducirlo

```console
$ cd benchmark
$ ./run.sh                    # construye los tres, instala en benchmark/.venv y mide
$ ./run.sh --quick            # menos repeticiones, para comprobar el banco de pruebas
$ python ab.py pyo3=.venv/bin/python:bench_pyo3 \
               vcraft=.venv/bin/python:bench_vcraft_native --rounds 5
```

`run.sh` necesita `uv`, `cargo` y un `v` compilado en el commit fijado en el `PATH` (zig
0.16 es opcional); no instala nada fuera de `benchmark/.venv`. Además de velocidad mide
memoria máxima y retenida (cada escenario dos veces, así una fuga aparece como
crecimiento), tiempo de importación, tamaño del wheel y del binario, una matriz de
corrección con casos límite, retención de referencias y escalado sin GIL entre hilos.

Las tablas completas, con memoria, tamaño y la historia de cada optimización, están en
[`benchmark/results-linux.md`](https://github.com/rroblf01/vcraft/blob/main/benchmark/results-linux.md)
y [`benchmark/HISTORY.md`](https://github.com/rroblf01/vcraft/blob/main/benchmark/HISTORY.md).
