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

uv honors `~/.config/pip/pip.conf` (including the TUR PyPI `extra-index-url`
this setup configures), so prebuilt Termux wheels work the same as with pip.

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

- Uses system Python 3.14; set `UV_PYTHON_DOWNLOADS=never` (or pass
  `--no-managed-python`) so uv never tries to fetch a managed CPython.
- **TUR PyPI for pre-built wheels:** `uv pip` reads `pip.conf` (including
  `extra-index-url`), but `uv add` / `uv sync` / `uv run` (project mode)
  do **not**. You must declare the TUR index in one of:
  - Global: `~/.config/uv/uv.toml` (this setup writes it automatically)
  - Per-project: `[[tool.uv.index]]` in `pyproject.toml`
- Cache lives on internal storage (~/.cache/uv); `uv cache clean` to reclaim
  space.
- `uv venv` environments are just `.venv/` — nuke it with `rm -rf .venv` if
  a sync ever wedges, then `uv sync` again.
