#!/bin/bash
# ha-pull.sh — runs ON the HA device via a time_pattern automation.
# Fetches from GitHub via SSH; if behind, fast-forward-pulls and writes a flag
# that the binary_sensor watches. All paths under /config/ are persistent.

LOG="/config/ha-git.log"
FLAG="/config/.ha-update-flag"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [pull] $*" >> "$LOG"; }

log "--- run start ---"

# ── fix HOME for HA's shell_command environment ───────────────────────────────
# HA's process may have HOME unset or pointing to the wrong directory.
# Scan known homes so SSH can find ~/.ssh/id_* and known_hosts.
for _H in /root /homeassistant /home/homeassistant; do
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

# Ensure SSH uses the correct known_hosts (prevents host key verification failure)
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=${HOME}/.ssh/known_hosts"

log "DEBUG: HOME=$HOME  GIT=$GIT  remote=$(\"$GIT\" -C /config remote get-url origin 2>/dev/null)"

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
  log "ERROR: git fetch failed (check SSH key / network). HOME=$HOME"
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
