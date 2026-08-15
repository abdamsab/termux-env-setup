#!/data/data/com.termux/files/usr/bin/bash
#
# termux-setup.sh
# ------------------------------------------------------------------
# One-shot setup of a full Termux environment on a fresh install:
# JupyterLab 4.6.3 + Hermes Agent + code-server + opencode + Ollama
# + AcodeX + postgres + proot Ubuntu + dotfiles/themes.
#
# Run on a FRESH Termux from F-Droid (aarch64, Android). Termux from the
# Google Play Store is outdated and unsupported -- do not use it.
#
#   bash ~/termux_setup/termux-setup.sh
#
# Flags (env vars):
#   SETUP_NO_PROOT=1         skip the proot-distro Ubuntu container download
#   SETUP_NO_OLLAMA_PULL=1   skip `ollama pull qwen2.5:0.5b`
#   SETUP_NO_SERVICES=1      skip postgres/sshd/ssh-agent service setup
#   SETUP_SKIP_OPTD=1        skip optional pip utility packages
#   SETUP_NO_TUR_PYPI=1      build all Python modules from source (no TUR prebuilt wheels)
#   SETUP_SCI_STACK=1        also install scipy (TUR apt deps + TUR wheel)
#   SETUP_DRY_RUN=1          verify-only: check env/packages/URLs and print the
#                            planned actions WITHOUT installing anything
#
# Notes:
#   * Network + on-device compilation needed; total 20-60 min on a phone.
#   * Project files and user files (secrets, ~/.env, ~/.pgpass_initial, ~/.ssh,
#     font.ttf) are NOT created or copied -- create them yourself (see README §3).
# ------------------------------------------------------------------

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="$HOME"

