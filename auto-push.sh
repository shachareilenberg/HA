#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# auto-push.sh — debounce wrapper called by the launchd watcher
#
# Waits 10 seconds after the first detected change before committing,
# so rapid consecutive saves are grouped into one commit.
# ─────────────────────────────────────────────────────────────────────────────

sleep 10

cd "$(dirname "$0")"
./push-config.sh "auto: $(date '+%Y-%m-%d %H:%M')"
