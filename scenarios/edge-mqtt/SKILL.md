---
name: edge-mqtt
description: "Test the Danube Edge broker as an MQTT gateway — topic mapping with wildcard extraction, schema validation at the edge, store-and-forward replication to the cluster, and full pipeline verification."
---

# Scenario: Edge MQTT Replication

## Objective

Test the Danube Edge broker — MQTT devices publish messages to the edge gateway, which validates payloads against schemas, extracts attributes from MQTT wildcards, stores messages in a local WAL, and replicates them to the cluster in the background.

## When to Use

- User wants to test "edge", "MQTT", "IoT", "gateway", "replication"
- User wants to verify MQTT-to-Danube topic mapping
- User wants to test schema validation at the edge
- User wants to test store-and-forward during cluster unavailability

## Compatible Infrastructure

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | — | ✅ | 3-node cluster + 1 edge broker, MQTT on port 1883 |
| Local Source | — | ✅ | Same — build from source includes edge mode |

Edge tests require a **cluster** (the edge replicates to a cluster). The edge broker runs as a separate process in `--mode edge` with its own `edge.yaml` config. Requires `paho-mqtt` Python package for MQTT publishing.

## AI Decision Flow

### 1. Which edge aspect to test?

| User says | Test Flow |
|-----------|-----------|
| "basic", "replication", "pipeline" | **Full Pipeline** — MQTT publish → edge → cluster consumer, verify end-to-end |
| "schema", "validation", "enforce" | **Schema Validation** — valid payload accepted, invalid payload dropped at edge |
| "mapping", "wildcard", "attributes" | **Topic Mapping** — verify MQTT wildcard extraction into Danube message attributes |
| "store and forward", "offline", "resilience" | **Store-and-Forward** — publish while cluster is down, verify replication after recovery |
| *(unclear)* | Default: **Full Pipeline** |

### 2. MQTT client

The Edge scenario uses MQTT as the ingestion protocol — not the Danube client libraries for producing. Danube client libraries are used only on the cluster side (consumer subscribing to verify replication).

## Predefined Scripts

