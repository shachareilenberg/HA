#!/bin/bash
# create-dashboards.sh
#
# Creates all 4 HA dashboards via the Chronograf API, routing through
# the HA Supervisor ingress proxy.
#
# Run from the HA SSH add-on terminal:
#   cd /config/chronograf && bash create-dashboards.sh

SUPERVISOR="http://172.30.32.2"
ADDON_SLUG="a0d7b954_influxdb"

# ── 1. Supervisor token ───────────────────────────────────────────────────────
if [ -z "$SUPERVISOR_TOKEN" ]; then
  echo "ERROR: \$SUPERVISOR_TOKEN not set."
  exit 1
fi
echo "1. Token: present (${#SUPERVISOR_TOKEN} chars)"

# ── 2. Add-on info ────────────────────────────────────────────────────────────
echo "2. Fetching add-on info..."
INFO=$(curl -s "${SUPERVISOR}/addons/${ADDON_SLUG}/info" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}")
echo "   raw (first 200): ${INFO:0:200}"

INGRESS_ENTRY=$(echo "$INFO" | jq -r '.data.ingress_entry // empty' 2>/dev/null)
INGRESS_TOKEN=$(echo "$INGRESS_ENTRY" | awk -F'/' '{print $NF}')
echo "   ingress_entry : $INGRESS_ENTRY"
echo "   ingress_token : $INGRESS_TOKEN"

if [ -z "$INGRESS_TOKEN" ]; then
  echo "ERROR: Could not extract ingress token. Check the add-on slug and info above."
  exit 1
fi

# ── 3. Find working Chronograf API URL ────────────────────────────────────────
# Session creation returns 403 from SSH add-on (only HA frontend can do that).
# Try: supervisor bearer token | X-Ingress-Token header | no auth
echo "3. Testing Chronograf API access..."
CHRONOGRAF_API=""

BASE_URL="${SUPERVISOR}/ingress/${INGRESS_TOKEN}"

for AUTH_HEADER in \
  "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  "X-Ingress-Token: ${INGRESS_TOKEN}" \
  "X-Supervisor-Token: ${SUPERVISOR_TOKEN}"
do
  for URL in \
    "${BASE_URL}/chronograf/v1/dashboards" \
    "${BASE_URL}${INGRESS_ENTRY}/chronograf/v1/dashboards"
  do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" -H "$AUTH_HEADER")
    echo "   [${AUTH_HEADER%%:*}] $URL → HTTP $CODE"
    if [ "$CODE" = "200" ]; then
      CHRONOGRAF_API="$URL"
      CHRONOGRAF_AUTH="$AUTH_HEADER"
      break 2
    fi
  done
done

if [ -z "$CHRONOGRAF_API" ]; then
  echo ""
  echo "All direct paths blocked. Trying via HA core host..."
  # HA hostname in the hassio network
  for HA_HOST in "homeassistant" "172.30.32.0"; do
    URL="http://${HA_HOST}:8123/api/hassio_ingress/${INGRESS_TOKEN}/chronograf/v1/dashboards"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" \
      -H "Authorization: Bearer ${SUPERVISOR_TOKEN}")
    echo "   $URL → HTTP $CODE"
    if [ "$CODE" = "200" ]; then
      CHRONOGRAF_API="$URL"
      CHRONOGRAF_AUTH="Authorization: Bearer ${SUPERVISOR_TOKEN}"
      break
    fi
  done
fi

if [ -z "$CHRONOGRAF_API" ]; then
  echo ""
  echo "BLOCKED: Cannot reach Chronograf from SSH add-on."
  echo "All ingress paths require a browser session or HA core context."
  echo ""
  echo "To create dashboards, run instead from HA Developer Tools:"
  echo "  Service: shell_command.create_chronograf_dashboards"
  echo "  (after adding it to configuration.yaml — see README.md)"
  exit 1
fi

echo "   Using: $CHRONOGRAF_API"
echo "   Auth:  ${CHRONOGRAF_AUTH%%:*}"

# ── 5. Create dashboards ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo ""
echo "5. Creating dashboards..."

for f in "$SCRIPT_DIR"/0[0-9]-*.json; do
  [ -f "$f" ] || continue
  NAME=$(jq -r '.dashboard.name' "$f")
  echo "   Creating: $NAME"
  RESULT=$(jq -c '.dashboard' "$f" | curl -s -X POST "$CHRONOGRAF_API" \
    -H "Content-Type: application/json" \
    -H "$CHRONOGRAF_AUTH" \
    --data-binary @-)
  if echo "$RESULT" | jq -e '.id' > /dev/null 2>&1; then
    echo "   → OK (id: $(echo "$RESULT" | jq -r '.id'))"
  else
    echo "   → FAILED: ${RESULT:0:150}"
  fi
done

echo ""
echo "Done. Open Chronograf → Dashboards."