say()  { printf '\033[1;36m[*] %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }

# =====================================================================
# Dry-run / verify-only mode (SETUP_DRY_RUN=1)
# Read-only: checks the environment, package names, and URLs, then prints
# the planned actions. Installs NOTHING.
# =====================================================================
if [ -n "${SETUP_DRY_RUN:-}" ]; then
  echo "== SETUP_DRY_RUN: verify-only mode -- nothing will be installed =="
  echo
  echo "Environment:"
  echo "  arch        : $(uname -m)"
  echo "  prefix      : $PREFIX"
  df -h "$PREFIX" 2>/dev/null | awk 'NR==2{printf "  free disk  : %s available\n", $4}'
  free -m 2>/dev/null | awk 'NR==2{printf "  free RAM   : %s MiB\n", $7}'
  command -v pkg >/dev/null 2>&1 && echo "  pkg         : present" || echo "  pkg         : MISSING"
  command -v git >/dev/null 2>&1 && echo "  git         : present" || echo "  git         : MISSING"
  command -v curl >/dev/null 2>&1 && echo "  curl        : present" || echo "  curl        : MISSING"
  command -v python >/dev/null 2>&1 && echo "  python      : $(python -V 2>&1)" || echo "  python      : MISSING"
  echo
  echo "pkg package-name check (local apt cache):"
  PKG_LIST="build-essential clang binutils cmake pkg-config make m4 patch libzmq libffi libcompiler-rt rust llvm lld ndk-sysroot python python-pip python-numpy python-lxml python-psutil python-cryptography python-pillow python-pandas nodejs npm openjdk-17 golang uv postgresql ollama code-server ffmpeg proot-distro runit termux-services termux-am termux-am-socket openssh openssh-sftp-server tmux micro nano neofetch net-tools ripgrep jq gh curl wget unzip dos2unix git fastfetch glibc openssl-glibc bash ncurses python-scipy patchelf"
  miss=0
  for p in $PKG_LIST; do
    if apt-cache show "$p" >/dev/null 2>&1; then printf '  OK   %s\n' "$p"; else printf '  MISS %s\n' "$p"; miss=1; fi
  done
  [ "$miss" -eq 0 ] && echo "  (all pkg names resolve)"
  echo
  echo "External URL check (HEAD):"
  check_url() { code=$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 15 "$2"); echo "  $code  $1"; }
  check_url "opencode .deb     " "https://github.com/Hope2333/opencode-termux/releases/download/Push260803/opencode_1.18.15_aarch64.deb"
  check_url "AcodeX bootstrap  " "https://raw.githubusercontent.com/bajrangCoder/acode-plugin-acodex/main/installServer.sh"
  check_url "hermes-agent repo " "https://github.com/nousresearch/hermes-agent"
  check_url "TUR PyPI index    " "https://termux-user-repository.github.io/pypi/"
  echo
  echo "pip package-name check (PyPI JSON, ~1 min):"
  PIP_LIST="jupyterlab marimo soccerdata seleniumbase edge-tts openai fastapi uvicorn httpx websockets orjson rich requests tqdm PyYAML ruamel.yaml tomlkit croniter python-dotenv PyJWT PyOTP PySocks wrapper-tls-requests tabulate behave pytest pytest-html pytest-xdist pytest-rerunfailures parameterized pdbp pynose mycdp msgspec narwhals tabcompleter annotated-doc fasteners Unidecode sbvirtualdisplay sortedcontainers tenacity termcolor trio trio-websocket socksio wsproto watchfiles uvloop fire docutils scipy"
  pmiss=0
  for p in $PIP_LIST; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://pypi.org/pypi/$p/json" 2>/dev/null)
    if [ "$code" = "200" ]; then printf '  OK   %s\n' "$p"; else printf '  MISS %s\n' "$p"; pmiss=1; fi
  done
  [ "$pmiss" -eq 0 ] && echo "  (all pip names resolve)"
  echo
  echo "Planned actions (what a real run WILL do):"
  echo "  Step 1 : add repos (termux-tur-repo termux-glibc-repo x11-repo root-repo); pkg update; pkg upgrade"
  echo "  Step 2 : termux-setup-storage (tap Allow); write ~/.termux/colors.properties (Base16 Chalk)"
  echo "  Step 3 : pkg install: $(echo $PKG_LIST | wc -w) system packages (toolchain, python, node, postgres, ollama, code-server, ...)"
  echo "  Step 4 : write pip.conf (TUR PyPI extra-index-url); pip install --upgrade pip"
  echo "  Step 5 : pip install core stack (jupyterlab, marimo, soccerdata, seleniumbase, edge-tts, openai, ...)"
  echo "           + optional group (msgspec, narwhals, uvloop, ...) unless SETUP_SKIP_OPTD=1"
  echo "           + scipy when SETUP_SCI_STACK=1"
  echo "  Step 6 : clone hermes-agent @ 2446c8b; pip install -e '.[termux]' -c constraints-termux.txt"
  echo "  Step 7 : download + dpkg -i opencode_1.18.15_aarch64.deb (~39 MB); npm i -g opencode-ai@1.18.15"
  echo "  Step 8 : write ~/.config/code-server/config.yaml"
  echo "  Step 9 : curl AcodeX installServer.sh | bash (installs axs); print Acode linking steps"
  echo "  Step 10: write service run scripts; initdb postgres; sv-enable postgres; sv down sshd ssh-agent"
  echo "  Step 11: ollama serve + ollama pull qwen2.5:0.5b"
  echo "  Step 12: proot-distro install ubuntu"
  echo "  Step 13: write dotfiles (.bashrc, .npmrc, pip.conf, code-server, micro, opencode, marimo)"
  echo "  Step 14: verification summary"
  echo
  echo "NOTE: dry-run proves names/URLs/space only. It cannot simulate on-device"
  echo "compilation or Android-specific quirks -- test a real run on a fresh"
  echo "device or a proot container before trusting it."
  exit 0
fi

