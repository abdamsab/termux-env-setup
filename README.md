# termux-env-setup

One-shot setup of a complete Termux environment on a fresh install:
JupyterLab 4.6.3, Hermes Agent, code-server, opencode, Ollama, AcodeX, PostgreSQL,
and a proot Ubuntu container — with the terminal theme and dotfiles.

Two ways to use this:

- **Automatic**: `bash ~/termux_setup/termux-setup.sh` does everything that can be scripted.
- **Manual**: this document lists every step, including the ones **only you** can do.

---

## 0. Before you start (manual — you must do this)

- [ ] Install **Termux from F-Droid**, not the Google Play Store.
      Play Store builds are outdated and unsupported.
      https://f-droid.org/en/packages/com.termux/
- [ ] The device must be **aarch64** (check with `uname -m`).
- [ ] Make sure you have **~2–4 GB free** and a stable network
      (native wheels are compiled on-device; big downloads come from proot/Ollama).
- [ ] Update Termux packages and install `git` first:
      ```
      pkg update -y && pkg install -y git
      ```

---

## 1. Get the script onto the device

```
git clone https://github.com/nousresearch/hermes-agent   # (example only — replace with your repo)
# or transfer via:
#   scp termux-setup.sh user@phone:~/
#   or paste it into `nano ~/termux-setup.sh`
```

Then, optionally, review what it does:

```
sed -n '1,80p' ~/termux_setup/termux-setup.sh
```

---

## 2. Run the setup script

```
bash ~/termux_setup/termux-setup.sh
```

Expected runtime: **20–60 minutes** on a phone. **Do not interrupt the
JupyterLab/Hermes compile step** (Step 5/6) — it builds native wheels
(pyzmq, pydantic-core, jiter, uvloop, Pillow, …).

Optional skips (export before running):

| Flag | Skips |
|---|---|
| `SETUP_NO_PROOT=1` | proot-distro Ubuntu download (~large) |
| `SETUP_NO_OLLAMA_PULL=1` | `ollama pull qwen2.5:0.5b` (~400 MB) |
| `SETUP_NO_SERVICES=1` | postgres/sshd/ssh-agent service setup |
| `SETUP_SKIP_OPTD=1` | extra pip utility packages |
| `SETUP_NO_TUR_PYPI=1` | build all Python modules from source (no prebuilt TUR wheels) |
| `SETUP_SCI_STACK=1` | also install scipy (TUR apt deps + TUR wheel) |
| `SETUP_DRY_RUN=1` | **verify-only**: check env/package names/URLs and print planned actions, install nothing |

The script ends with a verification summary. If a step reports `[!]` warnings,
see the troubleshooting section below.

Before committing to a real run, you can sanity-check everything without
touching your system:

```
SETUP_DRY_RUN=1 bash ~/termux_setup/termux-setup.sh
```

This verifies the architecture, free space, all 58 pkg package names, all 52
pip package names, and the 4 external URLs, then prints what a real run would
do. It installs nothing. Note it cannot simulate on-device compilation — a
full test still needs a spare device or a proot container.

---

## 3. Manual steps (the script CANNOT do these)

### 3.1 Storage permission

The script runs `termux-setup-storage`, but Android will show a **system
permission dialog** that needs a tap:

- [ ] On the phone, tap **Allow** when the storage prompt appears.
- [ ] If you missed it, re-run: `termux-setup-storage`

### 3.2 Secrets and personal files — create/copy these yourself

The script **never touches** your personal files. Create them yourself:

- [ ] `~/.env` — your `USERNAME`/`PASSWORD`
- [ ] `~/.pgpass_initial` — postgres password (`PG_PASS=…`)
- [ ] `~/.ssh/` — your SSH keys and `authorized_keys`
      (keep `chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys`)
- [ ] `~/.termux/font.ttf` — your custom terminal font
      (from `~/.termux/colors.properties`, colors are set by the script;
      copy the font file if you want a custom one)

### 3.3 Acode + AcodeX — download, install, connect

