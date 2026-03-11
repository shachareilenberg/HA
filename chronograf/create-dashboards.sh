#!/bin/bash
# create-dashboards.sh
#
# Creates all 4 HA dashboards via the Chronograf HTTP API.
# Uses the HA Supervisor ingress proxy (the only external route to Chronograf,
# since it listens on 127.0.0.1:8889 inside the add-on container).
#
# Run from the HA SSH add-on terminal:
#   cd /config/chronograf && bash create-dashboards.sh

set -e

SUPERVISOR="http://172.30.32.2"
ADDON_SLUG="a0d7b954_influxdb"

# ── Check SUPERVISOR_TOKEN ────────────────────────────────────────────────────
if [ -z "$SUPERVISOR_TOKEN" ]; then
  echo "ERROR: \$SUPERVISOR_TOKEN is not set."
  echo "This script must be run from within the HA SSH add-on terminal."
  exit 1
fi

AUTH="Authorization: Bearer ${SUPERVISOR_TOKEN}"

# ── Get the add-on ingress token ──────────────────────────────────────────────
ADDON_INFO=$(curl -sf "${SUPERVISOR}/addons/${ADDON_SLUG}/info" -H "$AUTH")
INGRESS_TOKEN=$(python3 -c "import json,sys; print(json.loads('${ADDON_INFO}')['data']['ingress_token'])" 2>/dev/null)
INGRESS_ENTRY=$(python3 -c "import json,sys; print(json.loads('${ADDON_INFO}')['data']['ingress_entry'])" 2>/dev/null)

if [ -z "$INGRESS_TOKEN" ]; then
  echo "ERROR: Could not read ingress token from supervisor."
  echo "Supervisor response: $ADDON_INFO"
  exit 1
fi

# ── Create an ingress session ─────────────────────────────────────────────────
SESSION_RESP=$(curl -sf -X POST "${SUPERVISOR}/ingress/session" -H "$AUTH")
SESSION=$(python3 -c "import json,sys; print(json.loads('${SESSION_RESP}')['data']['session'])" 2>/dev/null)

if [ -z "$SESSION" ]; then
  echo "ERROR: Could not create ingress session."
  echo "Supervisor response: $SESSION_RESP"
  exit 1
fi

CHRONOGRAF="${SUPERVISOR}/ingress/${INGRESS_TOKEN}${INGRESS_ENTRY}chronograf/v1/dashboards"
COOKIE="Cookie: ingress_session=${SESSION}"

# ── Smoke test ────────────────────────────────────────────────────────────────
if ! curl -sf "$CHRONOGRAF" -H "$COOKIE" > /dev/null; then
  echo "ERROR: Cannot reach Chronograf at $CHRONOGRAF"
  echo "Make sure the InfluxDB add-on is running."
  exit 1
fi

# ── Create dashboards ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Creating dashboards..."

for f in "$SCRIPT_DIR"/0[0-9]-*.json; do
  [ -f "$f" ] || continue

  NAME=$(python3 -c "import json; print(json.load(open('$f'))['dashboard']['name'])")

  python3 -c "
import json, sys
d = json.load(open('$f'))
sys.stdout.write(json.dumps(d['dashboard']))
" | curl -sf -X POST "$CHRONOGRAF" \
      -H 'Content-Type: application/json' \
      -H "$COOKIE" \
      --data-binary @- > /dev/null

  echo "  Created: $NAME"
done

echo ""
echo "Done. Open Chronograf → Dashboards to see all 4 dashboards."
