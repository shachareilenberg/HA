#!/bin/bash
# ha-push.sh — runs ON the HA device via a time_pattern automation.
# Commits and pushes any local changes to GitHub via SSH.

LOG="/config/ha-git.log"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [push] $*" >> "$LOG"; }

log "--- run start ---"

# ── fix HOME for HA's shell_command environment ───────────────────────────────
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

# ── locate SSH private key ────────────────────────────────────────────────────
SSH_KEY=""
for K in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa" "${HOME}/.ssh/id_ecdsa" \
         "${HOME}/.ssh/id_ecdsa_sk" "${HOME}/.ssh/id_ed25519_sk"; do
  [ -f "$K" ] && SSH_KEY="$K" && break
done
# If no standard key found, also scan for any private key file in ~/.ssh/
if [ -z "$SSH_KEY" ]; then
  for K in "${HOME}/.ssh/"*; do
    [ -f "$K" ] && [[ "$K" != *.pub ]] && [[ "$K" != *known_hosts* ]] && \
    [[ "$K" != *config* ]] && [[ "$K" != *authorized_keys* ]] && \
      SSH_KEY="$K" && break
  done
fi

# Build GIT_SSH_COMMAND — use explicit key if found, else fall back to SSH config
if [ -n "$SSH_KEY" ]; then
  export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=${HOME}/.ssh/known_hosts"
else
  # No key file found by name — let SSH use ~/.ssh/config (handles custom key names)
  export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=${HOME}/.ssh/known_hosts"
  log "WARN: no standard SSH key found — relying on ${HOME}/.ssh/config"
fi
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=true

log "DEBUG: HOME=$HOME  GIT=$GIT  KEY=${SSH_KEY:-from_config}"

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

# ── check for uncommitted file changes ───────────────────────────────────────
HAS_CHANGES=0
if ! "$GIT" diff --quiet || \
   ! "$GIT" diff --cached --quiet || \
   [ -n "$("$GIT" ls-files --others --exclude-standard 2>/dev/null)" ]; then
  HAS_CHANGES=1
fi

# ── check for already-committed but unpushed commits (e.g. from previous failures)
BRANCH="$("$GIT" branch --show-current 2>/dev/null)"
AHEAD="$("$GIT" rev-list "origin/$BRANCH..HEAD" --count 2>/dev/null || echo 0)"

if [ "$HAS_CHANGES" -eq 0 ] && [ "$AHEAD" -eq 0 ]; then
  log "OK: nothing to push"
  exit 0
fi

# ── commit any file changes ───────────────────────────────────────────────────
COMMITTED=0
if [ "$HAS_CHANGES" -eq 1 ]; then
  "$GIT" add -A
  "$GIT" commit -m "auto: update config $(date '+%Y-%m-%d %H:%M')" 2>> "$LOG"
  COMMITTED=1
fi

# ── push (includes any pre-existing unpushed commits) ────────────────────────
if ! "$GIT" push origin "$BRANCH" 2>> "$LOG"; then
  # If we just made a commit and push failed, undo it so it doesn't pile up
  if [ "$COMMITTED" -eq 1 ]; then
    "$GIT" reset --soft HEAD~1
    log "WARN: push failed — commit undone, will retry next run. KEY=$SSH_KEY"
  else
    log "ERROR: push failed (pre-existing commits). KEY=$SSH_KEY"
  fi
  exit 1
fi

log "OK: pushed changes to origin/$BRANCH"
