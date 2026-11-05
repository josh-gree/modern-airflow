"""Fans out one pod per number, slowly enough to watch in the UI."""

import time

import pendulum
from airflow.sdk import dag, task


@dag(schedule=None, start_date=pendulum.datetime(2026, 1, 1), catchup=False, tags=["demo"])
def countdown():
    @task
    def numbers() -> list[int]:
        return [5, 4, 3, 2, 1]

    @task
    def tick(number: int) -> int:
        time.sleep(number * 5)
        print(f"{number}...")
        return number

    @task
    def liftoff(ticks: list[int]) -> None:
        print(f"liftoff after {sum(ticks) * 5}s of waiting")

    liftoff(tick.expand(number=numbers()))


countdown()