# =====================================================================
# Step 0 -- sanity checks
# =====================================================================
say "Step 0/14: sanity checks"
[ "$(uname -m)" = "aarch64" ] || warn "Not aarch64: $(uname -m) (this guide was validated on aarch64)"
[ -d "$HOME_DIR" ] || die "\$HOME is not writable: $HOME_DIR"
command -v pkg >/dev/null 2>&1 || die "'pkg' not found -- is this really Termux?"

# =====================================================================
# Step 1 -- repositories (main / glibc / root / x11 / tur)
# =====================================================================
say "Step 1/14: enabling repositories"
pkg update -y || true
pkg install -y termux-tur-repo termux-glibc-repo x11-repo root-repo
pkg update -y
pkg upgrade -y

# =====================================================================
# Step 2 -- storage permissions + terminal theme
# =====================================================================
say "Step 2/14: storage permissions + theme"
termux-setup-storage || warn "termux-setup-storage needs a manual tap (Allow); re-run it after answering"

mkdir -p "$HOME_DIR/.termux"
cat > "$HOME_DIR/.termux/colors.properties" <<'EOF'
# https://github.com/chriskempson/base16-xresources/blob/master/base16-chalk.dark.256.xresources
# Base16 Chalk
# Scheme: Chris Kempson (http://chriskempson.com)
foreground=#d0d0d0
background=#151515
cursor=#d0d0d0

color0=#151515
color1=#fb9fb1
color2=#acc267
color3=#ddb26f
color4=#6fc2ef
color5=#e1a3ee
color6=#12cfc0
color7=#d0d0d0
color8=#505050
color9=#fb9fb1
color10=#acc267
color11=#ddb26f
color12=#6fc2ef
color13=#e1a3ee
color14=#12cfc0
color15=#f5f5f5
EOF
ok "colors.properties written (Base16 Chalk)"
warn "Manual copy-in: your custom font  ->  $HOME_DIR/.termux/font.ttf"

# =====================================================================
# Step 3 -- system packages
# =====================================================================
say "Step 3/14: installing system packages"
pkg install -y \
  build-essential clang binutils cmake pkg-config make m4 patch \
  libzmq libffi libcompiler-rt rust llvm lld ndk-sysroot \
  python python-pip python-numpy python-lxml python-psutil python-cryptography python-pillow \
  python-pandas nodejs npm openjdk-17 golang uv \
  postgresql ollama code-server ffmpeg proot-distro runit \
  termux-services termux-am termux-am-socket \
  openssh openssh-sftp-server tmux micro nano neofetch net-tools \
  ripgrep jq gh curl wget unzip dos2unix git fastfetch \
  || die "pkg install failed -- check network and re-run"

ok "system packages installed"

# =====================================================================
# Step 4 -- pip config
# =====================================================================
say "Step 4/14: pip configuration"
mkdir -p "$HOME_DIR/.config/pip"
# TUR PyPI index: prebuilt aarch64 Termux wheels (pydantic-core, pillow,
# watchfiles, scipy, ...). pip only uses it when a compatible wheel exists,
# otherwise it falls back to source builds. Set SETUP_NO_TUR_PYPI=1 to force
# full source builds (no prebuilt wheels).
cat > "$HOME_DIR/.config/pip/pip.conf" <<EOF
[global]
disable-pip-version-check = true

[install]
extra-index-url = https://termux-user-repository.github.io/pypi/
EOF
[ -n "${SETUP_NO_TUR_PYPI:-}" ] && sed -i '/extra-index-url/d' "$HOME_DIR/.config/pip/pip.conf"
python -m pip install --upgrade pip

# Optional: patch stale build flag on old clang (clang >= 20 accepts it; harmless guard)
if grep -qs -- '-fno-openmp-implicit-rpath' "$PREFIX"/lib/python*/_sysconfigdata*.py 2>/dev/null; then
  warn "Patching sysconfigdata to drop '-fno-openmp-implicit-rpath' (old-clang workaround)"
  sys="$(ls "$PREFIX"/lib/python*/_sysconfigdata*.py | head -1)"
  sed -i 's|-fno-openmp-implicit-rpath||g' "$sys"
