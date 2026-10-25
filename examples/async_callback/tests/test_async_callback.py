"""Tests for the async callback example."""

import asyncio
import unittest

import async_callback as m


class TestAsyncCallback(unittest.TestCase):
    def test_fast_path(self) -> None:
        async def add_one(x):
            await asyncio.sleep(0)
            return x + 1

        self.assertEqual(m.run_async(add_one, 41), 42)

    def test_slow_path(self) -> None:
        async def add_later(x):
            await asyncio.sleep(0.001)
            return x + 1

        self.assertEqual(m.run_async(add_later, 41), 42)

    def test_exception_propagates(self) -> None:
        async def boom(x):
            raise ValueError("from the coroutine")
            return x

        with self.assertRaises(RuntimeError):
            m.run_async(boom, 1)

    def test_running_loop_is_available(self) -> None:
        async def uses_loop(x):
            loop = asyncio.get_running_loop()
            await asyncio.sleep(0)
            return x + 1 if loop is not None else 0

        self.assertEqual(m.run_async(uses_loop, 41), 42)


if __name__ == "__main__":
    unittest.main()