This scenario ships with helper scripts in `scenarios/edge-mqtt/scripts/` (copied from the Danube repo's `scripts/edge-e2e/`):

- **`edge-e2e-local.sh`** — Sets up the complete edge infrastructure: 3-broker cluster + edge broker + namespace + schema. Usage:
  ```bash
  ./scenarios/edge-mqtt/scripts/edge-e2e-local.sh --keep-alive
  # Or skip build if binaries exist:
  ./scenarios/edge-mqtt/scripts/edge-e2e-local.sh --skip-build --keep-alive
  ```

- **`test_mqtt_ingestion.py`** — Runs 4 MQTT E2E tests: valid payload, raw payload, invalid payload (accept-but-drop), full pipeline (MQTT → edge → cluster consumer). Usage:
  ```bash
  pip install -r ./scenarios/edge-mqtt/scripts/requirements.txt
  python3 ./scenarios/edge-mqtt/scripts/test_mqtt_ingestion.py
  ```

- **`requirements.txt`** — Python dependencies: `paho-mqtt==1.6.1`, `danube-client>=0.5.0`

## Execution Steps

### Step 1: Set Up Edge Infrastructure

The edge requires a cluster + edge broker. Two options:

**Option A: Use the predefined setup script** (recommended)
```bash
./scenarios/edge-mqtt/scripts/edge-e2e-local.sh --keep-alive

# Or skip the build if binaries already exist:
./scenarios/edge-mqtt/scripts/edge-e2e-local.sh --skip-build --keep-alive
```

This script:
1. Starts a 3-broker cluster
2. Creates the `edge1` namespace
3. Registers the `telemetry-events` schema on the cluster
4. Generates `edge.yaml` with topic mappings
5. Starts the edge broker in `--mode edge`

**Option B: Manual setup** (if using downloaded binaries)

1. Start a 3-node cluster (via `scripts/setup_local_binary.sh cluster`)
2. Create namespace and schema:
```bash
danube-admin namespaces create edge1
danube-admin schemas register telemetry-events \
  --schema-type json_schema \
  --schema '{"type":"object","properties":{"temperature":{"type":"number"},"device_id":{"type":"string"}},"required":["temperature"]}' \
  --description "Edge telemetry events schema"
```

3. Create `edge.yaml`:
```yaml
edge:
  edge_name: "edge1"
  cluster_url: "http://127.0.0.1:6650"
  token: ""
  heartbeat_interval_ms: 10000

replicator:
  batch_size: 100
  batch_timeout_ms: 1000

mqtt:
  listener: "0.0.0.0:1883"
  topic_mappings:
    - mqtt_pattern: "device/+/telemetry"
      danube_topic: "/edge1/telemetry"
      schema_subject: "telemetry-events"
      validation_policy: "enforce"
      extract_attributes:
        device_id: "$1"
    - mqtt_pattern: "#"
      danube_topic: "/edge1/raw"
  ingestion:
    batch_size: 100
    batch_timeout_ms: 500
```

4. Start the edge broker:
```bash
danube-broker --mode edge \
  --broker-addr 0.0.0.0:6653 --admin-addr 0.0.0.0:50054 \
  --raft-addr 0.0.0.0:7653 --data-dir $TEST_RUN/data/edge-1 \
  --edge-config edge.yaml
```

### Step 2a: Full Pipeline (if selected)

Run the predefined test script:
```bash
pip install -r ./scenarios/edge-mqtt/scripts/requirements.txt
python3 ./scenarios/edge-mqtt/scripts/test_mqtt_ingestion.py
```

This runs 4 tests:
1. **Valid Schema Payload** — publish valid JSON to `device/sensor-1/telemetry` → PUBACK received
2. **Raw Bytes Payload** — publish raw bytes to `device/sensor-1/raw` → PUBACK received
3. **Invalid Schema Payload** — publish invalid JSON (missing required "temperature") → PUBACK received but message dropped silently
4. **Full Pipeline** — publish valid payload via MQTT, verify it arrives on cluster consumer via Danube client, verify invalid payloads did NOT leak to cluster

### Step 2b: Schema Validation (if selected)

Focus on edge-side validation behavior:

1. Publish valid JSON to `device/sensor-1/telemetry`:
```python
import paho.mqtt.client as mqtt
import json

client = mqtt.Client("schema-test")
client.connect("127.0.0.1", 1883)
# Valid: has required "temperature" field
client.publish("device/sensor-1/telemetry", json.dumps({"temperature": 25.5, "device_id": "s1"}), qos=1)
```

2. Publish invalid JSON (missing required field):
```python
# Invalid: missing "temperature"
client.publish("device/sensor-1/telemetry", json.dumps({"humidity": 60}), qos=1)
```

3. Verify on cluster: only valid messages arrive, invalid ones are dropped at the edge

### Step 2c: Topic Mapping (if selected)

Verify MQTT wildcard captures become Danube message attributes:

1. Publish to `device/sensor-42/telemetry`
2. On cluster, consume from `/edge1/telemetry`
3. Verify message has attribute `device_id = sensor-42` (extracted from `+` wildcard)
4. Publish to `device/sensor-99/telemetry`
5. Verify attribute `device_id = sensor-99`

### Step 2d: Store-and-Forward (if selected)

1. Publish messages via MQTT while cluster is up — verify they replicate
2. Stop all cluster brokers (simulating network outage)
3. Publish more messages via MQTT — they should be accepted (stored in local WAL)
4. Restart cluster brokers
5. Verify all messages (both from before and during outage) arrive on the cluster consumer

## Verification

| Test | Pass Criteria |
|------|--------------|
| **Full Pipeline** | All 4 tests pass (valid accepted, raw accepted, invalid dropped, full pipeline verified) |
| **Schema Validation** | Valid payloads reach cluster, invalid payloads dropped at edge (never reach cluster) |
| **Topic Mapping** | MQTT wildcards extracted as Danube message attributes (device_id matches MQTT topic segment) |
| **Store-and-Forward** | Messages published during cluster outage are replicated after cluster recovery |

```bash
# Key verification
# MQTT connectivity
nc -zv 127.0.0.1 1883

# Edge broker status
DANUBE_ADMIN_ENDPOINT=http://127.0.0.1:50054 danube-admin brokers list

# Cluster topics (edge-created)
danube-admin topics list --namespace edge1
danube-admin topics describe /edge1/telemetry
```

## Cleanup

This scenario only cleans up edge-related resources. See `setups/SKILL.md` → **Cleanup** for cluster teardown.

```bash
# Stop edge broker
kill $(cat edge_broker.pid)

# Topics created by the edge are managed by the cluster
danube-admin topics delete /edge1/telemetry
danube-admin topics delete /edge1/raw
danube-admin namespaces delete edge1
```
