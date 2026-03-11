#!/usr/bin/env bash
# ha-push.sh — runs ON the HA device via a time_pattern automation.
# Commits and pushes any local changes to GitHub.

LOG="/config/ha-git.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [push] $*" >> "$LOG"; }

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
if [ ! -d /config/.git ]; then
  log "ERROR: /config is not a git repository. Run ha-git-setup.sh first via SSH."
  exit 1
fi

cd /config || { log "ERROR: cannot cd to /config"; exit 1; }

# ── skip if another git operation is running ──────────────────────────────────
if [ -f .git/index.lock ]; then
  log "index.lock present — skipping (another git op is running)"
  exit 0
fi

# ── check for local changes ───────────────────────────────────────────────────
if "$GIT" diff --quiet && \
   "$GIT" diff --cached --quiet && \
   [ -z "$("$GIT" ls-files --others --exclude-standard 2>/dev/null)" ]; then
  exit 0   # nothing to push — exit silently
fi

"$GIT" add -A
"$GIT" commit -m "auto: update config $(date '+%Y-%m-%d %H:%M')" 2>> "$LOG"

BRANCH="$("$GIT" branch --show-current 2>/dev/null)"
if ! "$GIT" push origin "$BRANCH" 2>> "$LOG"; then
  log "ERROR: git push failed (check credentials / network)"
  exit 1
fi

log "OK: pushed changes to origin/$BRANCH"
