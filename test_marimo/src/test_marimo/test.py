import marimo

__generated_with = "0.24.0"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo
    import pandas as pd
    import numpy as np
    from sqlalchemy import create_engine, text
    import sqlite3

    return (mo,)


@app.cell
def _():
    import os
    import sqlalchemy

    _password = os.environ.get("DB_PASSWORD")
    DATABASE_URL = f"postgresql://u0_a365:{_password}@127.0.0.1:5432/dvdrental"
    engine = sqlalchemy.create_engine(DATABASE_URL)
    return


@app.cell
def _(mo):
    _df = mo.sql(
        f"""
        SELECT * FROM customer;
        """
    )
    return


if __name__ == "__main__":
    app.run()
