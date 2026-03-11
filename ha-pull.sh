#!/bin/bash
# ha-pull.sh — runs ON the HA device via a time_pattern automation.
# Fetches from GitHub via SSH; if behind, fast-forward-pulls and writes a flag
# that the binary_sensor watches. All paths under /config/ are persistent.

LOG="/config/ha-git.log"
FLAG="/config/.ha-update-flag"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [pull] $*" >> "$LOG"; }

log "--- run start ---"

# ── fix HOME for HA's shell_command environment ───────────────────────────────
# /config/.ssh/ is preferred — it's writable by the HA process regardless of user.
# /root/.ssh/ is only accessible when shell_command runs as root.
for _H in /config /root /homeassistant /home/homeassistant; do
  if [ -d "$_H/.ssh" ]; then
    export HOME="$_H"
    break
  fi
done

# ── locate git ────────────────────────────────────────────────────────────────
GIT=""
for P in /usr/bin/git /usr/local/bin/git /bin/git; do
  [ -x "$P" ] && GIT="$P" && break
done
[ -z "$GIT" ] && command -v git >/dev/null 2>&1 && GIT="$(command -v git)"
if [ -z "$GIT" ]; then
  log "ERROR: git not found."
  exit 1
fi

# ── locate SSH private key ────────────────────────────────────────────────────
log "DEBUG: .ssh contents: $(ls -la ${HOME}/.ssh/ 2>&1 | tr '\n' '|')"

SSH_KEY=""
for K in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa" "${HOME}/.ssh/id_ecdsa" \
         "${HOME}/.ssh/id_ecdsa_sk" "${HOME}/.ssh/id_ed25519_sk"; do
  [ -f "$K" ] && SSH_KEY="$K" && break
done
# If no standard key found, also scan for any private key file in ~/.ssh/
if [ -z "$SSH_KEY" ]; then
  for K in "${HOME}/.ssh/"*; do
    case "$K" in
      *.pub|*known_hosts*|*config*|*authorized_keys*) continue ;;
    esac
    [ -f "$K" ] && SSH_KEY="$K" && break
  done
fi

# Build GIT_SSH_COMMAND — use explicit key if found, else fall back to SSH config
if [ -n "$SSH_KEY" ]; then
  export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=${HOME}/.ssh/known_hosts"
else
  export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=${HOME}/.ssh/known_hosts"
  log "WARN: no standard SSH key found — relying on ${HOME}/.ssh/config"
fi
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=true

log "DEBUG: HOME=$HOME  GIT=$GIT  KEY=${SSH_KEY:-from_config}"

# ── sanity checks ─────────────────────────────────────────────────────────────
cd /config || { log "ERROR: cannot cd to /config"; exit 1; }

if [ ! -d .git ]; then
  log "ERROR: /config is not a git repository. Run ha-git-setup.sh first via SSH."
  exit 1
fi

# ── skip if another git operation is running ──────────────────────────────────
if [ -f .git/index.lock ]; then
  log "index.lock present — skipping"
  exit 0
fi

# ── fetch ─────────────────────────────────────────────────────────────────────
if ! "$GIT" fetch origin 2>> "$LOG"; then
  log "ERROR: git fetch failed (check SSH key / network). HOME=$HOME  KEY=$SSH_KEY"
  exit 1
fi

BRANCH="$("$GIT" branch --show-current 2>/dev/null)"
BEHIND="$("$GIT" rev-list "HEAD..origin/$BRANCH" --count 2>/dev/null || echo 0)"
AHEAD="$("$GIT"  rev-list "origin/$BRANCH..HEAD"  --count 2>/dev/null || echo 0)"

log "DEBUG: branch=$BRANCH  behind=$BEHIND  ahead=$AHEAD"

if [ "$BEHIND" -eq 0 ]; then
  log "OK: already up to date"
  exit 0
fi

if [ "$AHEAD" -gt 0 ]; then
  log "SKIP: $AHEAD local commit(s) ahead of remote — skipping pull"
  exit 0
fi

if [ -n "$("$GIT" status --porcelain 2>/dev/null)" ]; then
  log "SKIP: uncommitted changes — skipping pull"
  exit 0
fi

if ! "$GIT" pull origin "$BRANCH" --ff-only 2>> "$LOG"; then
  log "ERROR: git pull failed"
  exit 1
fi

log "OK: pulled $BEHIND new commit(s) from origin/$BRANCH"

# Signal the binary sensor (flag lives in /config/ — survives reboots)
touch "$FLAG"
