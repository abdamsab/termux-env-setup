# uv cheatsheet (Termux)

Installed by termux-env-setup (v0.12.4). uv is an extremely fast Python
package/environment manager (written in Rust) — a drop-in for
pip + venv + pip-tools (and a lighter Poetry). Handy on a phone: native
binary, no Python needed to manage Python.

## TL;DR

```sh
uv venv                        # create .venv  (python 3.14 = system)
source .venv/bin/activate      # activate it (fish: . .venv/bin/activate.fish)

uv pip install numpy           # pip-compatible installs (respects pip.conf index)
uv pip list / uv pip freeze
uv pip uninstall numpy

# project workflow (pyproject.toml + uv.lock):
uv init                        # new project
uv add requests                # add + install a dependency
uv remove requests
uv run main.py                 # run with the project env
uv sync                        # rebuild env from uv.lock
```

## Pitfalls (read this first!)

### `uv add` vs `uv pip install` — never mix in the same project

| | `uv add` | `uv pip install` |
|---|---|---|
| Needs `pyproject.toml`? | Yes | No |
| Updates `pyproject.toml`? | Yes | No |
| Updates `uv.lock`? | Yes | No |
| Visible to `uv sync`? | Yes | No |
| Visible to collaborators? | Yes | No |

**What goes wrong:**

```sh
uv add pandas           # writes to pyproject.toml + uv.lock, installs
uv pip install scipy    # installs into venv only, invisible to project
uv sync                 # recreates from uv.lock — scipy disappears!
```

**The rule:**
- **Project** (has `pyproject.toml`)? → always `uv add` / `uv remove`
- **Standalone venv** (no project)? → always `uv pip install` / `uv pip uninstall`
- **Never mix both** in the same environment

### Migrating from pip to uv project

If you already have packages installed with `pip` and want to move to a
uv project, don't just run `uv add` alongside them:

```sh
# WRONG: pip install + uv add = hidden deps, sync breaks
pip install pandas
uv add sqlalchemy           # pyproject.toml has sqlalchemy, NOT pandas
uv sync                     # pandas vanishes

# RIGHT: declare everything in pyproject.toml
uv init myproject && cd myproject
uv add pandas sqlalchemy    # all deps tracked properly
uv sync                     # reproducible — installs exactly what's listed
```

### `uv sync` is destructive

`uv sync` recreates the venv from `uv.lock`. Anything installed outside
`uv add` (pip, `uv pip install`, manual `pip install -e .`) is removed:

```sh
uv sync                     # installs exactly what uv.lock says — nothing else
uv pip install debug-tool   # added to venv, NOT in uv.lock
uv sync                     # debug-tool is gone
```

### `uv run` only sees project deps

`uv run` activates the project environment. Packages installed outside
the project (system-wide `pip install`) are not visible unless they're
in `uv.lock` or you pass `--with`:

```sh
uv run python -c "import scipy"     # ModuleNotFoundError (not in project)
uv run --with scipy python -c "import scipy"  # works (ephemeral)
```

### Quick reference — which command for what?

| Situation | Command |
|---|---|
| Add a dep to a project | `uv add pandas` |
| Remove a dep from a project | `uv remove pandas` |
| Install into a standalone venv | `uv pip install pandas` |
| Install from requirements.txt (no project) | `uv pip install -r requirements.txt` |
| Rebuild venv from lockfile | `uv sync` |
| Run script in project env | `uv run script.py` |
| Run with ephemeral extra dep | `uv run --with scipy script.py` |

## Environment / venv

```sh
uv venv                        # .venv with the active/system python
uv venv --python 3.13          # specific interpreter (see "uv python")
uv venv .venv --clear          # recreate
source .venv/bin/activate      # activate
deactivate                     # leave
```

## pip-compatible interface (`uv pip`)

```sh
uv pip install requests                # into the active venv
uv pip install -r requirements.txt
uv pip install --extra-index-url https://termux-user-repository.github.io/pypi/ numpy
uv pip list / uv pip freeze / uv pip check
uv pip uninstall requests
uv pip install -e ./hermes-agent       # editable local project
```

uv honors `~/.config/pip/pip.conf` for `uv pip` commands only.
For project mode (`uv add` / `uv sync` / `uv run`), you must declare
indexes explicitly — see **TUR PyPI (Termux)** below.

## TUR PyPI (Termux — pre-built wheels)

