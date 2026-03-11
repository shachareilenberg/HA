#!/bin/bash
# ha-push.sh — runs ON the HA device via a time_pattern automation.
# Commits and pushes any local changes to GitHub via SSH.

LOG="/config/ha-git.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [push] $*" >> "$LOG"; }

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
# Prevent any interactive prompts or editor windows when running non-interactively
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=true

log "DEBUG: HOME=$HOME  GIT=$GIT"

# ── sanity checks ─────────────────────────────────────────────────────────────
if [ ! -d /config/.git ]; then
  log "ERROR: /config is not a git repository. Run ha-git-setup.sh first via SSH."
  exit 1
fi

cd /config || { log "ERROR: cannot cd to /config"; exit 1; }

# ── skip if another git operation is running ──────────────────────────────────
if [ -f .git/index.lock ]; then
  log "index.lock present — skipping"
  exit 0
fi

# ── check for local changes ───────────────────────────────────────────────────
if "$GIT" diff --quiet && \
   "$GIT" diff --cached --quiet && \
   [ -z "$("$GIT" ls-files --others --exclude-standard 2>/dev/null)" ]; then
  log "OK: nothing to push"
  exit 0
fi

"$GIT" add -A
"$GIT" commit -m "auto: update config $(date '+%Y-%m-%d %H:%M')" 2>> "$LOG"

BRANCH="$("$GIT" branch --show-current 2>/dev/null)"
if ! "$GIT" push origin "$BRANCH" 2>> "$LOG"; then
  log "ERROR: git push failed (check SSH key). HOME=$HOME"
  exit 1
fi

log "OK: pushed changes to origin/$BRANCH"
