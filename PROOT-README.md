# proot-env-setup

One-shot setup of a full proot Ubuntu environment inside Termux:
JupyterLab 4.6.3, Hermes Agent, code-server, opencode, PostgreSQL,
SSH, and the complete Python data/AI stack — with dotfiles and service
management.

This script runs **inside** a `proot-distro login ubuntu` container.
Ollama, AcodeX, and the proot container itself are set up by the
companion [termux-setup.sh](termux-setup.sh) on the Termux host.

Two ways to use this:

- **Automatic**: `bash ~/termux_setup/proot-setup.sh` does everything that can be scripted.
- **Manual**: this document lists every step, including the ones **only you** can do.

---

## 0. Before you start (manual — you must do this)

- [ ] You must have **Termux from F-Droid** installed (aarch64, Android).
      Play Store builds are outdated and unsupported.
      https://f-droid.org/en/packages/com.termux/
- [ ] Run `bash ~/termux_setup/termux-setup.sh` in Termux first —
      it installs the proot-distro Ubuntu container and Ollama.
- [ ] The device must be **aarch64** (check with `uname -m`).
- [ ] Make sure you have **~2–4 GB free** and a stable network
      (native wheels are compiled on-device; pip packages are large).
- [ ] Enter the proot container:
      ```
      proot-distro login ubuntu
      ```

---

## 1. Get the script into the proot container

The proot-setup.sh lives alongside termux-setup.sh in the same repo.
Since proot-distro binds the Termux `$HOME` into `/root` by default,
the script is already accessible inside proot:

```
cd ~/termux_setup
ls proot-setup.sh
```

If you used `--isolated` mode (no shared home), copy it in:

```
proot-distro copy ubuntu ~/termux_setup/proot-setup.sh /root/
```

---

## 2. Run the setup script

```
proot-distro login ubuntu
bash ~/termux_setup/proot-setup.sh
```

Expected runtime: **20–60 minutes** on a phone. **Do not interrupt the
JupyterLab/Hermes compile step** (Step 4/5) — it builds native wheels.

Optional flags (export before running):

| Flag | Skips |
|---|---|
| `SETUP_NO_SERVICES=1` | postgres/ssh service setup |
| `SETUP_NO_SSH=1` | openssh-server setup only |
| `SETUP_SKIP_OPTD=1` | extra pip utility packages |
| `SETUP_SCI_STACK=1` | also install scipy |
| `SETUP_DRY_RUN=1` | **verify-only**: check env/packages/URLs, install nothing |

The script ends with a verification summary. If a step reports `[!]`
warnings, see the troubleshooting section below.

Before committing to a real run, you can sanity-check everything without
touching the container:

```
SETUP_DRY_RUN=1 bash ~/termux_setup/proot-setup.sh
```

This verifies the architecture, all apt package names, all pip package
names, and the external URLs, then prints what a real run would do.
It installs nothing.

---

## 3. Manual steps (the script CANNOT do these)

### 3.1 Secrets and personal files — create/copy these yourself

The script **never touches** your personal files. Create them yourself:

- [ ] `~/.env` — your `USERNAME`/`PASSWORD`
- [ ] `~/.pgpass_initial` — postgres password (`PG_PASS=…`)
- [ ] `~/.ssh/` — your SSH keys and `authorized_keys`
      (keep `chmod 700 ~/.ssh`, `chmod 600 ~/.ssh/authorized_keys`)

### 3.2 Ollama — runs on the Termux host, proot connects via localhost

Ollama is **not installed** inside proot. It runs natively on the
Termux host and proot reaches it through the shared network:

```
# From Termux (start ollama if not running):
ollama serve &

# From inside proot:
curl http://localhost:11434/api/tags    # verify it's reachable
```

The script writes these to `~/.bashrc` inside proot:

```bash
export OPENAI_BASE_URL="http://localhost:11434/v1"
export OPENAI_API_KEY="ollama"
```

Apps like Hermes Agent, opencode, and any OpenAI-compatible client
will automatically use the local Ollama engine.

### 3.3 AcodeX (axs) — Termux-side editor, not in proot

AcodeX is an Android editor (Acode app) that connects to the Termux
host. It is set up by `termux-setup.sh`, not proot-setup.sh.

