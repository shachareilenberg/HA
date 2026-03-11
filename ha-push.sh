#!/bin/bash
# ha-push.sh — runs ON the HA device via a time_pattern automation.
# Commits and pushes any local changes to GitHub via SSH.
#
# Logging: only errors and actual push events are written to ha-git.log.
# Log buffering: all output collected in memory, flushed at exit so
# ha-git.log is never modified during git operations (clean working tree).

LOG="/config/ha-git.log"
GIT_TMP="$(mktemp)"

LOG_BUFFER=""
log() { LOG_BUFFER+="$(date '+%Y-%m-%d %H:%M:%S') [push] $*"$'\n'; }
flush_log() {
  local git_out
  git_out="$(cat "$GIT_TMP" 2>/dev/null)"
  if [ -n "$LOG_BUFFER" ] || [ -n "$git_out" ]; then
    { printf '%s' "$LOG_BUFFER"; [ -n "$git_out" ] && printf '%s\n' "$git_out"; } >> "$LOG"
  fi
  rm -f "$GIT_TMP"
}
trap flush_log EXIT

# ── fix HOME for HA's shell_command environment ───────────────────────────────
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
  log "ERROR: git not found"
  exit 1
fi

# ── locate SSH private key ────────────────────────────────────────────────────
SSH_KEY=""
for K in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa" "${HOME}/.ssh/id_ecdsa" \
         "${HOME}/.ssh/id_ecdsa_sk" "${HOME}/.ssh/id_ed25519_sk"; do
  [ -f "$K" ] && SSH_KEY="$K" && break
done
if [ -z "$SSH_KEY" ]; then
  for K in "${HOME}/.ssh/"*; do
    case "$K" in
      *.pub|*known_hosts*|*config*|*authorized_keys*) continue ;;
    esac
    [ -f "$K" ] && SSH_KEY="$K" && break
  done
fi

if [ -n "$SSH_KEY" ]; then
  export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=${HOME}/.ssh/known_hosts"
else
  export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=${HOME}/.ssh/known_hosts"
  log "WARN: no SSH key found in ${HOME}/.ssh/ — relying on SSH config"
fi
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=true

# ── sanity checks ─────────────────────────────────────────────────────────────
if [ ! -d /config/.git ]; then
  log "ERROR: /config is not a git repo — run ha-git-setup.sh via SSH"
  exit 1
fi

cd /config || { log "ERROR: cannot cd to /config"; exit 1; }

if [ -f .git/index.lock ]; then
  exit 0  # another git op in progress — skip silently
fi

# ── check for changes to commit or push ──────────────────────────────────────
HAS_CHANGES=0
if ! "$GIT" diff --quiet || \
   ! "$GIT" diff --cached --quiet || \
   [ -n "$("$GIT" ls-files --others --exclude-standard 2>/dev/null)" ]; then
  HAS_CHANGES=1
fi

BRANCH="$("$GIT" branch --show-current 2>/dev/null)"
AHEAD="$("$GIT" rev-list "origin/$BRANCH..HEAD" --count 2>/dev/null || echo 0)"

if [ "$HAS_CHANGES" -eq 0 ] && [ "$AHEAD" -eq 0 ]; then
  exit 0  # nothing to do — log nothing
fi

# ── commit any file changes ───────────────────────────────────────────────────
COMMITTED=0
if [ "$HAS_CHANGES" -eq 1 ]; then
  "$GIT" add -A
  "$GIT" commit -m "auto: update config $(date '+%Y-%m-%d %H:%M')" 2>/dev/null
  COMMITTED=1
fi

# ── push — rebase and retry once if remote is ahead ──────────────────────────
if ! "$GIT" push origin "$BRANCH" 2>>"$GIT_TMP"; then
  BEHIND="$("$GIT" rev-list "HEAD..origin/$BRANCH" --count 2>/dev/null || echo 0)"
  if [ "$BEHIND" -gt 0 ]; then
    : > "$GIT_TMP"  # clear push rejection noise before rebase
    if "$GIT" pull --rebase -X ours origin "$BRANCH" 2>>"$GIT_TMP" && \
       "$GIT" push origin "$BRANCH" 2>>"$GIT_TMP"; then
      : > "$GIT_TMP"  # suppress successful push output
      exit 0
    fi
    log "ERROR: push failed after rebase (branch=$BRANCH KEY=${SSH_KEY:-none})"
  fi
  if [ "$COMMITTED" -eq 1 ]; then
    "$GIT" reset --soft HEAD~1
    log "ERROR: push failed — commit undone, will retry. KEY=${SSH_KEY:-none}"
  else
    log "ERROR: push failed (pre-existing commits). KEY=${SSH_KEY:-none}"
  fi
  exit 1
fi

: > "$GIT_TMP"  # suppress successful push output
