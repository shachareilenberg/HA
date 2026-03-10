#!/usr/bin/env bash
# ha-push.sh
# Runs ON the HA device every 5 minutes via a time_pattern automation +
# shell_command. Commits and pushes any local config changes to GitHub.
# Triggered config changes include anything saved via the HA UI editors,
# the File Editor add-on, or SSH direct edits.

LOG="/tmp/ha-git-push.log"

cd /config

# Bail early if another git operation is already running
if [ -f /config/.git/index.lock ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — index.lock present, skipping" >> "$LOG"
  exit 0
fi

# Nothing to do if tree is clean
if git diff --quiet && \
   git diff --cached --quiet && \
   [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0
fi

git add -A
git commit -m "auto: update config $(date '+%Y-%m-%d %H:%M')"

BRANCH="$(git branch --show-current)"
git push origin "$BRANCH"

echo "$(date '+%Y-%m-%d %H:%M:%S') — pushed changes to origin/$BRANCH" >> "$LOG"
