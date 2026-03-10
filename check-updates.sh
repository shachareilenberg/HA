#!/usr/bin/env bash
# check-updates.sh
# Runs periodically via launchd. Fetches from the remote, and if the local
# branch is strictly behind (fast-forward only, no local uncommitted changes),
# pulls the new commits and drops a signal file that Home Assistant watches.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/tmp/ha-check-updates.log"
SIGNAL_FILE="/tmp/ha-config-updated"

cd "$REPO_DIR"

BRANCH="$(git branch --show-current)"

# Fetch quietly — this updates origin/* refs without touching working tree
git fetch origin --quiet

BEHIND=$(git rev-list "HEAD..origin/$BRANCH" --count 2>/dev/null || echo 0)
AHEAD=$(git rev-list  "origin/$BRANCH..HEAD"  --count 2>/dev/null || echo 0)

if [[ "$BEHIND" -eq 0 ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — up to date on $BRANCH" >> "$LOG"
  exit 0
fi

if [[ "$AHEAD" -gt 0 ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — $AHEAD local commit(s) ahead; skipping pull to avoid conflict" >> "$LOG"
  exit 0
fi

# Safety: don't pull over a dirty working tree
if [[ -n "$(git status --porcelain)" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — working tree dirty; skipping pull" >> "$LOG"
  exit 0
fi

git pull origin "$BRANCH" --ff-only --quiet

echo "$(date '+%Y-%m-%d %H:%M:%S') — pulled $BEHIND new commit(s) from origin/$BRANCH" >> "$LOG"

# Signal HA that a fresh config is on disk
touch "$SIGNAL_FILE"