fi

# =====================================================================
# Step 5 -- JupyterLab + marimo + data/AI stack (compiles native wheels)
# =====================================================================
say "Step 5/14: JupyterLab, marimo and the Python data/AI stack"
say "Heavy native modules now come as prebuilt wheels from the TUR PyPI index"
say "(pydantic-core, Pillow, watchfiles, ...). The rest compiles from source:"
say "pyzmq, tornado, rpds-py, argon2-cffi-bindings, debugpy, jiter, uvloop."
say "It can take 10-30 minutes on a phone. Do NOT interrupt."

pip install jupyterlab marimo soccerdata seleniumbase edge-tts openai \
  fastapi uvicorn httpx websockets orjson rich requests tqdm PyYAML \
  ruamel.yaml tomlkit croniter python-dotenv PyJWT PyOTP PySocks \
  wrapper-tls-requests tabulate behave pytest pytest-html pytest-xdist \
  pytest-rerunfailures parameterized pdbp pynose

if [ -z "${SETUP_SKIP_OPTD:-}" ]; then
  pip install mycdp msgspec narwhals tabcompleter annotated-doc fasteners \
    Unidecode sbvirtualdisplay sortedcontainers tenacity termcolor trio \
    trio-websocket socksio wsproto watchfiles uvloop fire docutils
fi

# Optional scientific stack (scipy can NOT be built from source on Termux:
# no Fortran toolchain, main's flang is broken). TUR provides an aarch64
# wheel plus the OpenBLAS runtime via python-scipy.
if [ -n "${SETUP_SCI_STACK:-}" ]; then
  say "SETUP_SCI_STACK=1: installing scipy (TUR apt deps + TUR wheel)"
  pkg install -y python-scipy || warn "pkg install python-scipy failed"
  pip install scipy || warn "pip install scipy failed"
fi

# Runtime workaround for pyzmq (only if import fails: patchelf to link libpython)
if ! python -c "import zmq" >/dev/null 2>&1; then
  warn "import zmq failed -- attempting patchelf workaround"
  pkg install -y patchelf 2>/dev/null || true
  for so in "$PREFIX"/lib/python*/site-packages/zmq/backend/cython/_zmq*.so; do
    [ -e "$so" ] && patchelf --add-needed "libpython$(python -V 2>&1 | sed 's/Python //;s/\.[0-9]*$//').so" "$so" || true
  done
fi

python -c "import jupyterlab, zmq, tornado, marimo; print('JupyterLab', jupyterlab.__version__)" \
  || warn "python import check failed -- inspect errors above"

# =====================================================================
# Step 6 -- Hermes Agent (native Termux build)
# =====================================================================
say "Step 6/14: Hermes Agent (native build)"
# clean stale aliases / pip cache from any previous attempts
unalias hermes 2>/dev/null
sed -i '/alias hermes/d' "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc" 2>/dev/null || true
if [ -n "${SETUP_NO_TUR_PYPI:-}" ]; then
  unset PIP_EXTRA_INDEX_URL          # full source build
else
  export PIP_EXTRA_INDEX_URL="https://termux-user-repository.github.io/pypi/"
  # hermes deps pydantic-core, Pillow, watchfiles now come as prebuilt wheels
fi
python -m pip cache purge || true
hash -r 2>/dev/null || true

if [ ! -d "$HOME_DIR/hermes-agent/.git" ]; then
  # Pin-safe fetch: a plain --depth 1 clone would only contain the current
  # main tip, and the pinned commit may have fallen behind it. Fetch the
  # exact commit instead.
  git clone --filter=blob:none --no-checkout https://github.com/nousresearch/hermes-agent.git "$HOME_DIR/hermes-agent"
  git -C "$HOME_DIR/hermes-agent" fetch --depth 1 origin 2446c8bb6755ff5e6feff4d26e425661edd4019b
  git -C "$HOME_DIR/hermes-agent" -c advice.detachedHead=false checkout 2446c8bb6755ff5e6feff4d26e425661edd4019b
