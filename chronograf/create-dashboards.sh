#!/bin/bash
# create-dashboards.sh
#
# Creates all 4 HA dashboards via the Chronograf API, routing through
# the HA Supervisor ingress proxy (the only allowed path to Chronograf).
#
# Run from the HA SSH add-on terminal:
#   cd /config/chronograf && bash create-dashboards.sh

set -eo pipefail

SUPERVISOR="http://172.30.32.2"
ADDON_SLUG="a0d7b954_influxdb"

# ── Supervisor token ──────────────────────────────────────────────────────────
if [ -z "$SUPERVISOR_TOKEN" ]; then
  echo "ERROR: \$SUPERVISOR_TOKEN not set. Run from the HA SSH add-on terminal."
  exit 1
fi
echo "Supervisor token: present (${#SUPERVISOR_TOKEN} chars)"

# ── Add-on info ───────────────────────────────────────────────────────────────
echo "Fetching add-on info..."
ADDON_INFO=$(curl -sf "${SUPERVISOR}/addons/${ADDON_SLUG}/info" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}")

INGRESS_ENTRY=$(echo "$ADDON_INFO" | jq -r '.data.ingress_entry')
# ingress_entry = /api/hassio_ingress/TOKEN — extract the token (last path segment)
INGRESS_TOKEN=$(echo "$INGRESS_ENTRY" | awk -F'/' '{print $NF}')

echo "  ingress_entry : $INGRESS_ENTRY"
echo "  ingress_token : ${INGRESS_TOKEN:0:20}..."

# ── Create ingress session ────────────────────────────────────────────────────
echo "Creating ingress session..."
SESSION=$(curl -sf -X POST "${SUPERVISOR}/ingress/session" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  | jq -r '.data.session')
echo "  session: ${SESSION:0:20}..."

COOKIE="Cookie: ingress_session=${SESSION}"

# ── Find working Chronograf API URL ──────────────────────────────────────────
# Try: /ingress/{token}{ingress_entry}/chronograf/v1/dashboards
# Then: /ingress/{token}/chronograf/v1/dashboards
CHRONOGRAF_API=""
for CANDIDATE in \
  "${SUPERVISOR}/ingress/${INGRESS_TOKEN}${INGRESS_ENTRY}/chronograf/v1/dashboards" \
  "${SUPERVISOR}/ingress/${INGRESS_TOKEN}/chronograf/v1/dashboards"
do
  echo "Trying: $CANDIDATE"
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CANDIDATE" -H "$COOKIE")
  echo "  HTTP $CODE"
  if [ "$CODE" = "200" ]; then
    CHRONOGRAF_API="$CANDIDATE"
    break
  fi
done

if [ -z "$CHRONOGRAF_API" ]; then
  echo "ERROR: Cannot reach Chronograf through either URL."
  echo "Check the InfluxDB add-on is running and try again."
  exit 1
fi

# ── Create dashboards ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "Creating dashboards..."

for f in "$SCRIPT_DIR"/0[0-9]-*.json; do
  [ -f "$f" ] || continue
  NAME=$(jq -r '.dashboard.name' "$f")
  echo "  Creating: $NAME"
  jq -c '.dashboard' "$f" | curl -sf -X POST "$CHRONOGRAF_API" \
      -H "Content-Type: application/json" \
      -H "$COOKIE" \
      --data-binary @- > /dev/null
  echo "  Done"
done

echo ""
echo "All dashboards created. Open Chronograf → Dashboards."
