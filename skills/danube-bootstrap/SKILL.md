---
name: danube-bootstrap
description: Start Danube nodes (standalone, Raft cluster, or edge MQTT gateway), configure auto-TLS/TLS, add or promote nodes, and connect danube mcp. Use for node lifecycle before switching to MCP tools for cluster operations.
---

# Danube Bootstrap

Use this skill to start Danube brokers, form multi-node clusters, set up TLS, and connect `danube mcp`. Once a node is up and reachable, prefer `danube mcp` tools for cluster, topic, schema, RBAC, and diagnostic operations.

## Check the binary

```bash
danube version
```

`danube` is a single binary containing the broker (`danube up`), CLI, web console (`danube console`), and MCP server (`danube mcp`). Running `danube` alone prints the command tree and never starts a server.

## Core rules

- **Preview first:** add `--dry-run` to `danube up <mode>` to verify the resolved ports, data directory, and membership mode without starting anything.
- **One mode per data directory:** Danube records the mode in `<data-dir>/danube-node.json`. Never reuse a `standalone` directory for `cluster` or `edge`. Pick a fresh `--data-dir` or clean up the old directory first.
- **Non-blocking start in agent shells:** `danube up` runs in the foreground. Launch it as a background process, wait until port `6650` (or your `--listen` port) responds, and clean up the PID when done.

## Mode 1: Standalone (local dev, CI, single box)

```bash
danube up standalone --data-dir ./danube-data
```

- Listens on `127.0.0.1:6650` (client gRPC, schema registry, and admin API share one port).
- To accept remote connections: `--listen 0.0.0.0:6650`.
- Verify readiness via MCP `health_check` or `danube cluster status`.

## Mode 2: Cluster (Raft HA, scalable)

`--data-dir` is required in `cluster` mode, plus at most one membership flag: `--single-node`, `--seed-nodes`, or `--join`.

### Option A: Single-node cluster (grow later)

```bash
danube up cluster --data-dir ./data/node1 --single-node
```

### Option B: Multi-node on one machine (seed nodes)

Give each node its own `--data-dir`, `--listen`, and `--raft-port`:

```bash
danube up cluster --data-dir ./data/node1 \
  --listen 127.0.0.1:6650 --raft-port 7650 \
  --seed-nodes 127.0.0.1:7650,127.0.0.1:7651,127.0.0.1:7652

danube up cluster --data-dir ./data/node2 \
  --listen 127.0.0.1:6651 --raft-port 7651 \
  --seed-nodes 127.0.0.1:7650,127.0.0.1:7651,127.0.0.1:7652

danube up cluster --data-dir ./data/node3 \
  --listen 127.0.0.1:6652 --raft-port 7652 \
  --seed-nodes 127.0.0.1:7650,127.0.0.1:7651,127.0.0.1:7652
```

### Option C: Join a running cluster dynamically

A `--join` node only opens its shared `--listen` port after it becomes a member, so it MUST pass `--admin-listen`:

```bash
danube up cluster --data-dir ./data/node2 --join \
  --listen 127.0.0.1:6651 --raft-port 7651 --admin-listen 127.0.0.1:50052
```

Then add and promote it (via MCP `add_cluster_node` + `promote_cluster_node`, or CLI):

```bash
danube cluster node add --node-addr http://127.0.0.1:50052 --endpoint http://127.0.0.1:6650
danube cluster status --endpoint http://127.0.0.1:50052   # read Self Node ID
danube cluster node promote --node-id <NODE_ID> --endpoint http://127.0.0.1:6650
```

## Mode 3: Edge MQTT gateway

```bash
danube up edge --data-dir ./data/edge --name plant-7 \
  --cloud-endpoint http://127.0.0.1:6650 \
  --mqtt-listen 0.0.0.0:1883
```

- When running on the same host as a cluster node, pass non-conflicting `--listen` and `--raft-port` (e.g. `--listen 127.0.0.1:6660 --raft-port 7660`).
- Devices publish over MQTT; Danube buffers locally in a WAL and replicates to `/<name>/ingest` on the cloud cluster.
- For secured cloud clusters, pass `--cloud-token "$DANUBE_CLOUD_TOKEN"` and `--tls-ca` as needed.

## Security bootstrap (`auto-tls` and `tls`)

### Standalone with `auto-tls` (needs `openssl` on host)

```bash
danube up standalone --data-dir ./danube-data --auth auto-tls
```

This generates `<data-dir>/tls/ca.pem`, `ca-key.pem`, `cert.pem`, `key.pem`, `jwt.secret`, and `<data-dir>/bootstrap_admin.token` (`0600`).

Save an admin context for CLI and MCP:

```bash
danube context add local-tls \
  --endpoint https://127.0.0.1:6650 \
  --tls-ca ./danube-data/tls/ca.pem \
  --token "$(cat ./danube-data/bootstrap_admin.token)" \
  --use
```

### Multi-node with `auto-tls`

Multi-node `--auth auto-tls` with `--seed-nodes` or `--join` refuses to start unless `ca.pem`, `ca-key.pem`, and `jwt.secret` already exist in `<data-dir>/tls/`:

1. Export the same `DANUBE_CLUSTER_SECRET` on every node.
2. Start node 1 with `--single-node --auth auto-tls`.
3. Copy `ca.pem`, `ca-key.pem`, and `jwt.secret` from node 1's `<data-dir>/tls/` into node 2 and node 3's `<data-dir>/tls/` (`chmod 600`).
4. Start node 2 and node 3 with `--join --admin-listen ... --auth auto-tls`, then add and promote via `add_cluster_node` / `promote_cluster_node`.

### Custom PKI (`--auth tls`)

Generate a bootstrap token offline using `DANUBE_JWT_SECRET`, then pass `--tls-cert`, `--tls-key`, `--ca-cert`, and `--super-admin`:

```bash
export DANUBE_JWT_SECRET="replace-with-a-32-plus-character-random-secret"
danube auth token create --subject platform-admin --type user --ttl 8760h > ./admin.token
danube up standalone --data-dir ./danube-data --auth tls \
  --tls-cert ./server-cert.pem --tls-key ./server-key.pem \
  --ca-cert ./ca-cert.pem --super-admin platform-admin
```

## Connect `danube mcp`

- **Stdio (IDE / local agents):** `danube mcp --endpoint http://127.0.0.1:6650` (or `--context local-tls`).
- **Secured cluster via env vars:** set `DANUBE_TOKEN` and `DANUBE_TLS_CA` with `--endpoint https://127.0.0.1:6650`.
- **Streamable HTTP:** `danube mcp --http 0.0.0.0:8080` serves `/mcp` (for bearer auth on `/mcp`, use `danube console --http-token ...`).

## Common node flags & env vars

- `--listen` (`DANUBE_LISTEN`, default `127.0.0.1:6650`)
- `--admin-listen` (optional dedicated admin port)
- `--metrics-listen` (Prometheus exporter port)
- `--advertised-addr` (`DANUBE_ADVERTISED_ADDR`)
- `--raft-port` (default `7650`)
- `--wal-dir`, `--role` (`broker` | `lakehouse` | `all`), `--recovery-config`
