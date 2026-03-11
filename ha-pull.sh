#!/usr/bin/env bash
# ha-pull.sh — runs ON the HA device via a time_pattern automation.
# Fetches from GitHub; if behind, fast-forward-pulls and writes a flag
# that the binary_sensor watches. All paths under /config/ are persistent.

LOG="/config/ha-git.log"
FLAG="/config/.ha-update-flag"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [pull] $*" >> "$LOG"; }

# ── locate git ────────────────────────────────────────────────────────────────
GIT=""
for P in /usr/bin/git /usr/local/bin/git /bin/git; do
  [ -x "$P" ] && GIT="$P" && break
done
if [ -z "$GIT" ] && command -v git >/dev/null 2>&1; then
  GIT="$(command -v git)"
fi
if [ -z "$GIT" ]; then
  log "ERROR: git not found. Install it or check the HA container environment."
  exit 1
fi

# ── sanity checks ─────────────────────────────────────────────────────────────
if [ ! -d /config ]; then
  log "ERROR: /config directory not found."
  exit 1
fi

cd /config || { log "ERROR: cannot cd to /config"; exit 1; }

if [ ! -d .git ]; then
  log "ERROR: /config is not a git repository. Run ha-git-setup.sh first via SSH."
  exit 1
fi

# ── skip if another git operation is running ──────────────────────────────────
if [ -f .git/index.lock ]; then
  log "index.lock present — skipping (another git op is running)"
  exit 0
fi

# ── fetch ─────────────────────────────────────────────────────────────────────
if ! "$GIT" fetch origin --quiet 2>> "$LOG"; then
  log "ERROR: git fetch failed (check credentials / network)"
  exit 1
fi

BRANCH="$("$GIT" branch --show-current 2>/dev/null)"
BEHIND="$("$GIT" rev-list "HEAD..origin/$BRANCH" --count 2>/dev/null || echo 0)"
AHEAD="$("$GIT"  rev-list "origin/$BRANCH..HEAD"  --count 2>/dev/null || echo 0)"

if [ "$BEHIND" -eq 0 ]; then
  exit 0   # up to date — exit silently
fi

if [ "$AHEAD" -gt 0 ]; then
  log "SKIP: $AHEAD local commit(s) ahead of remote; skipping pull to avoid conflict"
  exit 0
fi

if [ -n "$("$GIT" status --porcelain 2>/dev/null)" ]; then
  log "SKIP: working tree has uncommitted changes; skipping pull"
  exit 0
fi

if ! "$GIT" pull origin "$BRANCH" --ff-only --quiet 2>> "$LOG"; then
  log "ERROR: git pull failed"
  exit 1
fi

log "OK: pulled $BEHIND new commit(s) from origin/$BRANCH"

# Signal the binary sensor (flag lives in /config/ — survives reboots)
touch "$FLAG"