fi
cd "$HOME_DIR/hermes-agent"
# relax Python ceiling if upstream still pins <3.14 (current repo: <3.15)
if grep -q '>=3.11,<3.14' pyproject.toml; then
  sed -i 's/>=3.11,<3.14/>=3.11,<3.15/' pyproject.toml
  ok "patched pyproject.toml Python ceiling to <3.15"
fi
pip install -e '.[termux]' -c constraints-termux.txt
hermes --version || warn "hermes --version failed"

# =====================================================================
# Step 7 -- opencode (glibc .deb from Hope2333/opencode-termux)
# =====================================================================
say "Step 7/14: opencode v1.18.15 (glibc .deb + npm)"
pkg install -y glibc openssl-glibc bash ncurses wget

DEB="$HOME_DIR/opencode_1.18.15_aarch64.deb"
if [ ! -f "$DEB" ]; then
  say "downloading opencode .deb from Push260803 release (~39 MB)"
  wget -q https://github.com/Hope2333/opencode-termux/releases/download/Push260803/opencode_1.18.15_aarch64.deb -O "$DEB" \
    || die "opencode download failed"
fi
SIZE="$(stat -c%s "$DEB" 2>/dev/null || echo 0)"
if [ "$SIZE" -lt 30000000 ]; then
  die "opencode .deb is only ${SIZE} bytes (expected ~39 MB) -- download corrupted; remove it and re-run"
fi
dpkg -i "$DEB"
rm -f "$DEB"
opencode --version || warn "opencode --version failed (run inside a login shell)"

# npm global install as an additional fallback
cat > "$HOME_DIR/.npmrc" <<'EOF'
allow-scripts=opencode-ai
EOF
npm install -g opencode-ai@1.18.15

# =====================================================================
# Step 8 -- code-server config (from TUR, matches current machine)
# =====================================================================
say "Step 8/14: code-server configuration"
mkdir -p "$HOME_DIR/.config/code-server"
cat > "$HOME_DIR/.config/code-server/config.yaml" <<'EOF'
bind-addr: 127.0.0.1:8080
auth: password
password: password
cert: false
EOF
code-server --version

# =====================================================================
# Step 9 -- Acode + AcodeX (axs) integration
# =====================================================================
say "Step 9/14: Acode + AcodeX bridge server (axs)"
warn "Install the Acode app (ad-free F-Droid APK):"
warn "  https://f-droid.org/en/packages/com.foxdebug.acode/"
warn "  (uninstall the Google Play version first if present)"
warn "Then inside Acode:  Settings (gear) > Plugins > Marketplace/All >"
warn "  'AcodeX - Terminal' > Install > restart Acode."

# Install the pre-compiled axs bridge server (bypasses npm compile errors)
say "installing acodeX-server via the official bootstrap script"
curl -sL https://raw.githubusercontent.com/bajrangCoder/acode-plugin-acodex/main/installServer.sh | bash \
  || warn "acodeX-server bootstrap failed -- you can retry manually"

# No project files are created -- create your own (e.g. `mkdir ~/myproject`)!

say "To connect Acode to this server (create your own project folder first):"
say "  1. In Termux:  mkdir ~/myproject   then run  axs   (keep it in the background)"
say "  2. In Acode: three-lines menu > Open Folder > + (Add Path) > Select Folder"
say "  3. In the file picker menu choose 'Termux' > myproject > 'Use this folder' > Allow"
say "  4. Create a file (e.g. hello.py) and open it: Ctrl+Shift+P > 'AcodeX: Open Terminal'"
say "  5. Type  ls  or  python hello.py  in the bottom terminal panel"

