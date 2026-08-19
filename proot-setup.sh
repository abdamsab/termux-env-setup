#!/bin/bash
#
# proot-setup.sh
# ------------------------------------------------------------------
# One-shot setup of a full proot Ubuntu environment:
# JupyterLab 4.6.3 + Hermes Agent + code-server + opencode + postgres
# + ssh + dotfiles + Python data/AI stack.
#
# Run INSIDE a proot-distro Ubuntu container:
#   proot-distro login ubuntu
#   bash ~/termux_setup/proot-setup.sh
#
# Ollama runs on the Termux host; proot connects via localhost:11434.
# AcodeX (axs) is a Termux-side editor; install from termux-setup.sh.
# proot-distro install ubuntu is a Termux-side step; install from
# termux-setup.sh.
#
# Flags (env vars):
#   SETUP_NO_SERVICES=1      skip postgres/ssh service setup
#   SETUP_SKIP_OPTD=1        skip optional pip utility packages
#   SETUP_SCI_STACK=1        also install scipy (apt gfortran + pip wheel)
#   SETUP_NO_SSH=1           skip openssh-server setup
#   SETUP_DRY_RUN=1          verify-only: check env/packages/URLs and print the
#                            planned actions WITHOUT installing anything
#
# Notes:
#   * Network + on-device compilation needed; total 20-60 min on a phone.
#   * Project files and user files (secrets, ~/.env, ~/.pgpass_initial, ~/.ssh)
#     are NOT created or copied -- create them yourself (see README).
#   * systemd is intentionally held/blocked; services are managed manually.
# ------------------------------------------------------------------

PREFIX="${PREFIX:-/usr}"
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
  echo "  home        : $HOME_DIR"
  echo "  user        : $(id -un) (uid=$(id -u))"
  df -h / 2>/dev/null | awk 'NR==2{printf "  free disk  : %s available\n", $4}'
  free -m 2>/dev/null | awk 'NR==2{printf "  free RAM   : %s MiB\n", $7}'
  cat /etc/os-release 2>/dev/null | awk -F= '/^PRETTY_NAME/{printf "  distro     : %s\n", $2}'
  command -v apt >/dev/null 2>&1 && echo "  apt         : present" || echo "  apt         : MISSING"
  command -v git >/dev/null 2>&1 && echo "  git         : present" || echo "  git         : MISSING"
  command -v curl >/dev/null 2>&1 && echo "  curl        : present" || echo "  curl        : MISSING"
  command -v python3 >/dev/null 2>&1 && echo "  python3     : $(python3 -V 2>&1)" || echo "  python3     : MISSING"
  echo
  echo "apt package-name check (remote search):"
  PKG_LIST="build-essential clang binutils cmake pkg-config make m4 patch
