# marimo cheatsheet (Termux)

Installed by termux-env-setup (v0.23.16). marimo is a *reactive* Python
notebook: running one cell automatically re-runs only the cells that depend
on it. Notebooks are plain `.py` files, so they version-control cleanly.

UI runs at http://127.0.0.1:2718 by default.

## Start / stop

```sh
marimo edit                        # start the server, create/edit notebooks
marimo edit notebook.py            # create or edit a specific notebook
marimo edit notebook.py --headless --port 2718   # headless (no browser), custom port
marimo run notebook.py             # serve a notebook as a read-only app
marimo serve                       # serve multiple notebooks/apps
# stop: Ctrl+C in its terminal, or:
pkill -f "marimo edit"
```

## File / CLI

```sh
marimo new                         # create an empty notebook
marimo new "Prompt to generate a notebook"   # AI-generate from a prompt
marimo tutorial intro              # interactive tour
marimo convert notebook.ipynb      # convert Jupyter .ipynb / md / py:percent -> marimo
marimo export script notebook.py   # flatten to a plain .py script
marimo export ipynb notebook.py    # marimo -> Jupyter notebook
marimo export md notebook.py       # marimo -> Markdown (code fenced)
marimo export html notebook.py     # run + export static HTML  (needs playwright, see below)
marimo export pdf notebook.py      # run + export PDF           (needs playwright)
```

`marimo export html/pdf` render with a headless browser:

```sh
pip install playwright
playwright install chromium        # one-time; needed only for html/pdf export
```

## Interactive cell basics

- Run a cell: `Shift+Enter` (reactive — dependents re-run automatically).
- Autosaves on every run; the file is readable `.py`.
- Define/reference variables across cells freely — order doesn't matter.
- To stop/refresh: sidebar ✕ or `marimo` toolbar buttons.

```python
import marimo as mo

@app.cell            # the decorator each cell uses (auto-added by marimo)
def _():
    import pandas as pd
    df = pd.DataFrame({"a": [1, 2, 3], "b": [4, 5, 6]})
    return (df,)
```

## Output & layout

```python
mo.md("# Title\nSome **markdown**.")         # markdown block
mo.Html("<b>raw html</b>")                    # raw HTML
mo.hstack([...])                              # side-by-side layout
mo.vstack([...])                              # stacked layout
mo.tabs({"Tab A": tab_a_output, "Tab B": tab_b_output})
mo.accordion({"Details": detail_output})
mo.carousel([...])
mo.ui.sidebar(...)                            # app sidebar
mo.status.running("loading…") / mo.status.done(...)  # progress/status
mo.callout("Note", kind="info")               # callout boxes (info/warn/danger)
```

## Interactive controls (`mo.ui`)

```python
slider = mo.ui.slider(0, 100, value=50, label="value")
btn    = mo.ui.button(label="click")
sel    = mo.ui.dropdown({"a": 1, "b": 2}, label="pick")
check  = mo.ui.checkbox(value=True, label="on")
txt    = mo.ui.text(value="hello", label="name")
num    = mo.ui.number(start=0, stop=10, value=3, label="n")
date   = mo.ui.date(label="when")
df_w   = mo.ui.dataframe(df)                 # editable dataframe
table  = mo.ui.table(df)                     # selectable table
batch  = mo.ui.batch(controls=[slider, sel]) # group into a dict
```

Controls are *reactive*: use `slider.value` in other cells and they
re-execute when the widget changes. You don't call them — you read `.value`.

## Async / running code

```python
# marimo runs cells, not scripts; async is natural:
@app.cell
async def _():
    import asyncio
    await asyncio.sleep(0.1)
    return ("done",)

# run the notebook itself from the shell (executes all cells):
python notebook.py
```

## DataFrames / plots

```python
import matplotlib.pyplot as plt
fig, ax = plt.subplots()
ax.plot(df["a"], df["b"])
mo.output(fig)                       # marimo renders the figure

df                              # last expression of a cell is displayed
mo.ui.table(df).value           # row selections -> filtered dataframe
```

## Databases (installed with this setup)

```python
import sqlalchemy as sa
from sqlalchemy import create_engine

engine = create_engine("postgresql+psycopg2://u0_a365:PASSWORD@127.0.0.1:5432/postgres")
# user = your Termux username (superuser, see ~/.pgpass_initial for the password)
# engine = create_engine("mysql+pymysql://user:pass@host:3306/db")
# engine = create_engine("mssql+pyodbc://user:pass@host/db?driver=ODBC+Driver+18+for+SQL+Server")

import pandas as pd
pd.read_sql("select * from t limit 100", engine)
```

marimo also has SQL cells (`%sql` style) driven by DuckDB — install duckdb
if you want in-notebook SQL.

## Config

- Global config: `~/.config/marimo/marimo.toml` (this setup writes an empty
  one). Options include server host/port, token, theme.
- Per-project: `.marimo.toml` next to your notebooks.
- CLI/server flags beat file config (e.g. `--port`, `--headless`).

## Keyboard / UI

| Keys | Action |
|---|---|
| `Shift+Enter` | run cell (reactive) |
| `Ctrl/Cmd+.` | run cell (non-reactive) |
| `Alt/Cmd+Enter` | run cell + create cell below |
| `Ctrl/Cmd+S` | save |
| `Ctrl/Cmd+F` | find in notebook |
| `Ctrl/Cmd+Shift+P` | command palette |
| `?` | show shortcuts in the app |

## Tips

- Cells can appear in any order — references resolve automatically (no
  "run in order" bugs).
- Every run autosaves; keep notebooks in git for free versioning.
- Prefer `marimo edit notebook.py --headless` on the phone (no browser).
- Large notebooks: keep one concern per cell; marimo re-runs only dependents.
