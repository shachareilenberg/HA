#!/bin/bash
# ha-pull.sh — runs ON the HA device via a time_pattern automation.
# Fetches from GitHub via SSH; if behind, rebases and writes a flag
# that the binary_sensor watches. All paths under /config/ are persistent.
#
# Logging: only errors and actual pull events are written to ha-git.log.
# Log buffering: all output collected in memory, flushed at exit so
# ha-git.log is never modified during git operations (clean working tree).

LOG="/config/ha-git.log"
FLAG="/config/.ha-update-flag"
GIT_TMP="$(mktemp)"

LOG_BUFFER=""
log()  { LOG_BUFFER+="$(date '+%Y-%m-%d %H:%M:%S') [pull] $*"$'\n'; }
# Only flush if there is something worth logging (errors or a real pull)
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
cd /config || { log "ERROR: cannot cd to /config"; exit 1; }

if [ ! -d .git ]; then
  log "ERROR: /config is not a git repo — run ha-git-setup.sh via SSH"
  exit 1
fi

if [ -f .git/index.lock ]; then
  exit 0  # another git op in progress — skip silently
fi

# ── fetch ─────────────────────────────────────────────────────────────────────
if ! "$GIT" fetch origin 2>>"$GIT_TMP"; then
  log "ERROR: git fetch failed (SSH/network). KEY=${SSH_KEY:-none}"
  exit 1
fi
# Discard fetch progress output — not useful in the log
: > "$GIT_TMP"

BRANCH="$("$GIT" branch --show-current 2>/dev/null)"
BEHIND="$("$GIT" rev-list "HEAD..origin/$BRANCH" --count 2>/dev/null || echo 0)"

if [ "$BEHIND" -eq 0 ]; then
  exit 0  # already up to date — log nothing
fi

# ── commit any local changes before rebase ────────────────────────────────────
if [ -n "$("$GIT" status --porcelain 2>/dev/null)" ]; then
  "$GIT" add -A
  "$GIT" commit -m "auto: save local changes before pull $(date '+%Y-%m-%d %H:%M')" 2>/dev/null
fi

# ── pull with rebase ──────────────────────────────────────────────────────────
if ! "$GIT" pull --rebase origin "$BRANCH" 2>>"$GIT_TMP"; then
  log "ERROR: git pull --rebase failed (branch=$BRANCH behind=$BEHIND)"
  exit 1
fi

touch "$FLAG"