libzmq3-dev libffi-dev libssl-dev libjpeg-dev zlib1g-dev
libxml2-dev libxslt1-dev libpq-dev libncurses-dev
python3 python3-pip python3-dev python3-venv
rustc cargo llvm-dev lld nodejs npm
openjdk-17-jdk golang-go postgresql postgresql-common
ffmpeg openssh-server openssh-sftp-server
tmux micro nano neofetch net-tools
ripgrep jq curl wget unzip dos2unix git patchelf unixodbc
software-properties-common gfortran"
  miss=0
  for p in $PKG_LIST; do
    if apt-cache show "$p" >/dev/null 2>&1; then printf '  OK   %s\n' "$p"; else printf '  MISS %s\n' "$p"; miss=1; fi
  done
  [ "$miss" -eq 0 ] && echo "  (all apt names resolve)"
  echo
  echo "External URL check (HEAD):"
  check_url() { code=$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 15 "$2"); echo "  $code  $1"; }
  check_url "hermes-agent repo " "https://github.com/nousresearch/hermes-agent"
  check_url "code-server       " "https://code-server.dev/install.sh"
  check_url "GitHub CLI        " "https://cli.github.com/packages/githubcli-archive-keyring.gpg"
  check_url "uv installer      " "https://astral.sh/uv/install.sh"
  echo
  echo "pip package-name check (PyPI JSON, ~1 min):"
  PIP_LIST="jupyterlab marimo soccerdata seleniumbase edge-tts openai fastapi uvicorn httpx websockets orjson rich requests tqdm PyYAML ruamel.yaml tomlkit croniter python-dotenv PyJWT PyOTP PySocks wrapper-tls-requests tabulate behave pytest pytest-html pytest-xdist pytest-rerunfailures parameterized pdbp pynose sqlalchemy PyMySQL psycopg2-binary pyodbc jupyterlab-lsp python-lsp-server mycdp msgspec narwhals tabcompleter annotated-doc fasteners Unidecode sbvirtualdisplay sortedcontainers tenacity termcolor trio trio-websocket socksio wsproto watchfiles uvloop fire docutils scipy"
  pmiss=0
  for p in $PIP_LIST; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://pypi.org/pypi/$p/json" 2>/dev/null)
    if [ "$code" = "200" ]; then printf '  OK   %s\n' "$p"; else printf '  MISS %s\n' "$p"; pmiss=1; fi
  done
  [ "$pmiss" -eq 0 ] && echo "  (all pip names resolve)"
  echo
  echo "Planned actions (what a real run WILL do):"
  echo "  Step 1 : hold systemd; apt update && apt upgrade"
  echo "  Step 2 : apt install: $(echo $PKG_LIST | wc -w) system packages"
  echo "           + gh (GitHub CLI via apt repo)"
  echo "           + code-server (via Microsoft install script)"
  echo "           + uv (via astral install script)"
  echo "  Step 3 : pip install --upgrade pip; write pip.conf"
  echo "  Step 4 : pip install core stack (jupyterlab, marimo, soccerdata, seleniumbase, edge-tts, openai, ...)"
  echo "           + optional group (msgspec, narwhals, uvloop, ...) unless SETUP_SKIP_OPTD=1"
  echo "           + scipy when SETUP_SCI_STACK=1"
  echo "  Step 5 : clone hermes-agent @ 2446c8b; pip install -e ."
  echo "  Step 6 : npm install -g opencode-ai@1.18.15"
  echo "  Step 7 : write ~/.config/code-server/config.yaml"
  echo "  Step 8 : setup postgres (policy-rc.d trick + initdb + start)"
  echo "           + setup ssh (ssh-keygen -A + UsePAM no)"
  echo "           + write /usr/local/bin/svcs wrapper"
  echo "  Step 9 : write dotfiles (.bashrc, .npmrc, resolv.conf, machine-id, configs)"
  echo "  Step 10: verification summary"
  echo
  echo "NOTE: dry-run proves names/URLs/space only. It cannot simulate on-device"
  echo "compilation or proot-specific quirks -- test a real run on a fresh"
  echo "proot container before trusting it."
  exit 0
fi

# =====================================================================
# Step 0 -- sanity checks
# =====================================================================
say "Step 0/10: sanity checks"
[ "$(uname -m)" = "aarch64" ] || warn "Not aarch64: $(uname -m) (this guide was validated on aarch64)"
[ "$(id -u)" -eq 0 ] || die "Not running as root -- run 'proot-distro login ubuntu' first"
command -v apt >/dev/null 2>&1 || die "'apt' not found -- is this really Ubuntu?"
[ -f /etc/os-release ] || die "/etc/os-release not found"
grep -qi ubuntu /etc/os-release || die "Not Ubuntu: $(grep PRETTY_NAME /etc/os-release)"

# Detect nested proot (same check as proot-distro itself)
TRACER_PID=$(grep TracerPid "/proc/$$/status" 2>/dev/null | cut -f2)
if [ -n "$TRACER_PID" ] && [ "$TRACER_PID" != "0" ]; then
  TRACER_NAME=$(grep Name "/proc/$TRACER_PID/status" 2>/dev/null | cut -f2)
  if [ "$TRACER_NAME" = "proot" ]; then
    die "Nested proot detected -- do NOT run this script inside another proot instance"
  fi
