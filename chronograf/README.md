# Chronograf Dashboards for Home Assistant

Four importable dashboard JSON files for visualising HA data logged to InfluxDB v1 (`ha_data` database).

## Prerequisites

- InfluxDB TICK stack add-on running on HA
- `ha_data` database created (Chronograf → Admin → Databases → Create Database → `ha_data`)
- `influxdb:` block active in `configuration.yaml` (already present in this repo)

## How to Create the Dashboards

The Chronograf "Import Dashboard" file upload is broken through the HA ingress
proxy. Use the API script instead.

**How it works:** Chronograf binds to `127.0.0.1:8889` inside the container,
so it's not reachable from outside. The script routes through the HA Supervisor
ingress proxy (`172.30.32.2`) — the same path the browser uses — which is the
only allowed external route per the nginx config.

**Steps:**

1. SSH into HA (via the SSH & Web Terminal add-on)
2. Run:
   ```bash
   cd /config/chronograf && bash create-dashboards.sh
   ```
3. Open Chronograf → **Dashboards** — all 4 dashboards will appear

The `$SUPERVISOR_TOKEN` env var is automatically set in the SSH add-on shell.

## Dashboards

| File | Contents |
|---|---|
| `01-home-overview.json` | At-a-glance: AC states table, away/good-night timeline, boiler & heater timeline, lights snapshot |
| `02-ac-climate.json` | AC deep-dive: temperature trends (7 d), HVAC mode table, daily activity bar |
| `03-lights-usage.json` | Lights: per-room on/off step charts, daily activity bar (14 d), late-night panel |
| `04-presence-devices.json` | Presence & devices: away/good-night, fans, TV + Yamaha, boiler & heater |

## Data Notes

The HA InfluxDB v1 integration stores:
- **`value` field** — `1.0` when state is `"on"`, `0.0` when `"off"` (binary entities)
- **`current_temperature` field** — current temperature for `climate.*` entities
- **`temperature` field** — setpoint for `climate.*` entities
- **`state` field** — string state, always present
- **`entity_id` tag** — used by all queries to target specific entities

Because HA writes data only on **state changes** (not every second), the step-line charts correctly represent the last known state between events via `fill(previous)`.

## Adjusting Time Ranges

All time-series panels respect the Chronograf dashboard time picker (`:dashboardTime:` / `:interval:` template variables). Status/snapshot panels always show the last 24 h regardless of the picker.
