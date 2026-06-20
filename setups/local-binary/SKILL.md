---
name: local-binary
description: "Download pre-built Danube binaries and run brokers on the host. Use for quick testing without Docker or build tools. Supports standalone, cluster, and edge modes."
---

# Skill: Local Binary Setup

## Objective

Download pre-built Danube binaries from GitHub releases and run brokers directly on the host machine. The simplest setup — no Docker, no build tools, just download and run.

## Required Setup
None — this IS the setup.

## Required Tools
- `curl` or `wget` (for downloading binaries)
- `tar` (for extracting archives)

## How to Run

Use the setup script. It handles binary download, OS detection, config copying, broker startup, readiness polling, and health verification — all in one command.

```bash
# Standalone (single broker, no config needed)
./scripts/setup_local_binary.sh standalone v0.15.0

# 3-broker cluster
./scripts/setup_local_binary.sh cluster v0.15.0 3

# Cleanup everything
./scripts/cleanup.sh
```

The script is at `scripts/setup_local_binary.sh` — read it for the full implementation details.

## Modes

### Standalone
- Runs a single broker with `--mode standalone`
- **No config file needed** — the broker auto-generates sensible defaults
- Broker listens on `127.0.0.1:6650` (client) and `127.0.0.1:50051` (admin)
- Raft runs in single-node mode — `cluster status`, `brokers balance`, and `brokers leader-broker` are **not available** and will return errors
- Verification: `danube-admin brokers list` shows one broker as `active`

### Cluster
- Runs N brokers (default 3) with `--config-file` and port offsets
- Config is copied from `configs/default.yml` into `$TEST_RUN/danube_broker.yml`
- Seed nodes are passed via `--seed-nodes` CLI flag (not embedded in the config)
- Raft elects a leader within ~10 seconds
- Verification: `danube-admin brokers list` shows all brokers `active`, `cluster status` shows a leader

### Edge (manual — not in setup script)
Edge mode requires a running cluster first. It is not covered by the setup script because it depends on having a cluster already up.

1. Start a cluster (standalone or multi-broker) using the script
2. Create the edge namespace on the cluster: `danube-admin namespaces create edge1`
   - The namespace name must match `edge.edge_name` in `configs/edge.yaml`
   - Without this, the edge broker fails with `"Unable to find the namespace"`
3. Copy the edge config: `cp configs/edge.yaml "$TEST_RUN/edge.yaml"`
   - `cluster_url` defaults to `http://127.0.0.1:6650` — correct for local setup
   - `schema_subject` in topic mappings is **optional** — remove it for basic testing, otherwise the referenced schemas must be pre-registered on the cluster
4. Start the edge broker from inside `$TEST_RUN/`:
   ```bash
   "$DANUBE_BIN/danube-broker" \
     --mode edge \
     --data-dir "./data/edge" \
     --edge-config "./edge.yaml" \
     --broker-addr "0.0.0.0:6653" \
     --admin-addr "0.0.0.0:50054" \
     --raft-addr "0.0.0.0:7653" \
     > "./logs/edge_broker.log" 2>&1 &
   ```
5. Test MQTT ingestion (requires `mosquitto_pub`):
   ```bash
   mosquitto_pub -h 127.0.0.1 -p 1883 \
     -t "device/sensor-1/telemetry" \
     -m '{"temperature": 25.5, "device_id": "sensor-1"}'
   ```

## Key Concepts

### Binary Downloads Are Shared
Binaries live in `bin/<version>/` at the repo root and are reused across all test runs. The script skips download if they already exist.

Release URL pattern:
```
https://github.com/danube-messaging/danube/releases/download/<VERSION>/<BINARY>-<VERSION>-<OS_TARGET>.<EXT>
```

Three binaries are downloaded: `danube-broker`, `danube-cli`, `danube-admin`.

### Brokers Run From Inside $TEST_RUN
The script `cd`s into the test run directory before starting brokers. This ensures all relative paths in the config (e.g., `local_wal_root: "./data/wal"`) resolve inside the test run — keeping all data isolated.

### Config Path Behavior
- `meta_store.data_dir` — overridden by `--data-dir` CLI flag (Raft data)
- `storage.local_wal_root` — **NOT overridden by any CLI flag**. It reads from the config file and resolves relative to the broker's working directory. This is why brokers must run from `$TEST_RUN/`.

### CLI Quirks
- `danube-broker` does **not** support `--version` or `--help`. Only `danube-admin` and `danube-cli` support `--version`.
- Readiness checks should use `danube-admin brokers list` — it works in all modes (standalone, cluster, edge).
- `danube-admin cluster status`, `brokers leader-broker`, and `brokers balance` only work in cluster mode.

## Verification

The setup scripts (`scripts/setup_local_binary.sh`) run these checks automatically. The expected output is documented here so the AI can confirm the setup is healthy.

### `danube-admin brokers list`

All brokers must show status `active`. In cluster mode, one broker has role `Cluster_Leader`, the rest are `Cluster_Follower`.

```text
BROKER ID       STATUS   ADDRESS              ROLE              ADMIN ADDR
---------------------------------------------------------------------------
5804156356...   active   http://0.0.0.0:6650  Cluster_Leader    http://0.0.0.0:50051
9393761688...   active   http://0.0.0.0:6651  Cluster_Follower  http://0.0.0.0:50052
1293191161...   active   http://0.0.0.0:6652  Cluster_Follower  http://0.0.0.0:50053
```

In standalone mode, one broker appears with role `None`.

### `danube-admin cluster status` (cluster mode only)

The `Leader` field must show a valid node ID (not `none`). All broker node IDs should appear in the `Voters` list.

```text
Raft Cluster Status:
  Self Node ID:  5804156356532636512
  Raft Address:  0.0.0.0:7650
  Leader:        5804156356532636512
  Term:          1
  Last Applied:  18
  Voters:        [5804156356532636512, 9393761688591103413, 12931911617355319510]
```

**Fail indicators:**
- Any broker with status other than `active`
- `Leader: none` in cluster status (no leader elected)
- Fewer voters than expected brokers
- `ERROR`, `PANIC`, or `FATAL` in broker logs: `grep -i "ERROR\|PANIC\|FATAL" "$TEST_RUN/logs/"*.log`

## Troubleshooting

- **Binary not found or wrong architecture**: The script auto-detects OS/arch. If it fails, check `uname -s` and `uname -m` and verify the release page has a matching archive.

- **Permission denied**: `chmod +x bin/<version>/danube-*`

- **Port already in use**: `ss -lntp | grep <port>`. Kill the conflicting process or run `./scripts/cleanup.sh` first.

- **Raft cluster not forming**: Check logs: `tail -20 "$TEST_RUN/logs/broker_6650.log"`. Ensure seed_nodes are correct.

- **Standalone mode ignores config file**: By design. `--mode standalone` auto-generates config. To use a custom config, omit `--mode standalone` and use `--config-file` instead.

- **Edge broker: "Unable to find the namespace"**: Create the namespace first: `danube-admin namespaces create <edge_name>`.

- **Edge broker: stale Raft data**: Delete the edge data dir before restarting: `rm -rf $TEST_RUN/data/edge`

- **Edge broker: "schema not resolved"**: Remove `schema_subject` from topic mappings in the edge config, or pre-register the schemas on the cluster first.
