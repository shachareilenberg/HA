#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# push-config.sh — commit & push HA config changes to the current git branch
#
# Usage:
#   ./push-config.sh                      # auto-generates a timestamped message
#   ./push-config.sh "my commit message"  # use a custom message
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# ── Build commit message ─────────────────────────────────────────────────────
if [[ $# -ge 1 && -n "$1" ]]; then
  MSG="$1"
else
  MSG="chore: update config $(date '+%Y-%m-%d %H:%M')"
fi

# ── Check there is anything to commit ────────────────────────────────────────
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
  echo "Nothing to commit — working tree is clean."
  exit 0
fi

# ── Stage all tracked + new files (gitignore keeps secrets out) ──────────────
git add -A

echo ""
echo "Staged changes:"
git diff --cached --stat
echo ""

# ── Commit ───────────────────────────────────────────────────────────────────
git commit -m "$MSG"

# ── Push to the current branch ───────────────────────────────────────────────
BRANCH="$(git branch --show-current)"
git push origin "$BRANCH"

echo ""
echo "✓ Pushed to origin/$BRANCH"