fi

[ -d "$HOME_DIR" ] || die "\$HOME is not writable: $HOME_DIR"

# =====================================================================
# Step 1 -- apt update + upgrade; hold systemd
# =====================================================================
say "Step 1/10: updating apt and holding systemd"

# systemd CANNOT run in proot. Its postinst crashes with
# "Failed to seek /etc/machine-id: Bad file descriptor" and blocks all
# subsequent package installs. Hold it preemptively so nothing pulls it in.
apt-get update -y
apt-get upgrade -y || true
apt-mark hold systemd libsystemd-shared systemd-timesyncd 2>/dev/null || true

# Enable universe/multiverse for packages like gh, micro, etc.
add-apt-repository -y universe multiverse 2>/dev/null || true
apt-get update -y

# =====================================================================
# Step 2 -- system packages
# =====================================================================
say "Step 2/10: installing system packages"

# Prevent package postinst scripts from starting services during install.
# This is critical for postgresql (its postinst tries to start the server
# which fails without systemd). We remove it after install.
cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d

apt-get install -y \
  build-essential clang binutils cmake pkg-config make m4 patch \
  libzmq3-dev libffi-dev libssl-dev libjpeg-dev zlib1g-dev \
  libxml2-dev libxslt1-dev libpq-dev libncurses-dev \
  python3 python3-pip python3-dev python3-venv \
  rustc cargo llvm-dev lld \
  nodejs npm openjdk-17-jdk golang-go \
  postgresql postgresql-common \
  ffmpeg \
  openssh-server openssh-sftp-server \
  tmux micro nano neofetch net-tools \
  ripgrep jq curl wget unzip dos2unix git patchelf unixodbc \
  software-properties-common gfortran \
  || die "apt install failed -- check network and re-run"

ok "system packages installed"

# --- GitHub CLI (gh) via official apt repo ---
if ! command -v gh >/dev/null 2>&1; then
  say "installing GitHub CLI (gh)"
  mkdir -p /etc/apt/keyrings
  out=$(mktemp)
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$out" \
    && cat "$out" | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -y
  apt-get install -y gh || warn "gh install failed -- install manually later"
fi

# --- code-server via Microsoft install script ---
if ! command -v code-server >/dev/null 2>&1; then
  say "installing code-server"
  curl -fsSL https://code-server.dev/install.sh | sh \
    || warn "code-server install failed -- install manually later"
fi

# --- uv (Python package manager) via astral install script ---
if ! command -v uv >/dev/null 2>&1; then
  say "installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh \
    || warn "uv install failed -- install manually later"
  # uv installs to ~/.local/bin; ensure it's on PATH for this session
  export PATH="$HOME_DIR/.local/bin:$PATH"
fi

# Remove the policy-rc.d blocker now that package installs are done
rm -f /usr/sbin/policy-rc.d

ok "all system packages and tools installed"

# =====================================================================
# Step 3 -- pip configuration
# =====================================================================
say "Step 3/10: pip configuration"
mkdir -p "$HOME_DIR/.config/pip"
# Standard PyPI works for all packages on Ubuntu (glibc, native wheels).
# No TUR index needed -- that's a Termux-specific prebuilt wheel source.
cat > "$HOME_DIR/.config/pip/pip.conf" <<EOF
[global]
disable-pip-version-check = true
EOF
python3 -m pip install --upgrade pip

# =====================================================================
# Step 4 -- JupyterLab + marimo + data/AI stack (compiles native wheels)
# =====================================================================
say "Step 4/10: JupyterLab, marimo and the Python data/AI stack"
say "All packages compile from standard PyPI wheels (no TUR needed)."
say "It can take 10-30 minutes on a phone. Do NOT interrupt."

