#!/usr/bin/env bash
# ha-pull.sh
# Runs ON the HA device every 5 minutes via a time_pattern automation +
# shell_command. Fetches from GitHub and, if the branch is strictly behind
# with a clean working tree, pulls and drops a signal file so the dashboard
# banner appears asking for a restart.

LOG="/tmp/ha-git-pull.log"
SIGNAL="/tmp/ha-config-updated"

cd /config

# Bail early if another git operation is already running
if [ -f /config/.git/index.lock ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — index.lock present, skipping" >> "$LOG"
  exit 0
fi

git fetch origin --quiet 2>&1

BRANCH="$(git branch --show-current)"
BEHIND="$(git rev-list "HEAD..origin/$BRANCH" --count 2>/dev/null || echo 0)"
AHEAD="$(git rev-list  "origin/$BRANCH..HEAD"  --count 2>/dev/null || echo 0)"

if [ "$BEHIND" -eq 0 ]; then
  exit 0
fi

if [ "$AHEAD" -gt 0 ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — $AHEAD local commit(s) ahead; skipping pull" >> "$LOG"
  exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — dirty working tree; skipping pull" >> "$LOG"
  exit 0
fi

git pull origin "$BRANCH" --ff-only --quiet 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S') — pulled $BEHIND new commit(s) from origin/$BRANCH" >> "$LOG"

# Signal the HA binary sensor — both this script and the sensor run on the
# same device, so /tmp/ is the same filesystem.
touch "$SIGNAL"
