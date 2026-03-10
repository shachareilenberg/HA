#!/usr/bin/env bash
# check-updates.sh
# Runs periodically via launchd (every 5 min). Fetches from the remote, and if
# the local branch is strictly behind with a clean tree, pulls the new commits
# then POSTs to HA's webhook so the dashboard banner appears immediately.
#
# ── Configuration ──────────────────────────────────────────────────────────────
# Set HA_URL to your Home Assistant instance URL (no trailing slash).
# You can also export HA_URL from the shell environment to override this.
HA_URL="${HA_URL:-http://homeassistant.local:8123}"
WEBHOOK_ID="ha-config-updated"
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/tmp/ha-check-updates.log"

cd "$REPO_DIR"

BRANCH="$(git branch --show-current)"

# Fetch quietly — updates origin/* refs without touching the working tree
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

# Notify HA via webhook — HA will show the dashboard banner and a notification.
# This works regardless of whether HA runs on this Mac or a separate device.
if curl -s --max-time 10 \
        -X POST "${HA_URL}/api/webhook/${WEBHOOK_ID}" \
        -o /dev/null 2>/dev/null; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') — HA notified via webhook (${HA_URL})" >> "$LOG"
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') — webhook call failed — is HA reachable at ${HA_URL}?" >> "$LOG"
fi