See the [termux README §3.3](README.md#33-acode--acodex--download-install-connect)
for the full Acode + AcodeX setup guide.

### 3.4 Managing services in proot (start / stop / status)

There is **no systemd** in proot. Services are managed with:

1. The `svcs` wrapper script (installed by proot-setup.sh)
2. Direct commands (`pg_ctlcluster`, `/usr/sbin/sshd`)

#### The svcs wrapper

```
svcs postgres start          # start PostgreSQL
svcs postgres stop           # stop PostgreSQL
svcs postgres status         # check if running
svcs postgres restart        # stop + start

svcs ssh start               # start sshd on port 2222
svcs ssh stop
svcs ssh status

svcs all start               # start everything
svcs all status              # check everything
```

#### PostgreSQL — manual control

| Action | Command |
|---|---|
| Start | `svcs postgres start` |
| Stop | `svcs postgres stop` |
| Status | `svcs postgres status` |
| Logs | `tail /var/log/postgresql/*.log` |
| Connect | `psql -U postgres` |
| List clusters | `pg_lsclusters` |

**Set your password** (once):

```bash
psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'your-password';"
```

**Create a new database:**

```bash
createdb mydb
psql mydb
```

**Allow remote connections** (from Termux host):

```bash
# Edit postgresql.conf:
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" \
  /etc/postgresql/*/main/postgresql.conf

# Edit pg_hba.conf (allow local network):
echo "host all all 127.0.0.1/32 md5" >> /etc/postgresql/*/main/pg_hba.conf
echo "host all all ::1/128 md5" >> /etc/postgresql/*/main/pg_hba.conf

# Restart:
svcs postgres restart
```

**Connect from Termux:**

```bash
# In Termux (proot must be running):
PGPASSWORD='your-password' psql -h 127.0.0.1 -U postgres
```

#### SSH — manual control

| Action | Command |
|---|---|
| Start | `svcs ssh start` |
| Stop | `svcs ssh stop` |
| Status | `svcs ssh status` |
| Connect locally | `ssh root@127.0.0.1 -p 2222` |

**SSH uses port 2222** (not 22) to avoid conflict with Termux sshd.

**Configure public-key auth:**

```bash
# In proot: add your public key
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... you@device" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

**Connect from Termux:**

```bash
ssh root@127.0.0.1 -p 2222
```

### 3.5 Background daemons

Start these manually (they don't auto-start):

```
svcs postgres start                       # 127.0.0.1:5432
jupyter lab --no-browser --port=8888      # http://127.0.0.1:8888
code-server &                             # http://127.0.0.1:8080
marimo edit --port=2718                   # http://127.0.0.1:2718
```

**Access from Android browser:**

```bash
# From inside proot:
jupyter lab --no-browser --port=8888
# Open Android browser: http://localhost:8888
```

**Stop them:**

```bash
svcs postgres stop
pkill -f "jupyter lab"
pkill code-server
pkill -f "marimo edit"
```

**Check what's listening:**

```bash
ss -tlnp
```

### 3.6 opencode

opencode is installed via npm (no `.deb` or glibc shim needed —
proot Ubuntu has native glibc). Just run it:

```
opencode --version
opencode
```

It automatically uses the Ollama backend via the `OPENAI_BASE_URL`
set in `~/.bashrc`.

---

## 4. What the script installs automatically

### 4.1 System packages (`apt install`)

systemd is **held** (`apt-mark hold`) before any package installs to
prevent it from being pulled in as a dependency — systemd cannot run
in proot.

| Group | Packages |
|---|---|
| Build toolchain | `build-essential` `clang` `binutils` `cmake` `pkg-config` `make` `m4` `patch` `rustc` `cargo` `llvm-dev` `lld` `gfortran` |
| Python runtime | `python3` `python3-pip` `python3-dev` `python3-venv` |
| Python libs | `libzmq3-dev` `libffi-dev` `libssl-dev` `libjpeg-dev` `zlib1g-dev` `libxml2-dev` `libxslt1-dev` `libpq-dev` `libncurses-dev` |
| Languages / tools | `nodejs` `npm` `openjdk-17-jdk` `golang-go` |
| Database | `postgresql` `postgresql-common` |
| Media | `ffmpeg` |
| SSH | `openssh-server` `openssh-sftp-server` |
| Terminal / utilities | `tmux` `micro` `nano` `neofetch` `net-tools` `ripgrep` `jq` `curl` `wget` `unzip` `dos2unix` `git` `patchelf` `unixodbc` `software-properties-common` |
| Standalone tools | `gh` (via apt repo), `code-server` (via Microsoft script), `uv` (via astral script) |
| Optional (`SETUP_SCI_STACK=1`) | `gfortran` (already installed), `scipy` (via pip) |

### 4.2 pip packages

| Group | Packages |
|---|---|
| Core data/AI (Step 4) | `jupyterlab` `marimo` `soccerdata` `seleniumbase` `edge-tts` `openai` `fastapi` `uvicorn` |
| Database drivers (Step 4) | `sqlalchemy` `PyMySQL` `psycopg2-binary` `pyodbc` |
| Notebook LSP (Step 4) | `jupyterlab-lsp` `python-lsp-server` — in-cell intellisense in JupyterLab |
| HTTP / util | `httpx` `websockets` `orjson` `rich` `requests` `tqdm` `PyYAML` `ruamel.yaml` `tomlkit` `croniter` `python-dotenv` `PyJWT` `PyOTP` `PySocks` `wrapper-tls-requests` `tabulate` |
| Testing | `behave` `pytest` `pytest-html` `pytest-xdist` `pytest-rerunfailures` `parameterized` `pdbp` `pynose` |
| Optional (`SETUP_SKIP_OPTD` off) | `mycdp` `msgspec` `narwhals` `tabcompleter` `annotated-doc` `fasteners` `Unidecode` `sbvirtualdisplay` `sortedcontainers` `tenacity` `termcolor` `trio` `trio-websocket` `socksio` `wsproto` `watchfiles` `uvloop` `fire` `docutils` |
| Optional (`SETUP_SCI_STACK=1`) | `scipy` |

All packages install from **standard PyPI** — no TUR index or prebuilt
wheel source needed. Ubuntu's native glibc and full toolchain mean
everything compiles cleanly from source or uses upstream wheels.

### 4.3 Standalone installs

| Item | Source | Result |
|---|---|---|
| Hermes Agent | `git clone nousresearch/hermes-agent` @ `2446c8b` | `~/hermes-agent` editable install (`pip install -e .`) |
| opencode | `npm install -g opencode-ai@1.18.15` | npm global binary |
| code-server | `curl -fsSL https://code-server.dev/install.sh \| sh` | system binary |
| gh (GitHub CLI) | GitHub apt repo | system binary |
| uv | `curl -LsSf https://astral.sh/uv/install.sh \| sh` | `~/.local/bin/uv` |

### 4.4 Services (manual, no systemd)

| Service | State | Management |
|---|---|---|
| postgres | installed, **running** after setup | `svcs postgres start\|stop\|status` or `pg_ctlcluster <ver> main start` |
| sshd | installed, **running** after setup (port 2222) | `svcs ssh start\|stop\|status` or `/usr/sbin/sshd -D -e -p 2222 &` |

PostgreSQL cluster is created with `pg_createcluster` during install
and started with `pg_ctlcluster`. SSH host keys are generated with
`ssh-keygen -A`. PAM is disabled (`UsePAM no`) because real PAM
modules don't work in proot.

### 4.5 Dotfiles / configs written

| Path | Contents |
|---|---|
| `~/.bashrc` | OPENAI base-url + api-key exports for local Ollama, proot prompt, PATH/LANG |
| `~/.npmrc` | `allow-scripts=opencode-ai` |
| `~/.config/pip/pip.conf` | `disable-pip-version-check` (standard PyPI only, no TUR) |
| `~/.config/code-server/config.yaml` | `127.0.0.1:8080`, password `password`, cert false |
| `~/.config/micro/settings.json` | clipboard/keymenu/mouse/simple colorscheme |
| `~/.config/opencode/opencode.jsonc` | empty schema config |
| `~/.config/marimo/marimo.toml` | empty |
| `~/.jupyter/jupyter_lab_config.py` | drops the "Skipped non-installed server(s)" log line, keeps autodetect on for pylsp |
| `/etc/resolv.conf` | DNS: 8.8.8.8, 8.8.4.4 (proot doesn't inherit host resolv.conf) |
| `/etc/machine-id` | generated (some programs check this) |
| `/usr/local/bin/svcs` | service control wrapper (postgres/ssh/all) |
| `~/.env` | **not written** — create yourself (§3.1) |
| `~/.pgpass_initial` | **not written** — create yourself (§3.1) |
| `~/.ssh/` | **not created** — create keys yourself (§3.1) |

### 4.6 Flag-gated extras (see §2)

- `SETUP_SCI_STACK=1` → `scipy` (gfortran + pip wheel, builds natively)
- `SETUP_SKIP_OPTD=1` → skips the optional pip group
- `SETUP_NO_SERVICES=1` → skips postgres/ssh service setup
- `SETUP_NO_SSH=1` → skips openssh-server configuration

---

## 4b. Why proot Ubuntu instead of Termux-only?

Termux is an Android app — it has a **non-standard Linux userspace**
(no glibc, custom Bionic libc, limited /proc, no systemd). This means:

| Problem in Termux | Proot Ubuntu advantage |
|---|---|
| Many pip packages fail to compile (no Fortran, broken flang) | Full glibc + gfortran + build-essential: everything compiles |
| TUR prebuilt wheels lag behind PyPI releases | Standard aarch64 glibc wheels from PyPI work directly |
| scipy, polars, onnxruntime, numba require special handling | Just `pip install scipy` — done |
| No real init system (runit, not systemd) | Services use `pg_ctlcluster` / `svcs` wrapper directly |
| PostgreSQL needs TUR hacks | PostgreSQL from Ubuntu repos, starts normally |
| Python ceiling patches and constraints files | Standard Python from apt, no patches needed |

The two environments complement each other:

- **Termux** handles Android-native apps: Ollama (GPU access), code-server
  (browser IDE), opencode (TUI agent), AcodeX (editor bridge).
- **Proot Ubuntu** handles the Linux server stack: PostgreSQL, SSH, Python
  (all of it), JupyterLab, Hermes Agent, the full data/AI pipeline.

They communicate through **localhost** — Ollama's API at `localhost:11434`,
PostgreSQL at `localhost:5432`, JupyterLab at `localhost:8888`.

---

## 5. Verification

Run these and check nothing is missing:

```bash
# System
cat /etc/os-release | grep PRETTY_NAME
python3 -V; pip -V

# Python stack
jupyter --version | head -4
marimo --version
python3 -c "import PIL, pydantic, zmq"
python3 -c "import sqlalchemy, pymysql, psycopg2, pyodbc"
pylsp --version

# Hermes
hermes --version

# Tools
code-server --version | head -1
opencode --version
gh --version | head -1
uv --version

# Services
pg_isready                    # PostgreSQL running?
pgrep -x sshd                 # sshd running?
svcs all status               # both services

# SciPy (if SETUP_SCI_STACK=1)
python3 -c "import scipy; print(scipy.__version__)"

# Ollama connectivity (from inside proot)
curl -s http://localhost:11434/api/tags | head
```

---

## 6. Troubleshooting

| Problem | Fix |
|---|---|
| `apt` hangs or "held broken packages" | systemd was pulled in and broke dpkg. Run: `apt autoremove -y && apt --fix-broken install -y && apt-mark hold systemd libsystemd-shared systemd-timesyncd` |
| `E: Unable to locate package` | Run `apt update` first, or the package doesn't exist in Ubuntu repos. Check: `apt-cache search <name>` |
| PostgreSQL "cluster already exists" | Normal — script detects existing clusters. To reset: `pg_dropcluster <ver> main` then re-run, or `svcs postgres restart` |
| PostgreSQL won't start (shared memory) | proot-distro binds `/dev/shm` automatically. Check: `ls -la /dev/shm`. If still failing: `pg_ctlcluster <ver> main start -o "-c shared_preload_libraries=''` |
| `sshd: Permission denied` or won't start | PAM is disabled in config. Ensure host keys exist: `ssh-keygen -A`. Check: `/usr/sbin/sshd -D -e -p 2222` (foreground for debugging) |
| `import zmq` errors | Should not happen on Ubuntu (native glibc). If it does: `pip install --force-reinstall pyzmq` |
| Hermes build fails on Python ceiling | Script patches `<3.14`→`<3.15` if needed. Verify: `grep requires-python ~/hermes-agent/pyproject.toml` |
| Ollama unreachable from proot | Make sure `ollama serve` is running **in Termux**, not in proot. Test: `curl http://localhost:11434/api/tags` |
| `opencode: command not found` | Run `hash -r` or start a new shell. npm global bin may need PATH: `export PATH="$HOME/.npm-global/bin:$PATH"` |
| Slow/stuck compile | Normal for on-device compilation. Ensure charger + enough free space. On a phone: 10-30 min for the Python stack |
| `No PostgreSQL cluster` | Script creates one automatically. If missing: `pg_createcluster 16 main --start` |
| DNS not resolving | Check: `cat /etc/resolv.conf`. Should have `nameserver 8.8.8.8`. Fix: `echo "nameserver 8.8.8.8" > /etc/resolv.conf` |
| `nested proot detected` | You ran this script inside another proot instance. Exit to Termux first: `exit`, then `proot-distro login ubuntu` |
| Port already in use | Check what's using it: `ss -tlnp \| grep :PORT`. Kill or use a different port |
| `[ServerApp] Skipped non-installed server(s)` | Expected — jupyter-lsp scans for ~19 known language servers; only `python-lsp-server` is installed. The log line is dropped by `~/.jupyter/jupyter_lab_config.py`. To add another language server: `pip install <server>` |
| No LSP completions in code cell | Install `jupyterlab-lsp` (script does) → restart JupyterLab → open notebook → click the **rocket/LSP icon** in the right sidebar → toggle **Enable** |

---

*Setup guide for proot Ubuntu inside Termux (F-Droid, aarch64).*
