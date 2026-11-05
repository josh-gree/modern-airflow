"""Smoke test: two tasks in separate pods, passing a value through XCom."""

import socket

import pendulum
from airflow.sdk import dag, task


@dag(schedule=None, start_date=pendulum.datetime(2026, 1, 1), catchup=False, tags=["smoke"])
def hello_k8s():
    @task
    def where_am_i() -> str:
        return socket.gethostname()

    @task
    def compare(upstream_host: str) -> None:
        here = socket.gethostname()
        print(f"upstream={upstream_host} here={here}")
        assert upstream_host != here, "expected tasks to run in separate pods"

    compare(where_am_i())


hello_k8s()