# =====================================================================
# Step 10 -- services (postgres up; sshd + ssh-agent registered, down)
# =====================================================================
if [ -z "${SETUP_NO_SERVICES:-}" ]; then
  say "Step 10/14: services (postgres / sshd / ssh-agent)"

  # SVDIR/LOGDIR + runsvdir normally come from profile.d/start-services.sh
  # (interactive/login shells only). Set them explicitly so the script also
  # works from non-interactive shells (ssh, cron, job-scheduler).
  export SVDIR="$PREFIX/var/service"
  export LOGDIR="$PREFIX/var/log"
  if ! pgrep -f runsvdir >/dev/null 2>&1; then
    warn "runsvdir not running -- starting service-daemon"
    command -v service-daemon >/dev/null 2>&1 && (service-daemon start >/dev/null 2>&1 &) || true
    sleep 2
  fi

  mkdir -p "$PREFIX/var/service"

  cat > "$PREFIX/var/service/postgres/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
mkdir -p ~/.postgres
if [ -f "~/.postgres/postgresql.conf" ]; then DATADIR="~/.postgres"; else DATADIR="/data/data/com.termux/files/usr/var/lib/postgresql"; fi
exec postgres -D $DATADIR 2>&1
EOF

  cat > "$PREFIX/var/service/sshd/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec sshd -D -e 2>&1
EOF

  cat > "$PREFIX/var/service/ssh-agent/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh

# Run `sv-enable ssh-agent` and add the following to your bashrc (or
# equivalent) to use ssh-agent:
#   export SSH_AUTH_SOCK="$PREFIX"/var/run/ssh-agent.socket
# After that you can add your key to the agent with `ssh-add`, and
# then make use of the credentials across all terminal sessions

service_agent() {
	# If agent is not turned off before device is rebooted or
	# termux force-stopped, then it fails to start with:
	#   unix_listener: cannot bind to path /data/data/com.termux/files/usr/var/run/ssh-agent.socket: Address already in use
	# Therefore unlink socket file before trying to use it
	if [ -S "$1" ]; then
		unlink "$1"
	fi
	exec ssh-agent -D -a "$1" 2>&1
}

# Allow overriding the service_agent function easily.
if [ -r "${TERMUX__PREFIX:-"${PREFIX}"}"/etc/ssh/start_agent.sh ]; then
	. "${TERMUX__PREFIX:-"${PREFIX}"}"/etc/ssh/start_agent.sh
fi

export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-"${TERMUX__PREFIX:-"${PREFIX}"}/var/run"}"/ssh-agent.socket

service_agent "${SSH_AUTH_SOCK}"
EOF

  chmod +x "$PREFIX"/var/service/{postgres,sshd,ssh-agent}/run

  # initialize postgres data dir if missing
  if [ ! -f "$PREFIX/var/lib/postgresql/PG_VERSION" ]; then
    say "initializing postgres data dir"
    initdb -D "$PREFIX/var/lib/postgresql" || warn "initdb failed"
  fi

  sv-enable postgres || warn "sv-enable postgres failed"
  sv down sshd ssh-agent || true   # leave sshd/ssh-agent registered but stopped (start on demand)
  sv status postgres sshd ssh-agent || true
else
  say "Step 10/14: services skipped (SETUP_NO_SERVICES=1)"
fi

# =====================================================================
# Step 11 -- Ollama + model
# =====================================================================
say "Step 11/14: Ollama"
ollama --version
if [ -z "${SETUP_NO_OLLAMA_PULL:-}" ]; then
  say "pulling qwen2.5:0.5b (~400 MB)"
  ollama serve >/dev/null 2>&1 &
  sleep 3
  ollama pull qwen2.5:0.5b || warn "ollama pull failed -- start 'ollama serve' and pull manually"
  pkill -x ollama 2>/dev/null || true
fi

