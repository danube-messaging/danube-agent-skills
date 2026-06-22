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

Present these options to the user **exactly as listed**:

1. **Full Pipeline**: Run the predefined `test_mqtt_ingestion.py` script end-to-end. Tests valid payload acceptance, raw payload acceptance, schema enforcement (invalid payloads dropped at the edge), and full MQTT → edge → cluster consumer replication. Covers the entire edge pipeline in a single run.

2. **Store-and-Forward**: Publish MQTT messages while the cluster is unavailable (brokers stopped), verify the edge accepts and stores them locally in its WAL. Restart the cluster and verify all buffered messages are replicated — no data loss during outage.

Each aspect maps to the corresponding `Step 2x` in Execution Steps below.

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

### Step 2b: Store-and-Forward (if selected)

1. Publish messages via MQTT while cluster is up — verify they replicate
2. Stop all cluster brokers (simulating network outage)
3. Publish more messages via MQTT — they should be accepted (stored in local WAL)
4. Restart cluster brokers
5. Verify all messages (both from before and during outage) arrive on the cluster consumer

## Verification

| Test | Pass Criteria |
|------|--------------|
| **Full Pipeline** | All 4 tests pass (valid accepted, raw accepted, invalid dropped, full pipeline verified) |
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
