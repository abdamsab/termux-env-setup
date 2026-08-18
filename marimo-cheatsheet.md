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
marimo run notebook.py app2.py folder/  # serve multiple notebooks/apps
# stop: Ctrl+C in its terminal, or:
pkill -f "marimo edit"
pkill -f "marimo run"
```

## Central project manager (like JupyterLab)

Running `marimo edit` **without a filename** starts a server with a file
browser — list, create, and edit notebooks from a single page, just like
JupyterLab. This is the recommended way to manage a project.

```sh
# Start from your project root — browse all notebooks in the browser
cd ~/projects/myproject
marimo edit                         # http://127.0.0.1:2718 shows file tree

# Headless (phone / remote access)
marimo edit --headless --port 2718 --host 0.0.0.0
```

For **serving finished apps** (read-only, no editor), `marimo run` accepts
multiple paths — pass files and/or directories:

```sh
marimo run analysis.py dashboard/  --port 8080 --headless
```

To keep a single always-on server (like JupyterLab in a tmux/screen
session or as a Termux service):

```sh
# tmux/screen:
tmux new -s marimo
marimo edit --headless --port 2718
# detach with Ctrl+B, D

# or Termux runit service (see termux-ops skill)
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

## uv integration (recommended)

marimo is designed to work with [uv](https://docs.astral.sh/uv/) — the
fast Python package manager. Notebooks are `.py` files, so they slot
directly into uv's project workflow.

### Quick start: uv project + marimo

```sh
uv init myproject && cd myproject
uv add marimo pandas matplotlib   # deps tracked in pyproject.toml + uv.lock
uv run marimo edit                 # launch editor in the project's venv
uv run marimo run app.py           # serve a finished app
```

### Database drivers

```sh
# SQLAlchemy (ORM / raw SQL engine)
uv add sqlalchemy

# PostgreSQL
uv add psycopg2-binary            # or: uv add psycopg (async, no-binary)

# MySQL
uv add pymysql

# SQL Server (needs unixODBC system package: pkg install unixodbc)
uv add pyodbc

# DuckDB (in-process analytical SQL, no server needed)
# WARNING: no pre-built Termux wheel; source build fails.
# Use marimo's built-in DuckDB SQL cells instead, or skip.
# uv add duckdb  # BROKEN on Termux

# all at once
uv add sqlalchemy psycopg2-binary pymysql pyodbc duckdb
```

> On Termux, pre-built wheels come from TUR PyPI. uv does **not** read
> `pip.conf` — you must declare the index. This is configured globally
> in `~/.config/uv/uv.toml` (this setup writes it automatically).

### .env and secrets

marimo **auto-loads `.env`** files — the `.env` next to your
`pyproject.toml` is loaded by default. No `python-dotenv` needed.

```python
import os
DB_URL = os.environ["DATABASE_URL"]  # already available from .env
```

Configure multiple `.env` files in `pyproject.toml`:

```toml
[tool.marimo.runtime]
dotenv = [".env", ".env.testing"]
```

**Fallback: uv or python-dotenv (for standalone files without pyproject.toml):**

```sh
uv run --env-file .env marimo edit --headless --port 2718
```

**.env example for this setup:**

```ini
DATABASE_URL=postgresql+psycopg2://u0_a365:YOURPASSWORD@127.0.0.1:5432/postgres
MYSQL_URL=mysql+pymysql://user:pass@127.0.0.1:3306/db
MSSQL_URL=mssql+pyodbc://user:pass@host/db?driver=ODBC+Driver+18+for+SQL+Server
DUCKDB_PATH=./data.duckdb
```

> Never commit `.env` to git — add it to `.gitignore`.
> marimo surfaces env vars in the UI when creating databases.

### PEP 723 inline metadata (single-file sandbox)

marimo notebooks use PEP 723 `# /// script` blocks at the top of each
`.py` file to declare dependencies. marimo manages this block for you,
but here's what it looks like:

```python
# /// script
# requires-python = ">=3.14"
# dependencies = [
#     "marimo",
#     "pandas",
#     "matplotlib",
#     "sqlalchemy",
#     "psycopg2-binary",
# ]
# ///

import marimo as mo
import pandas as pd

@app.cell
def _():
    df = pd.DataFrame({"a": [1, 2, 3]})
    return (df,)
```

### Sandbox mode (`--sandbox`)

`--sandbox` tells marimo to run the notebook in an isolated venv created
from the `# /// script` block, using uv under the hood. Dependencies
install automatically — no manual `pip install` needed.

```sh
marimo edit notebook.py --sandbox  # single-file: uv run wraps the process
marimo run notebook.py --sandbox   # same for read-only apps
marimo edit --sandbox              # directory: per-notebook venvs (multi-file)

# with .env inside sandbox:
marimo edit notebook.py --sandbox --env-file .env
```

When you add/remove packages via the marimo UI (Cell > Add/Remove
package), marimo updates the `# /// script` block AND installs them
with `uv add` or `uv pip install` automatically.

### Project vs. standalone

| Mode | When | How deps are installed |
|---|---|---|
| **In a uv project** (pyproject.toml exists) | `uv run marimo edit` | `uv add <pkg>` — shared project env |
| **Standalone file** | `marimo edit --sandbox` | `uv pip install` into a per-file venv |
| **No sandbox** | `marimo edit notebook.py` | Uses the active/system Python directly |

### Export from a uv project

```sh
uv export --format requirements.txt -o requirements.txt  # lockfile -> requirements
uv run marimo export html notebook.py                     # export needs the project env
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

## Runtime configuration (pyproject.toml)

Configure marimo's runtime in `pyproject.toml`:

```toml
[tool.marimo.runtime]

# Auto-load .env files (the one next to pyproject.toml is loaded by default)
dotenv = [".env", ".env.testing"]

# Lazy execution: mark affected cells stale instead of auto-running
# (set in UI via Settings > On cell change > lazy)
# Useful for expensive notebooks

# Auto-cache every cell (avoid re-running expensive computations)
cache_cells = true

# Add directories to sys.path (before notebook code runs)
pythonpath = ["project/src"]

# Module autoreload: re-run cells when imported .py files change
# "autorun" = auto re-run affected cells
# "lazy"     = mark affected cells stale
on_module_change = "autorun"   # or "lazy"
```

### Python path

By default, marimo does not modify `sys.path` — keeping `marimo edit nb.py`
consistent with `python nb.py`. Use `pythonpath` in `pyproject.toml` when
you need modules from a subdirectory:

```toml
[tool.marimo.runtime]
pythonpath = ["project/src"]
```

Prefer the uv approach for library projects instead:

```sh
uv init --lib my_package && cd my_package
uv add --dev marimo
uv run marimo edit notebook.py     # my_package is importable
```

For multiple packages, use [uv workspaces](https://docs.astral.sh/uv/concepts/workspaces/).

### Keyboard / UI

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