**Step 1 — Install F-Droid (only if you don't have it)**

- [ ] Open https://f-droid.org on the phone, download `F-Droid.apk`, install it,
      and let it add its app repository (or set the repo manually:
      *Settings → Repositories → + → `https://f-droid.org/fdroid/repo`*).
      (F-Droid, not Play Store, for the ad-free builds.)

**Step 2 — Install Acode from F-Droid**

- [ ] In F-Droid, search **Acode**, open the entry, and tap **Install**
      (install the F-Droid build, not the Play Store one).
      Direct link: https://f-droid.org/en/packages/com.foxdebug.acode/
- [ ] If you previously used the Google Play version, **uninstall it first**.

**Step 3 — Install the AcodeX plugin inside Acode**

- [ ] Open Acode → *Settings (gear icon) → Plugins → Marketplace / All*
      → search **"AcodeX - Terminal"** → **Install** → restart Acode.
      (AcodeX is a plugin, not a separate F-Droid app.)

**Step 4 — Start the bridge server in Termux**

- [ ] Create your own project folder (the script creates none) and start `axs`
      in the background:
      ```
      mkdir ~/myproject
      axs
      ```
      Check it is listening: `ss -tlnp | grep 5845` (default AcodeX port).

**Step 5 — Connect Acode to Termux**

- [ ] In Acode: three-lines menu → **Open Folder** → **+ (Add Path)** →
      *Select Folder* → in the picker choose **Termux** → `myproject` →
      **Use this folder** → **Allow**.
- [ ] Create a file (e.g. `hello.py`), open it, then `Ctrl+Shift+P` →
      **"AcodeX: Open Terminal"** and test with `python hello.py`.
- [ ] Stop the bridge when done: `pkill axs`.

### 3.4 Managing services in Termux (start / stop / status)

Two kinds of "services" exist here:

1. **runit services** (postgres, sshd, ssh-agent) — controlled with `sv`, and
   `sv-enable`/`sv-disable` decide whether they auto-start on boot.
2. **Background daemons** (code-server, ollama, jupyter, axs) — just foreground
   processes you start with `&` and stop with `pkill`.

#### runit services (`termux-services`)

Per-service status:

```
sv status postgres            # running? / down?
sv status sshd ssh-agent
ls $PREFIX/var/service        # list every registered service
```

One-time start / stop / restart (does not change autostart):

```
sv start  postgres
sv stop   postgres
sv restart postgres
```

Autostart at boot:

```
sv-enable postgres            # add to boot
sv-disable postgres           # remove from boot
```

| Service | Autostart | Start | Stop | Connect |
|---|---|---|---|---|
| postgres | enabled (script) | `sv start postgres` | `sv stop postgres` | `psql -U root -d postgres` |
| sshd | registered, stopped (`down`) | `sv start sshd` | `sv stop sshd` | `ssh user@127.0.0.1` |
| ssh-agent | registered, stopped (`down`) | `sv start ssh-agent` | `sv stop ssh-agent` | `export SSH_AUTH_SOCK=$PREFIX/var/run/ssh-agent.socket` |

Postgres once-only: set your password and record it in `~/.pgpass_initial`:

```
psql -U root -d postgres -c "ALTER USER root WITH PASSWORD '<your-pass>';"
echo "PG_PASS=<your-pass>" > ~/.pgpass_initial
```

#### Background daemons

Start, then confirm the port is open:

```
code-server &                       # http://127.0.0.1:8080  (password: password)
ollama serve &                      # then: ollama pull qwen2.5:0.5b if skipped
jupyter lab --no-browser --ip=127.0.0.1 --port=8888
axs &                               # AcodeX bridge (Termux <-> Acode)
ss -tlnp                            # list what's listening
```

Stop them:

```
pkill code-server
pkill -x ollama
# jupyter: Ctrl+C in its terminal (or pkill -f "jupyter lab")
pkill axs
```

### 3.5 opencode

- [ ] The `.deb` install is **glibc-based**; run `opencode` from a fresh
      **login shell** so the PATH is set (or `bash -l`). The npm install
      (`opencode-ai@1.18.15`) is the fallback if the `.deb` misbehaves.
- [ ] To auto-start Ollama as your local engine, add to `~/.bashrc` if desired:
      ```
      export OPENAI_BASE_URL="http://localhost:11434/v1"
      export OPENAI_API_KEY="ollama"
      ```
      (already present in the `.bashrc` written by the script)

---

## 4. What the script installs automatically

### 4.1 Repositories

| Repo | Enabled by | Provides |
|---|---|---|
| main | default | core packages |
| TUR | `termux-tur-repo` | code-server, ollama, python-pandas, python-scipy, nodejs-24, … |
| glibc | `termux-glibc-repo` | glibc-base, openssl-glibc (for the opencode `.deb`) |
| root | `root-repo` | root (su) tools |
| x11 | `x11-repo` | GUI/X11 packages |

### 4.2 System packages (`pkg install`)

| Group | Packages |
|---|---|
| Build toolchain | `build-essential` `clang` `binutils` `cmake` `pkg-config` `make` `m4` `patch` `rust` `llvm` `lld` `libcompiler-rt` `ndk-sysroot` |
| Python runtime | `python` `python-pip` `python-numpy` `python-lxml` `python-psutil` `python-cryptography` `python-pillow` `python-pandas` |
| Python messaging | `libzmq` `libffi` |
| Languages / tools | `nodejs` `npm` `openjdk-17` `golang` `uv` |
| Apps / services | `postgresql` `ollama` `code-server` `ffmpeg` `proot-distro` `runit` `termux-services` `termux-am` `termux-am-socket` |
| SSH | `openssh` `openssh-sftp-server` |
| Terminal / utilities | `tmux` `micro` `nano` `neofetch` `net-tools` `ripgrep` `jq` `gh` `curl` `wget` `unzip` `dos2unix` `git` `fastfetch` |
| opencode deps (Step 7) | `glibc` `openssl-glibc` `bash` `ncurses` `wget` |
| Optional (`SETUP_SCI_STACK=1`) | `python-scipy` |
| Fallback (zmq import broken) | `patchelf` |

### 4.3 pip packages

| Group | Packages |
|---|---|
| Core data/AI (Step 5) | `jupyterlab` `marimo` `soccerdata` `seleniumbase` `edge-tts` `openai` `fastapi` `uvicorn` |
| HTTP / util | `httpx` `websockets` `orjson` `rich` `requests` `tqdm` `PyYAML` `ruamel.yaml` `tomlkit` `croniter` `python-dotenv` `PyJWT` `PyOTP` `PySocks` `wrapper-tls-requests` `tabulate` |
| Testing | `behave` `pytest` `pytest-html` `pytest-xdist` `pytest-rerunfailures` `parameterized` `pdbp` `pynose` |
| Optional (`SETUP_SKIP_OPTD` off) | `mycdp` `msgspec` `narwhals` `tabcompleter` `annotated-doc` `fasteners` `Unidecode` `sbvirtualdisplay` `sortedcontainers` `tenacity` `termcolor` `trio` `trio-websocket` `socksio` `wsproto` `watchfiles` `uvloop` `fire` `docutils` |
| Optional (`SETUP_SCI_STACK=1`) | `scipy` |

TUR PyPI `extra-index-url` is configured so `pydantic-core`, `pillow`,
`watchfiles`, `scipy`, … install as prebuilt wheels (see §4b).

### 4.4 Standalone installs / downloads

| Item | Source | Result |
|---|---|---|
| Hermes Agent | `git clone nousresearch/hermes-agent` @ `2446c8b` | `~/hermes-agent` editable install `pip install -e '.[termux]' -c constraints-termux.txt` |
| opencode | `~/opencode_1.18.15_aarch64.deb` (local copy or Push260803 release, ~39 MB) + npm `opencode-ai@1.18.15` | `/usr/bin/opencode` + npm global |
| AcodeX server | `curl …/installServer.sh \| bash` (official bootstrap) | `axs` in `$PREFIX/bin` (no example project — create your own) |
| Ollama model | `ollama pull qwen2.5:0.5b` | local LLM (~400 MB) |
| Ubuntu container | `proot-distro install ubuntu` | proot Ubuntu |

### 4.5 Services (runit/termux-services)

| Service | State | Run script |
|---|---|---|
| postgres | **running** (autostart) | `$PREFIX/var/service/postgres/run` → `postgres -D $PREFIX/var/lib/postgresql` |
| sshd | registered, **stopped** (`down`) | `$PREFIX/var/service/sshd/run` → `sshd -D -e` |
| ssh-agent | registered, **stopped** (`down`) | `$PREFIX/var/service/ssh-agent/run` → `ssh-agent -D -a` |

postgres data dir is initialized with `initdb -D $PREFIX/var/lib/postgresql`
if `PG_VERSION` is missing.

### 4.6 Dotfiles / configs written

| Path | Contents |
|---|---|
| `~/.termux/colors.properties` | Base16 Chalk theme (font is manual, §3.2) |
| `~/.bashrc` | OPENAI base-url + api-key exports for local Ollama |
| `~/.npmrc` | `allow-scripts=opencode-ai` |
| `~/.config/pip/pip.conf` | `disable-pip-version-check` + TUR PyPI `extra-index-url` |
| `~/.config/code-server/config.yaml` | `127.0.0.1:8080`, password `password`, cert false |
| `~/.config/micro/settings.json` | clipboard/keymenu/mouse/simple colorscheme |
| `~/.config/opencode/opencode.jsonc` | empty schema config |
| `~/.config/marimo/marimo.toml` | empty |
| `~/.env` | **not written** — create yourself (§3.2) |
| `~/.pgpass_initial` | **not written** — create yourself (§3.2) |
| `~/.ssh/` | **not created** — create keys yourself (§3.2) |

### 4.7 Flag-gated extras (see §2)

- `SETUP_SCI_STACK=1` → `python-scipy` + `scipy`
- `SETUP_SKIP_OPTD=1` → skips the optional pip group
- `SETUP_NO_TUR_PYPI=1` → all source builds
- `SETUP_NO_PROOT` / `SETUP_NO_OLLAMA_PULL` / `SETUP_NO_SERVICES` → skip those steps

---

## 4b. Precompiled wheels & modules that won't build on Termux

Many Python packages with C/Rust extensions either **fail** to compile on-device
or take tens of minutes on a phone. Termux has three sources of **precompiled**
builds — the script already uses all three:

1. **Termux main repo** (`.deb`s): `python-numpy`, `python-lxml`,
   `python-psutil`, `python-cryptography`, `python-pillow` (plus
   `python-cffi`, pulled in as a dependency).
2. **TUR apt repo** (`termux-tur-repo`): prebuilt `.deb`s for packages that
   can't be pip-built at all, e.g. `python-scipy` (needs a Fortran toolchain —
   Termux main's `flang` is broken) and `python-pandas`. Also code-server,
   ollama, old Python/Node versions.
3. **TUR PyPI index** — prebuilt aarch64 Termux **wheels**, added to your
   pip config as the `extra-index-url`. pip only uses it when a compatible
   wheel exists (falls back to source builds otherwise), so it is safe.

```ini
# ~/.config/pip/pip.conf  (already written by the script)
[global]
disable-pip-version-check = true

[install]
extra-index-url = https://termux-user-repository.github.io/pypi/
```

Wheels currently hosted there (27):

```
aioquic        brotli          cmake           cryptography    grpcio
llvmlite       lxml            maturin         mitmproxy-rs    mitmproxy-wireguard
ninja          numba           numpy           onnxruntime     pandas
pillow         playwright      polars          pycairo         pycryptodomex
pydantic-core  scikit-learn    scipy           tflite-runtime  tiktoken
tokenizers     watchfiles
```

Which of these can't realistically build on a phone, and how to get them:

| Module | Why source builds fail/are impractical | Get it from |
|---|---|---|
| `scipy` | Fortran + LAPACK/BLAS; no working Fortran compiler | TUR apt `python-scipy` + TUR wheel (script: `SETUP_SCI_STACK=1`) |
| `pydantic-core` | Rust; large, slow compile — **hermes dependency** | TUR wheel (cp314 available; used by default) |
| `pillow` | Needs jpeg/zlib headers; slow C build — **hermes dependency** | main repo `python-pillow` or TUR wheel |
| `watchfiles` | Rust — **hermes dependency** | TUR wheel |
| `onnxruntime` | Huge C++/ML pipeline; not buildable on-device | TUR wheel (only cp≤312 — on py3.14 pip falls back to source; use proot Ubuntu instead) |
| `numba` / `llvmlite` | Requires exact LLVM version | TUR wheels |
| `polars` | Massive Rust build | TUR wheel |
| `playwright` | Rust + browser binaries | TUR wheel + `playwright install` |
| `tiktoken` / `tokenizers` | Rust | TUR wheels |

Notes:

- The `science` repo was **merged into main** years ago — there is no separate
  science repo anymore.
- TUR has extra apt components not enabled by default: `tur-hacking`,
  `tur-continuous` (very long compiles, e.g. Chromium), `tur-multilib`.
- `SETUP_NO_TUR_PYPI=1` disables the index so everything compiles from source
  (needed only for a fully source-built environment).

---

## 5. Verification

Run these and check nothing is missing:

```
jupyter --version | head -4        # JupyterLab 4.6.3
marimo --version
python -c "import PIL, pydantic, zmq"   # native modules import cleanly
hermes --version
code-server --version | head -1
opencode --version                 # in a login shell
axs                                # should start, not 'command not found'
ollama --version
proot-distro list
sv status postgres sshd ssh-agent
# with SETUP_SCI_STACK=1:
python -c "import scipy; print(scipy.__version__)"
```

---

## 6. Troubleshooting

| Problem | Fix |
|---|---|
| `import zmq` / Jupyter import errors | Script auto-runs the patchelf workaround; retry `pip install --force-reinstall pyzmq` then import again |
| Hermes build fails on Python ceiling | The script patches `<3.14`→`<3.15` if upstream regresses; verify `grep requires-python ~/hermes-agent/pyproject.toml` |
| opencode: `GLIBC`/command not found | Use a login shell (`bash -l`) or the npm fallback `opencode-ai` |
| `sv-enable` not found | `pkg install runit termux-services` (script does this) |
| `termux-setup-storage` "denied" | Tap Allow on the dialog; re-run the command |
| Acode can't see Termux folder | Server not running → run `axs`; or re-do the folder pick → Termux → Allow |
| `ollama pull` failed | `ollama serve &`, wait 3s, pull again |
| Slow/stuck compile | Normal for on-device wheels; ensure charger + enough free space |
| `pip install onnxruntime`/`numba` tries a source build | No cp314 TUR wheel yet; TUR wheel only helps if the Python version matches. Use the proot Ubuntu container instead |

---

*Setup guide for Termux (F-Droid, aarch64).*