pip install jupyterlab marimo soccerdata seleniumbase edge-tts openai \
  fastapi uvicorn httpx websockets orjson rich requests tqdm PyYAML \
  ruamel.yaml tomlkit croniter python-dotenv PyJWT PyOTP PySocks \
  wrapper-tls-requests tabulate behave pytest pytest-html pytest-xdist \
  pytest-rerunfailures parameterized pdbp pynose \
  sqlalchemy PyMySQL psycopg2-binary pyodbc \
  jupyterlab-lsp python-lsp-server

if [ -z "${SETUP_SKIP_OPTD:-}" ]; then
  pip install mycdp msgspec narwhals tabcompleter annotated-doc fasteners \
    Unidecode sbvirtualdisplay sortedcontainers tenacity termcolor trio \
    trio-websocket socksio wsproto watchfiles uvloop fire docutils
fi

# Optional scientific stack (scipy builds natively on Ubuntu with gfortran)
if [ -n "${SETUP_SCI_STACK:-}" ]; then
  say "SETUP_SCI_STACK=1: installing scipy"
  pip install scipy || warn "pip install scipy failed"
fi

python3 -c "import jupyterlab, zmq, tornado, marimo; print('JupyterLab', jupyterlab.__version__)" \
  || warn "python import check failed -- inspect errors above"

# =====================================================================
# Step 5 -- Hermes Agent (proot Ubuntu build)
# =====================================================================
say "Step 5/10: Hermes Agent"
# clean stale aliases / pip cache from any previous attempts
unalias hermes 2>/dev/null
sed -i '/alias hermes/d' "$HOME_DIR/.bashrc" "$HOME_DIR/.zshrc" 2>/dev/null || true
python3 -m pip cache purge || true
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
pip install -e .
hermes --version || warn "hermes --version failed"

# =====================================================================
# Step 6 -- opencode (npm on native glibc)
# =====================================================================
say "Step 6/10: opencode v1.18.15 (npm)"
# Ubuntu has native glibc -- no .deb hack or glibc shim needed.
# npm global install is the cleanest path.

cat > "$HOME_DIR/.npmrc" <<'EOF'
allow-scripts=opencode-ai
EOF
npm install -g opencode-ai@1.18.15 || warn "npm install opencode-ai failed"
opencode --version || warn "opencode --version failed (may need a new shell)"

# =====================================================================
# Step 7 -- code-server config
# =====================================================================
say "Step 7/10: code-server configuration"
mkdir -p "$HOME_DIR/.config/code-server"
cat > "$HOME_DIR/.config/code-server/config.yaml" <<'EOF'
bind-addr: 127.0.0.1:8080
auth: password
password: password
cert: false
EOF
code-server --version || warn "code-server --version failed"

