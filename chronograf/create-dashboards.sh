#!/bin/bash
# create-dashboards.sh
#
# Creates all 4 HA dashboards via the Chronograf HTTP API.
# Bypasses the Chronograf file-import UI (broken through the HA ingress proxy).
#
# Run from the HA SSH add-on terminal:
#   cd /config/chronograf && bash create-dashboards.sh

set -e

CHRONOGRAF="http://a0d7b954-influxdb:8888/chronograf/v1/dashboards"

# Smoke-test connectivity before looping
if ! curl -sf "$CHRONOGRAF" > /dev/null 2>&1; then
  echo "ERROR: Cannot reach Chronograf at $CHRONOGRAF"
  echo "Make sure the InfluxDB add-on is running."
  exit 1
fi

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
      --data-binary @- > /dev/null

  echo "  Created: $NAME"
done

echo ""
echo "Done. Open Chronograf → Dashboards to see all 4 dashboards."
