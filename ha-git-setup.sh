#!/usr/bin/env bash
# ha-git-setup.sh
# Run this ONCE on the HA device (via SSH or the Advanced SSH add-on terminal)
# to initialise /config as a git repo connected to GitHub.
#
# Prerequisites on the HA device:
#   1. "Advanced SSH & Web Terminal" add-on installed and running.
#   2. A GitHub Personal Access Token (PAT) with repo read/write scope.
#      Create one at: https://github.com/settings/tokens → "Generate new token (classic)"
#      Scopes required: repo (full)
#
# Usage:
#   cd /config
#   bash ha-git-setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

GITHUB_USER="shachareilenberg"
REPO_NAME="HA"
BRANCH="ipad-dashboard"   # current working branch
REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

echo "=== HA Git Setup ==="
echo ""

# ── 1. Make sure we are in /config ───────────────────────────────────────────
if [ "$(pwd)" != "/config" ]; then
  echo "ERROR: run this script from /config  (cd /config && bash ha-git-setup.sh)"
  exit 1
fi

# ── 2. Store GitHub credentials so git push/pull don't prompt ────────────────
echo ""
read -rp "GitHub Personal Access Token (will be stored in ~/.git-credentials): " PAT
git config --global credential.helper store
echo "https://${GITHUB_USER}:${PAT}@github.com" > ~/.git-credentials
chmod 600 ~/.git-credentials

# ── 3. Set git identity ───────────────────────────────────────────────────────
git config --global user.email "ha@homeassistant.local"
git config --global user.name  "Home Assistant"

# ── 4. Init or connect the repo ──────────────────────────────────────────────
if [ -d .git ]; then
  echo "Git repo already initialised — skipping git init."
  # Make sure remote points to the right URL
  git remote set-url origin "$REMOTE_URL" 2>/dev/null || \
    git remote add origin "$REMOTE_URL"
else
  git init
  git remote add origin "$REMOTE_URL"
fi

# ── 5. Fetch & set up tracking branch ────────────────────────────────────────
git fetch origin
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  # Branch already exists locally
  git checkout "$BRANCH"
  git branch --set-upstream-to="origin/$BRANCH" "$BRANCH"
else
  git checkout -b "$BRANCH" "origin/$BRANCH"
fi

echo ""
echo "✓ Setup complete. /config is now tracking origin/$BRANCH"
echo ""
echo "Next steps:"
echo "  1. Restart Home Assistant so it loads the new configuration.yaml."
echo "  2. Check Developer Tools → States for binary_sensor.config_update_available."
echo "  3. Push a test commit from any device and wait up to 5 minutes"
echo "     for the dashboard banner to appear."