# =====================================================================
# Step 8 -- services (postgres / sshd / ssh-agent)
# =====================================================================
if [ -z "${SETUP_NO_SERVICES:-}" ]; then
  say "Step 8/10: services (postgres / sshd)"

  # --- PostgreSQL ---
  say "setting up PostgreSQL"

  # Find installed cluster version
  PG_LINE=$(pg_lsclusters -h 2>/dev/null | head -1)
  if [ -n "$PG_LINE" ]; then
    PG_VER=$(echo "$PG_LINE" | awk '{print $1}')
    PG_CLUST=$(echo "$PG_LINE" | awk '{print $2}')
  else
    # No cluster exists yet -- create one
    PG_VER=$(dpkg -l postgresql 2>/dev/null | grep ^ii | awk '{print $3}' | sed 's/postgresql-\([0-9]*\).*/\1/')
    PG_VER="${PG_VER:-16}"
    PG_CLUST="main"
    say "creating PostgreSQL cluster (ver=$PG_VER)"
    pg_createcluster "$PG_VER" "$PG_CLUST" -- --auth-local=trust --auth-host=md5 2>/dev/null \
      || warn "pg_createcluster failed -- try: pg_ctlcluster $PG_VER $PG_CLUST start"
  fi

  # Start PostgreSQL
  if ! pg_isready -q 2>/dev/null; then
    say "starting PostgreSQL $PG_VER"
    pg_ctlcluster "$PG_VER" "$PG_CLUST" start 2>/dev/null \
      || su - postgres -c "pg_ctl -D /var/lib/postgresql/$PG_VER/$PG_CLUST -l /var/log/postgresql/postgresql-$PG_VER-$PG_CLUST.log start" \
      || warn "postgres start failed"
  fi
  pg_isready 2>/dev/null && ok "PostgreSQL is running" || warn "PostgreSQL may not be running -- check: pg_isready"

  # --- OpenSSH ---
  if [ -z "${SETUP_NO_SSH:-}" ]; then
    say "setting up OpenSSH"

    # Generate host keys if missing
    [ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A 2>/dev/null

    # Configure: no PAM (no real auth modules in proot), root login OK
    sed -i 's/^#\?UsePAM.*/UsePAM no/' /etc/ssh/sshd_config
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    # Use non-standard port (2222) to avoid conflict with Termux sshd
    sed -i 's/^#\?Port .*/Port 2222/' /etc/ssh/sshd_config

    # Start sshd in background
    if ! pgrep -x sshd >/dev/null 2>&1; then
      /usr/sbin/sshd -D -e 2>/dev/null &
      sleep 1
      pgrep -x sshd >/dev/null 2>&1 && ok "sshd running on port 2222" \
        || warn "sshd failed to start -- run: /usr/sbin/sshd -D -e -p 2222"
    fi
  fi

  # --- Service wrapper script ---
  say "writing /usr/local/bin/svcs (service control wrapper)"
  cat > /usr/local/bin/svcs <<'WRAPPER'
#!/bin/bash
#
# svcs -- simple service control for proot Ubuntu
# Usage: svcs <service> <action>
# Services: postgres, ssh, all
# Actions:  start, stop, status, restart
#
usage() {
  echo "Usage: svcs <service> <action>"
  echo "Services: postgres, ssh, all"
  echo "Actions:  start, stop, status, restart"
  exit 1
}

[ $# -lt 2 ] && usage

svc_start_postgres() {
  PG_LINE=$(pg_lsclusters -h 2>/dev/null | head -1)
  [ -z "$PG_LINE" ] && { echo "No PostgreSQL cluster found"; return 1; }
  PG_VER=$(echo "$PG_LINE" | awk '{print $1}')
  PG_CLUST=$(echo "$PG_LINE" | awk '{print $2}')
  pg_ctlcluster "$PG_VER" "$PG_CLUST" start 2>/dev/null
  pg_isready -q 2>/dev/null && echo "PostgreSQL started" || echo "PostgreSQL failed to start"
}

svc_stop_postgres() {
  PG_LINE=$(pg_lsclusters -h 2>/dev/null | head -1)
  [ -z "$PG_LINE" ] && { echo "No PostgreSQL cluster found"; return 1; }
  PG_VER=$(echo "$PG_LINE" | awk '{print $1}')
  PG_CLUST=$(echo "$PG_LINE" | awk '{print $2}')
  pg_ctlcluster "$PG_VER" "$PG_CLUST" stop 2>/dev/null
  echo "PostgreSQL stopped"
}

svc_status_postgres() {
  pg_isready -q 2>/dev/null && echo "PostgreSQL: running" || echo "PostgreSQL: stopped"
}

svc_start_ssh() {
  if pgrep -x sshd >/dev/null 2>&1; then
    echo "sshd already running"
    return
  fi
  /usr/sbin/sshd -D -e -p 2222 2>/dev/null &
  sleep 1
  pgrep -x sshd >/dev/null 2>&1 && echo "sshd started on port 2222" || echo "sshd failed to start"
}

svc_stop_ssh() {
  if pgrep -x sshd >/dev/null 2>&1; then
    pkill -x sshd
    echo "sshd stopped"
  else
    echo "sshd not running"
  fi
}

svc_status_ssh() {
  pgrep -x sshd >/dev/null 2>&1 && echo "sshd: running (port 2222)" || echo "sshd: stopped"
}

SVC="$1"
ACTION="$2"

case "$SVC" in
  postgres)
    case "$ACTION" in
      start)   svc_start_postgres ;;
      stop)    svc_stop_postgres ;;
      status)  svc_status_postgres ;;
      restart) svc_stop_postgres; sleep 1; svc_start_postgres ;;
      *)       usage ;;
    esac
    ;;
  ssh)
    case "$ACTION" in
      start)   svc_start_ssh ;;
      stop)    svc_stop_ssh ;;
      status)  svc_status_ssh ;;
      restart) svc_stop_ssh; sleep 1; svc_start_ssh ;;
      *)       usage ;;
    esac
    ;;
  all)
    case "$ACTION" in
      start)   svc_start_postgres; svc_start_ssh ;;
      stop)    svc_stop_postgres; svc_stop_ssh ;;
      status)  svc_status_postgres; svc_status_ssh ;;
      restart) svc_stop_postgres; svc_stop_ssh; sleep 1; svc_start_postgres; svc_start_ssh ;;
      *)       usage ;;
    esac
    ;;
  *)
    usage
    ;;
