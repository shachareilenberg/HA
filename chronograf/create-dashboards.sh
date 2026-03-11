#!/bin/bash
# create-dashboards.sh
#
# Creates all 4 HA dashboards via the Chronograf HTTP API.
# Bypasses the Chronograf file-import UI (broken through the HA ingress proxy).
#
# Run this from the HA SSH terminal (HA OS / SSH add-on):
#   bash /config/chronograf/create-dashboards.sh
#
# Requirements: docker, python3 (both present on HA OS by default).

set -e

# ── Find the InfluxDB add-on container ────────────────────────────────────────
CONTAINER=$(docker ps --format '{{.Names}}' | grep -iE 'influxdb|a0d7b954' | head -1)

if [ -z "$CONTAINER" ]; then
  echo "ERROR: Cannot find the InfluxDB add-on container."
  echo "Make sure the InfluxDB add-on is running in Home Assistant."
  exit 1
fi

echo "Using container: $CONTAINER"
echo ""

# ── Create each dashboard ─────────────────────────────────────────────────────
CHRONOGRAF="http://localhost:8888/chronograf/v1/dashboards"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for f in "$SCRIPT_DIR"/0[0-9]-*.json; do
  [ -f "$f" ] || continue

  NAME=$(python3 -c "import json; print(json.load(open('$f'))['dashboard']['name'])")

  # Extract the dashboard object and POST it to Chronograf's API inside the container
  python3 -c "
import json, sys
d = json.load(open('$f'))
sys.stdout.write(json.dumps(d['dashboard']))
" | docker exec -i "$CONTAINER" \
      curl -sf -X POST "$CHRONOGRAF" \
        -H 'Content-Type: application/json' \
        --data-binary @- > /dev/null

  echo "  Created: $NAME"
done

echo ""
echo "Done. Open Chronograf and click Dashboards to see all 4 dashboards."
