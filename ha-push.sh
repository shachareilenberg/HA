#!/bin/bash
# ha-push.sh — runs ON the HA device via a time_pattern automation.
# Commits and pushes any local changes to GitHub via SSH.
#
# Log buffering: all output is collected in memory and flushed to ha-git.log
# only at script exit. This keeps ha-git.log unmodified during git operations,
# so the working tree stays clean and rebase never sees unstaged changes.

LOG="/config/ha-git.log"
GIT_TMP="$(mktemp)"

LOG_BUFFER=""
log() { LOG_BUFFER+="$(date '+%Y-%m-%d %H:%M:%S') [push] $*"$'\n'; }
flush_log() {
  local git_out
  git_out="$(cat "$GIT_TMP" 2>/dev/null)"
  { printf '%s' "$LOG_BUFFER"; [ -n "$git_out" ] && printf '%s\n' "$git_out"; } >> "$LOG"
  rm -f "$GIT_TMP"
}
trap flush_log EXIT

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

# ── check for uncommitted file changes ────────────────────────────────────────
# ha-git.log is NOT modified during this run (buffered), so only real config
# changes trigger this check.
HAS_CHANGES=0
if ! "$GIT" diff --quiet || \
   ! "$GIT" diff --cached --quiet || \
   [ -n "$("$GIT" ls-files --others --exclude-standard 2>/dev/null)" ]; then
  HAS_CHANGES=1
fi

# ── check for already-committed but unpushed commits ─────────────────────────
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
  "$GIT" commit -m "auto: update config $(date '+%Y-%m-%d %H:%M')" 2>>"$GIT_TMP"
  COMMITTED=1
fi

# ── push — rebase and retry once if remote is ahead ──────────────────────────
# Working tree is clean (ha-git.log not written during run), so rebase works.
if ! "$GIT" push origin "$BRANCH" 2>>"$GIT_TMP"; then
  BEHIND="$("$GIT" rev-list "HEAD..origin/$BRANCH" --count 2>/dev/null || echo 0)"
  if [ "$BEHIND" -gt 0 ]; then
    log "WARN: remote is ahead by $BEHIND — rebasing and retrying push"
    if "$GIT" pull --rebase origin "$BRANCH" 2>>"$GIT_TMP"; then
      if "$GIT" push origin "$BRANCH" 2>>"$GIT_TMP"; then
        log "OK: pushed changes to origin/$BRANCH (after rebase)"
        exit 0
      fi
    fi
    log "ERROR: push still failed after rebase"
  fi
  # Undo the local commit so it doesn't accumulate on repeated failures
  if [ "$COMMITTED" -eq 1 ]; then
    "$GIT" reset --soft HEAD~1
    log "WARN: push failed — commit undone, will retry next run. KEY=$SSH_KEY"
  else
    log "ERROR: push failed (pre-existing commits). KEY=$SSH_KEY"
  fi
  exit 1
fi

log "OK: pushed changes to origin/$BRANCH"