esac
WRAPPER
  chmod +x /usr/local/bin/svcs

  svcs all status || true
else
  say "Step 8/10: services skipped (SETUP_NO_SERVICES=1)"
fi

# =====================================================================
# Step 9 -- dotfiles and configs (no project/user files)
# =====================================================================
say "Step 9/10: dotfiles and configs"

cat > "$HOME_DIR/.bashrc" <<'EOF'

# --- proot Ubuntu -- Local AI Agent Configuration (4GB RAM Optimized) ---
# Ollama runs on the Termux host; proot connects via localhost.
export OPENAI_BASE_URL="http://localhost:11434/v1"
export OPENAI_API_KEY="ollama"

# proot prompt (distinguish from Termux host)
export PS1='\[\033[1;35m\]proot\[\033[0m\] \w\$ '

# Ensure ~/.local/bin is on PATH (uv, user-installed tools)
export PATH="$HOME/.local/bin:$PATH"
export LANG=en_US.UTF-8
EOF

# .npmrc
cat > "$HOME_DIR/.npmrc" <<'EOF'
allow-scripts=opencode-ai
EOF

# micro editor
mkdir -p "$HOME_DIR/.config/micro"
cat > "$HOME_DIR/.config/micro/settings.json" <<'EOF'
{
    "clipboard": "terminal",
    "keymenu": true,
    "mouse": true,
    "colorscheme": "simple"
}
EOF

# opencode
mkdir -p "$HOME_DIR/.config/opencode"
cat > "$HOME_DIR/.config/opencode/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF

# marimo
mkdir -p "$HOME_DIR/.config/marimo"
: > "$HOME_DIR/.config/marimo/marimo.toml"

# JupyterLab (suppress noisy "Skipped non-installed server(s)" log lines)
mkdir -p "$HOME_DIR/.jupyter"
cat > "$HOME_DIR/.jupyter/jupyter_lab_config.py" <<'EOF'
import logging

# jupyter-lsp auto-detects known language servers and logs an INFO line on the
# "ServerApp" logger for every server that is not installed (e.g.
# "Skipped non-installed server(s): basedpyright, ...").
# python-lsp-server IS installed (via jupyterlab-lsp) for in-cell intellisense;
# autodetect stays on so it registers automatically. This filter drops only
# that one noisy line and leaves all other ServerApp INFO logs untouched.
class _NoSkippedServers(logging.Filter):
    def filter(self, record):
        return not record.getMessage().startswith("Skipped non-installed")

logging.getLogger("ServerApp").addFilter(_NoSkippedServers())
EOF