Termux packages (numpy, pandas, scipy, pydantic-core, etc.) need
pre-built wheels from the [TUR PyPI](https://termux-user-repository.github.io/pypi/).
**`uv add` / `uv sync` / `uv run` do NOT read `pip.conf`** — you must
declare the index yourself.

**Global config** (all projects, already written by this setup):

```toml
# ~/.config/uv/uv.toml
[[index]]
url = "https://termux-user-repository.github.io/pypi/"
name = "tur-pypi"

python-downloads = "never"
```

```sh
# ~/.bashrc (this setup adds both)
export UV_INDEX_STRATEGY=unsafe-best-match   # check all indexes
export UV_LINK_MODE=copy                     # avoid hardlink warning
```

> **`UV_INDEX_STRATEGY=unsafe-best-match`:** By default, uv only uses
> the **first** index that has a package. If TUR has `cmake==3.28.4` but
> a package needs `cmake>=3.29.0`, uv fails instead of checking PyPI.
> With `unsafe-best-match`, uv checks all indexes — TUR first (pre-built
> wheels), then PyPI (newer versions as fallback). This is safe because
> both are trusted sources.

**Per-project** (in `pyproject.toml`):

```toml
[[tool.uv.index]]
url = "https://termux-user-repository.github.io/pypi/"
name = "tur-pypi"
```

**Per-project** (in `uv.toml` alongside `pyproject.toml`):

```toml
[[index]]
url = "https://termux-user-repository.github.io/pypi/"
name = "tur-pypi"
```

**One-off** (inline flag):

```sh
uv add --index https://termux-user-repository.github.io/pypi/ pandas
```

> The global `~/.config/uv/uv.toml` is the recommended approach — set
> once, works for all projects. Without this, `uv add pandas` tries to
> build from source and fails (no meson/cython on Termux).

### Termux package layers

There are **two ways** packages arrive on Termux — know which layer you're in:

| Layer | Install with | Scope | Example |
|---|---|---|---|
| **System** (TUR) | `pkg install python-X` | Global, all venvs see it | `pkg install python-numpy` |
| **Project** (uv) | `uv add X` | Per-project `.venv` only | `uv add pandas` |

- `pkg install python-pandas` → installs pandas system-wide; `uv pip install`
  finds it via TUR PyPI index; `uv add` re-downloads into `.venv`.
- Many packages (numpy, pandas, scipy, pydantic) are available as TUR
  system packages — `pkg install` is faster and avoids venv duplication.

### Packages that DON'T work on Termux

Some packages have no pre-built Termux wheel and fail to compile from source:

- **duckdb** — manylinux wheels need glibc loader setup; source build
  fails (cmake/cython version mismatch). Use `marimo`'s built-in
  DuckDB cells as a workaround, or skip it.

## Project workflow

```sh
uv init myproj && cd myproj    # creates pyproject.toml, src layout
uv add "requests>=2" "httpx"   # add deps + update uv.lock + sync env
uv remove httpx
uv sync                        # sync env to uv.lock (reproducible)
uv lock --upgrade              # bump all pinned versions
uv tree                        # dependency tree
uv export --format requirements.txt -o requirements.txt   # export lock
```

## Running scripts

```sh
uv run script.py               # runs with project env (or system python)
uv run python -m pytest        # any command, in the project env
uv run --with requests script.py   # ephemeral extra for one run
uv run --no-project script.py      # ignore pyproject.toml
```

uv also runs standalone scripts with inline dependencies:

```python
# /// script
# requires-python = ">=3.14"
# dependencies = ["requests"]
# ///
import requests
print(requests.get("https://example.com").status_code)
```

```sh
uv run myscript.py             # uv auto-creates an env for the inline deps
```

## Tools (pipx replacement)

```sh
uv tool install ruff           # install globally into an isolated env
uv tool install --with torch somepkg
uvx ruff check .               # run without installing (uv tool run)
uv tool list / uv tool uninstall ruff
```

## Managing Pythons (`uv python`)

```sh
uv python list                 # installed + downloadable versions
uv python install 3.13         # download/install a CPython
uv python find                 # show the interpreter uv would use
uv venv --python 3.12.4
```

On Termux, uv-managed CPython builds aren't available — keep it on the
system Python:

```sh
export UV_PYTHON_DOWNLOADS=never   # don't try to fetch managed pythons
export UV_NO_MANAGED_PYTHON=1      # or --no-managed-python
```

## Cache / maintenance

```sh
uv cache dir                   # where the cache lives (~/.cache/uv)
uv cache clean                 # clear everything
uv cache clean <pkg>           # clear one package
uv self update                 # upgrade uv itself
uv audit                       # check for known-vulnerability advisories (experimental)
uv format / uv check           # ruff-style formatting / lint check (experimental)
```

> **Termux note:** `uv audit`, `uv format`, and `uv check` are experimental
> (need `--preview-features`) and `uv format`/`uv check` require ruff and ty
> binaries that aren't available for `aarch64-linux-android`. Use
> `uvx ruff check .` / `uvx ruff format .` instead (install ruff first).

## Termux notes

- Uses system Python 3.14; `UV_PYTHON_DOWNLOADS=never` is set globally
  (`~/.config/uv/uv.toml`) so uv never tries to fetch a managed CPython.
- TUR PyPI: see **TUR PyPI (Termux)** section above for index setup.
- Cache lives on internal storage (`~/.cache/uv`); `uv cache clean` to
  reclaim space.
- `uv venv` environments are just `.venv/` — nuke with `rm -rf .venv`
  if a sync ever wedges, then `uv sync` again.
