# JupyterLab cheatsheet (Termux)

Installed by termux-env-setup. The notebook UI is at http://127.0.0.1:8888 on
the phone; reach it from the phone browser, or from another machine with an
SSH tunnel (`ssh -L 8888:127.0.0.1:8888 user@phone`).

## Start / stop

```sh
jupyter lab --no-browser            # start on http://127.0.0.1:8888 (headless)
jupyter lab --no-browser --port 9999    # different port
jupyter lab --no-browser &          # background it (see README §3.4)
jupyter notebook list               # running servers + tokens (legacy)
jupyter server list                 # running servers + tokens (current)
# stop: Ctrl+C in its terminal, or:
pkill -f "jupyter lab"
```

## Defaults

| Setting | Default | Change |
|---|---|---|
| address | 127.0.0.1 (loopback only) | `--ip 0.0.0.0` to expose on LAN (careful) |
| port | 8888 | `--port <n>` |
| browser | never opens (headless) | omit `--no-browser` if a browser exists |
| config dir | `~/.jupyter/` | `JUPYTER_CONFIG_DIR=...` |
| data dir | `~/.local/share/jupyter/` | `JUPYTER_DATA_DIR=...` |

Config file: `jupyter lab --generate-config` writes
`~/.jupyter/jupyter_lab_config.py` (edit port, IP, token there).

## Security / access

```sh
jupyter server list                 # shows url?token=... for the running server
jupyter lab password                # set a permanent password (kills token prompts)
# expose to the LAN with an explicit password:
jupyter lab --no-browser --ip 0.0.0.0 --ServerApp.token='' --ServerApp.password='...'
# or edit jupyter_lab_config.py:
#   c.ServerApp.ip = '0.0.0.0'
#   c.ServerApp.port = 8888
```

## Kernels

```sh
jupyter kernelspec list             # installed kernels
python -m ipykernel install --user --name myenv --display-name "My Env"
pip install ipykernel ipywidgets    # needed for new venvs to show up
# register a venv: . .venv/bin/activate && pip install ipykernel && python -m ipykernel install --user
```

## LSP intellisense in code cells

```sh
pylsp --version                     # python-lsp-server (installed with jupyterlab-lsp)
jupyter labextension list           # should show @jupyter-lsp/jupyterlab-lsp
```

Enable per-notebook: open a notebook → right sidebar → **rocket / LSP icon** →
toggle **Enable** (once per browser session). Then code cells get completions,
diagnostics, hover docs and go-to-definition. Install more language servers
later and they auto-register on restart:

```sh
pip install jedi-language-server     # or pyright, yaml-language-server, ...
```

The `Skipped non-installed server(s)` startup line is dropped by a
`logging.Filter` in `~/.jupyter/jupyter_lab_config.py` (autodetect stays on).

## Keyboard shortcuts

| Keys | Action |
|---|---|
| `Shift+Enter` | run cell, select below |
| `Ctrl+Enter` | run cell, stay |
| `Alt+Enter` | run cell, insert below |
| `Esc` then `I I` | interrupt kernel |
| `Esc` then `0 0` | restart kernel |
| `Esc` then `A` / `B` | insert cell above / below |
| `Esc` then `M` / `Y` | cell → markdown / code |
| `Esc` then `D D` | delete cell |
| `Ctrl+S` | save |
| `Ctrl+Shift+P` | command palette |
| `Ctrl+Shift+C` | open terminal inside Jupyter |
| `Ctrl+F` / `Ctrl+Shift+F` | find / find in files |

## Magic commands (cell / line)

```python
%load_ext autoreload
%autoreload 2                     # auto-reload edited modules

%time   expr                      # time one run
%timeit expr                      # time many runs
%%timeit                          # cell-level timer
%%capture out                     # capture cell stdout/stderr into `out`

%debug / %pdb                     # post-mortem debugging
%whos / %who / %who_ls            # inspect variables
%history                          # shell history
%matplotlib inline                # inline plots
%%writefile foo.py                # dump cell contents to a file
%%bash                            # run the cell as a shell script
!ls -la                           # one-line shell command
!ss -tlnp | grep 8888             # is the server listening?
```

## Plotting / display

```python
import matplotlib.pyplot as plt
%matplotlib inline
fig, ax = plt.subplots()
ax.plot([1, 2, 3], [4, 5, 6]); plt.show()

# rich HTML output of any object:
from IPython.display import display, HTML, Markdown, Image, display_html
display(HTML("<b>hi</b>"))

# dataframes auto-render as HTML tables; control it:
pd.set_option("display.max_rows", 50)
pd.set_option("display.max_columns", 20)
```

## DataFrames quickies

```python
df.info(); df.describe(); df.head(); df.tail()
df.value_counts().head(20)
df.plot()                         # quick matplotlib line plot
df.corr(); df.groupby("col").agg(["mean", "count"])
```

## Export / convert (nbconvert)

```sh
pip install nbconvert nbformat     # part of jupyterlab, usually present
jupyter nbconvert notebook.ipynb --to html
jupyter nbconvert notebook.ipynb --to markdown
jupyter nbconvert notebook.ipynb --to script        # strip outputs -> .py
jupyter nbconvert --execute notebook.ipynb --to html --output executed.html
```

## Import / connect to DBs (installed with this setup)

```python
import sqlalchemy
from sqlalchemy import create_engine

# PostgreSQL (local postgres service from this setup)
# user = your Termux username (superuser), password in ~/.pgpass_initial
engine = create_engine("postgresql+psycopg2://u0_a365:PASSWORD@127.0.0.1:5432/postgres")

# MySQL
engine = create_engine("mysql+pymysql://user:pass@host:3306/db")

# SQL Server (needs an ODBC driver, see README §6)
engine = create_engine("mssql+pyodbc://user:pass@host/db?driver=ODBC+Driver+18+for+SQL+Server")

import pandas as pd
pd.read_sql("select * from t limit 100", engine)
```

## Tips

- First run prints a `url?token=...`; paste it in a browser, or set a
  password once with `jupyter lab password`.
- On a phone always use `jupyter lab --no-browser` — there's nothing to open.
- Big outputs: use `df.head()` / `df.tail()`; large HTML output slows the UI.
- `pkill -f "jupyter lab"` is the reliable way to stop it headlessly.
- Remote access from a laptop: `ssh -L 8888:127.0.0.1:8888 user@phone` then
  open http://127.0.0.1:8888 locally (no `--ip 0.0.0.0` needed, stays secure).