# --- proot-specific: resolv.conf, machine-id, locale ---
# DNS resolution: proot doesn't automatically inherit host resolv.conf
if [ ! -f /etc/resolv.conf ] || ! grep -q nameserver /etc/resolv.conf 2>/dev/null; then
  say "writing /etc/resolv.conf (DNS)"
  cat > /etc/resolv.conf <<'DNS'
nameserver 8.8.8.8
nameserver 8.8.4.4
DNS
fi

# /etc/machine-id: some programs (dbus, systemd tools, networkd) check this.
# systemd-machine-id-setup is the proper way, but if systemd is held it may
# not be available. Fallback to a manual write.
if [ ! -s /etc/machine-id ]; then
  say "generating /etc/machine-id"
  systemd-machine-id-setup 2>/dev/null \
    || (head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > /etc/machine-id)
  chmod 444 /etc/machine-id
fi

# Locale
if ! locale -a 2>/dev/null | grep -q en_US.utf8; then
  say "generating locale"
  locale-gen en_US.UTF-8 2>/dev/null || true
fi

# User files are intentionally NOT written by this script. Create them yourself:
warn "Create your own ~/.env (USERNAME/PASSWORD), ~/.pgpass_initial (PG_PASS),"
warn "~/.ssh keys/authorized_keys -- see README."

# =====================================================================
# Step 10 -- final verification + summary
# =====================================================================
say "Step 10/10: verification"
{
  echo "--- apt (key) ---"
  apt list --installed 2>/dev/null | rg -i "python3|code-server|postgresql|nodejs|rustc|clang|openssh" | head -20
  echo "--- python ---";  python3 -V; pip -V
  echo "--- jupyter ---"; jupyter --version 2>/dev/null | head -4
  echo "--- lsp ---";     pylsp --version 2>/dev/null || true
  echo "--- marimo ---";  marimo --version 2>/dev/null || true
  echo "--- native modules ---"
  python3 -c "import PIL, pydantic, zmq; print('PIL', PIL.__version__, '| pydantic', pydantic.VERSION)" 2>&1 || true
  [ -n "${SETUP_SCI_STACK:-}" ] && echo "--- scipy ---"
  [ -n "${SETUP_SCI_STACK:-}" ] && python3 -c "import scipy; print('scipy', scipy.__version__)" 2>&1 || true
  echo "--- hermes ---";  hermes --version 2>/dev/null || true
  echo "--- code-server ---"; code-server --version 2>/dev/null | head -1
  echo "--- opencode ---"; opencode --version 2>/dev/null || true
  echo "--- postgres ---"; pg_isready 2>/dev/null || echo "not running"
  echo "--- sshd ---";     pgrep -x sshd >/dev/null 2>&1 && echo "running (port 2222)" || echo "not running"
  echo "--- gh ---";       gh --version 2>/dev/null | head -1 || echo "not installed"
  echo "--- uv ---";       uv --version 2>/dev/null || echo "not installed"
} || true

ok "All done!"
cat <<EOF

Manual follow-ups:
  * READ THIS GUIDE for all steps you must do by hand: ~/README.md
  * CREATE ~/.env (USERNAME/PASSWORD), ~/.pgpass_initial (PG_PASS), ~/.ssh keys
  * Start services/daemons when ready:
      svcs postgres start     # or: pg_ctlcluster <ver> main start
      svcs ssh start          # or: /usr/sbin/sshd -D -e -p 2222 &
      jupyter lab --no-browser --port=8888
      code-server &
  * Access from Android browser (via Termux or proot port forward):
      proot-distro login ubuntu
      svcs postgres start
      jupyter lab --no-browser --port=8888
      # then open http://localhost:8888 on Android
  * Ollama runs on the Termux host -- connect via localhost:11434
  * For SSH access from other devices: start sshd on port 2222 inside proot
  * Service wrapper: svcs <postgres|ssh|all> <start|stop|status|restart>
  * AcodeX (axs) is a Termux-side editor: install from termux-setup.sh
EOF
