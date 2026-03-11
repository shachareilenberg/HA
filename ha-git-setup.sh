#!/usr/bin/env bash
# ha-git-setup.sh
# Run this ONCE on the HA device (via SSH or the Advanced SSH add-on terminal)
# to initialise /config as a git repo connected to GitHub over SSH.
#
# Prerequisites on the HA device:
#   1. "Advanced SSH & Web Terminal" add-on installed and running.
#   2. An SSH key pair already generated on this device AND the public key
#      added to GitHub: https://github.com/settings/ssh/new
#      If you don't have a key yet, generate one first:
#        ssh-keygen -t ed25519 -C "ha@homeassistant" -f ~/.ssh/id_ed25519 -N ""
#        cat ~/.ssh/id_ed25519.pub   # paste this into GitHub SSH keys
#
# Usage:
#   cd /config
#   bash ha-git-setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

GITHUB_USER="shachareilenberg"
REPO_NAME="HA"
BRANCH="ipad-dashboard"
REMOTE_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"

echo "=== HA Git Setup (SSH) ==="
echo ""

# ── 1. Make sure we are in /config ───────────────────────────────────────────
if [ "$(pwd)" != "/config" ]; then
  echo "ERROR: run this script from /config  (cd /config && bash ha-git-setup.sh)"
  exit 1
fi

# ── 2. Add GitHub to known_hosts so SSH never prompts for host verification ──
echo "Adding GitHub to known_hosts..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null
chmod 600 ~/.ssh/known_hosts
echo "✓ known_hosts updated"

# ── 3. Verify SSH auth works before proceeding ───────────────────────────────
echo ""
echo "Testing SSH connection to GitHub..."
if ssh -T git@github.com -o StrictHostKeyChecking=no 2>&1 | grep -q "successfully authenticated"; then
  echo "✓ SSH authentication OK"
else
  echo "⚠ SSH test inconclusive (this is normal — GitHub closes the connection)."
  echo "  If the next steps fail, ensure your public key is at:"
  echo "  https://github.com/settings/ssh/new"
fi

# ── 4. Set git identity & behaviour ──────────────────────────────────────────
git config --global user.email "ha@homeassistant.local"
git config --global user.name  "Home Assistant"
# Never open an editor for commit/merge messages when running non-interactively
git config --global core.editor "true"
# Always fast-forward only on pull — avoids merge commit prompts
git config --global pull.ff only

# ── 5. Init or connect the repo ──────────────────────────────────────────────
if [ -d .git ]; then
  echo ""
  echo "Git repo already initialised — updating remote to SSH URL."
  git remote set-url origin "$REMOTE_URL" 2>/dev/null || \
    git remote add origin "$REMOTE_URL"
else
  git init
  git remote add origin "$REMOTE_URL"
fi

echo "✓ Remote set to $REMOTE_URL"

# ── 6. Fetch & set up tracking branch ────────────────────────────────────────
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git fetch origin
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git checkout "$BRANCH"
  git branch --set-upstream-to="origin/$BRANCH" "$BRANCH"
else
  git checkout -b "$BRANCH" "origin/$BRANCH"
fi

echo ""
echo "✓ Setup complete. /config is now tracking origin/$BRANCH via SSH"
echo ""
echo "Next steps:"
echo "  1. Restart Home Assistant so it loads the new configuration.yaml."
echo "  2. Tap the Pull button on the dashboard or wait 5 min for the automation."
echo "  3. Check /config/ha-git.log in File Editor to verify pull/push works."
