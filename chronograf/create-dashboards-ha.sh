#!/bin/bash
# create-dashboards-ha.sh
#
# Runs inside the HA core container (via shell_command).
# HA core has permission to create supervisor ingress sessions.
#
# Trigger from HA Developer Tools → Services:
#   Service: shell_command.create_chronograf_dashboards
#
# Or run directly from HA SSH terminal:
#   bash /config/chronograf/create-dashboards-ha.sh

SUPERVISOR="http://172.30.32.2"
ADDON_SLUG="a0d7b954_influxdb"

# HA core has SUPERVISOR_TOKEN too
if [ -z "$SUPERVISOR_TOKEN" ]; then
  echo "ERROR: SUPERVISOR_TOKEN not set."
  exit 1
fi

# Get ingress entry
INGRESS_ENTRY=$(curl -s "${SUPERVISOR}/addons/${ADDON_SLUG}/info" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['ingress_entry'])")
INGRESS_TOKEN=$(echo "$INGRESS_ENTRY" | awk -F'/' '{print $NF}')
echo "ingress_entry: $INGRESS_ENTRY"
echo "ingress_token: $INGRESS_TOKEN"

# Create ingress session (HA core is allowed to do this)
# Supervisor returns {"result":"ok","data":{"session":"TOKEN"}} — extract the token
SESSION=$(curl -s -X POST "${SUPERVISOR}/ingress/session" \
  -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['session'])")
echo "session: ${SESSION:0:30}..."

CHRONOGRAF_API="${SUPERVISOR}/ingress/${INGRESS_TOKEN}/chronograf/v1/dashboards"
COOKIE="Cookie: ingress_session=${SESSION}"

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CHRONOGRAF_API" -H "$COOKIE")
echo "Chronograf reachable: HTTP $CODE"

if [ "$CODE" != "200" ]; then
  echo "ERROR: Cannot reach Chronograf (HTTP $CODE)"
  exit 1
fi

SCRIPT_DIR="/config/chronograf"
echo "Looking for JSON files in: $SCRIPT_DIR"
ls "$SCRIPT_DIR"/0[0-9]-*.json 2>&1

for f in "$SCRIPT_DIR"/0[0-9]-*.json; do
  [ -f "$f" ] || { echo "No files matched"; break; }
  NAME=$(python3 -c "import json; print(json.load(open('$f'))['dashboard']['name'])")
  echo "Creating: $NAME"
  RESULT=$(python3 -c "
import json, sys
d = json.load(open('$f'))['dashboard']
d.pop('id', None)
sys.stdout.write(json.dumps(d))
" \
    | curl -s -w "\nHTTP:%{http_code}" -X POST "$CHRONOGRAF_API" \
      -H "Content-Type: application/json" -H "$COOKIE" \
      --data-binary @-)
  echo "  Response: ${RESULT:0:300}"
done
echo "Done."
