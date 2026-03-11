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

# ── 3. Create ingress session ─────────────────────────────────────────────────
echo "3. Creating ingress session..."
SESSION_RAW=$(curl -s -X POST "${SUPERVISOR}/ingress/session" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}")
echo "   raw response: $SESSION_RAW"

# Supervisor may return raw token string OR {"result":"ok","data":{"session":"..."}}
SESSION=$(echo "$SESSION_RAW" | jq -r '.data.session // empty' 2>/dev/null)
if [ -z "$SESSION" ]; then
  SESSION="$SESSION_RAW"  # use raw value if not JSON
fi
echo "   session: ${SESSION:0:30}..."

COOKIE="Cookie: ingress_session=${SESSION}"

# ── 4. Find working Chronograf API URL ────────────────────────────────────────
echo "4. Testing Chronograf URLs..."
CHRONOGRAF_API=""
for URL in \
  "${SUPERVISOR}/ingress/${INGRESS_TOKEN}/chronograf/v1/dashboards" \
  "${SUPERVISOR}/ingress/${INGRESS_TOKEN}${INGRESS_ENTRY}/chronograf/v1/dashboards"
do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" -H "$COOKIE")
  echo "   $URL"
  echo "   → HTTP $CODE"
  if [ "$CODE" = "200" ]; then
    CHRONOGRAF_API="$URL"
    break
  fi
done

if [ -z "$CHRONOGRAF_API" ]; then
  echo ""
  echo "ERROR: Cannot reach Chronograf through any URL."
  echo "Make sure the InfluxDB add-on is running and try again."
  exit 1
fi

echo "   Using: $CHRONOGRAF_API"

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
    -H "$COOKIE" \
    --data-binary @-)
  if echo "$RESULT" | jq -e '.id' > /dev/null 2>&1; then
    echo "   → OK (id: $(echo "$RESULT" | jq -r '.id'))"
  else
    echo "   → FAILED: ${RESULT:0:150}"
  fi
done

echo ""
echo "Done. Open Chronograf → Dashboards."