# =====================================================================
# Step 12 -- proot-distro Ubuntu container
# =====================================================================
if [ -z "${SETUP_NO_PROOT:-}" ]; then
  say "Step 12/14: proot-distro Ubuntu container (large download)"
  proot-distro install ubuntu || warn "proot-distro install ubuntu failed -- retry with: proot-distro install ubuntu"
else
  say "Step 12/14: proot-distro Ubuntu container skipped (SETUP_NO_PROOT=1)"
fi

# =====================================================================
# Step 13 -- dotfiles and configs (no project/user files)
# =====================================================================
say "Step 13/14: dotfiles and configs"

cat > "$HOME_DIR/.bashrc" <<'EOF'

# --- Local AI Agent Configuration (4GB RAM Optimized) ---
# Link agents to local engine
export OPENAI_BASE_URL="http://localhost:11434/v1"
export OPENAI_API_KEY="ollama"
EOF

cat > "$HOME_DIR/.npmrc" <<'EOF'
allow-scripts=opencode-ai
EOF

mkdir -p "$HOME_DIR/.config/micro"
cat > "$HOME_DIR/.config/micro/settings.json" <<'EOF'
{
    "clipboard": "terminal",
    "keymenu": true,
    "mouse": true,
    "colorscheme": "simple"
}
EOF

mkdir -p "$HOME_DIR/.config/opencode"
cat > "$HOME_DIR/.config/opencode/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF

mkdir -p "$HOME_DIR/.config/marimo"
: > "$HOME_DIR/.config/marimo/marimo.toml"

# User files are intentionally NOT written by this script. Create them yourself:
warn "Create your own ~/.env (USERNAME/PASSWORD), ~/.pgpass_initial (PG_PASS),"
warn "~/.ssh keys/authorized_keys, ~/.termux/font.ttf -- see ~/README.md section 3."

# =====================================================================
# Step 14 -- final verification + summary
# =====================================================================
say "Step 14/14: verification"
{
  echo "--- pkg (key) ---"; pkg list-installed 2>/dev/null | rg -i "python|code-server|ollama|postgresql|nodejs|rust|clang|proot" | head -20
  echo "--- python ---";  python -V; pip -V
  echo "--- jupyter ---"; jupyter --version 2>/dev/null | head -4
  echo "--- marimo ---";  marimo --version 2>/dev/null || true
  echo "--- native modules ---"; python -c "import PIL, pydantic, zmq; print('PIL', PIL.__version__, '| pydantic', pydantic.VERSION)" 2>&1 || true
  [ -n "${SETUP_SCI_STACK:-}" ] && echo "--- scipy ---"; [ -n "${SETUP_SCI_STACK:-}" ] && python -c "import scipy; print('scipy', scipy.__version__)" 2>&1 || true
  echo "--- hermes ---";  hermes --version 2>/dev/null || true
  echo "--- code-server ---"; code-server --version 2>/dev/null | head -1
  echo "--- opencode ---"; opencode --version 2>/dev/null || true
  echo "--- axs ---";     command -v axs || echo "axs missing"
  echo "--- ollama ---";  ollama --version 2>/dev/null || true
  echo "--- proot ---";   proot-distro list 2>/dev/null | tail -3
} || true

ok "All done!"
cat <<EOF

Manual follow-ups:
  * READ THIS GUIDE for all steps you must do by hand: ~/README.md
  * termux-setup-storage  -> tap Allow if you missed the prompt
  * CREATE ~/.env (USERNAME/PASSWORD), ~/.pgpass_initial (PG_PASS), ~/.ssh keys,
    and copy ~/.termux/font.ttf from your old device if needed
  * Start services/daemons when ready:
      jupyter lab --no-browser --ip=127.0.0.1 --port=8888
      code-server &
      axs
      ollama serve
      sv start sshd ssh-agent   # if you want ssh enabled
  * Acode app + 'AcodeX - Terminal' plugin must be installed on the Android side
  * opencode needs a login shell for the glibc PATH: run  opencode  from a fresh session
EOF
