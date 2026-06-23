---
name: setups
description: "Overview of all Danube setup methods. Use when deciding how to run Danube — local binary, local source, Docker Compose, or Kubernetes."
---

# Skill: Setups — How to Run Danube

## Objective

Provide four methods for running Danube brokers. Each method has a dedicated SKILL.md with step-by-step instructions. The AI picks the method based on the user's environment and scenario requirements.

## Setup Methods

| Method | Directory | Best For | Prerequisites |
|--------|-----------|----------|---------------|
| **Local Binary** | `local-binary/` | Quick standalone tests, no Docker needed | curl/wget |
| **Local Source** | `local-source/` | Developing on Danube codebase | Rust toolchain, Danube repo |
| **Docker Compose** | `docker-compose/` | Multi-broker clusters, most scenarios | Docker, Docker Compose |
| **Kubernetes** | `kubernetes/` | K8s-native deployment, production testing | kubectl, helm, K8s cluster |

> **Note**: `--mode standalone` (single broker, no config) is only available from **local-binary** and **local-source** setups. Docker Compose and Kubernetes always run in cluster mode.

## Decision Matrix

| Question | If YES | If NO |
|----------|--------|-------|
| Developing on Danube source? | `local-source/` | Continue |
| Need multi-broker cluster? | `docker-compose/` (preferred) or `local-binary/` (multi-process) | Continue |
| Need Kubernetes features? | `kubernetes/` | Continue |
| Need MinIO/S3 storage? | `docker-compose/` (with-cloud-storage) | Continue |
| Default | `local-binary/` (standalone) or `docker-compose/` (quickstart) | — |

## Test-Run Directory (`$TEST_RUN`)

**Every infrastructure session creates a unique directory under `runs/`.** This is the most important convention in the repo — all setup scripts, configs, logs, data, and scenario outputs live here.

### How It's Created

Setup scripts create the directory automatically:

```bash
TEST_RUN="runs/test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_RUN"/{data,logs}
```

### Directory Layout

```text
runs/test_20260620_105703/              ← one infrastructure session
  ├── danube_broker.yml                 ← generated broker config (copied from configs/default.yml)
  ├── edge.yaml                         ← edge config (if edge scenario)
  ├── docker-compose.yml                ← generated compose file (Docker setup only)
  ├── prometheus.yml                    ← Prometheus scrape config (if monitoring)
  ├── *.pem                             ← TLS certs (if secure scenario)
  │
  ├── data/                             ← broker runtime data
  │   ├── standalone/                   ← standalone mode
  │   │   ├── raft/                     ← Raft consensus state
  │   │   └── wal/                      ← Write-ahead log
  │   ├── broker_6650/                  ← cluster mode, broker 0
  │   │   ├── raft/
  │   │   └── wal/
  │   ├── broker_6651/                  ← cluster mode, broker 1
  │   └── broker_6652/                  ← cluster mode, broker 2
  │
  ├── logs/                             ← broker logs
  │   ├── broker_standalone.log         ← standalone mode
  │   ├── broker_6650.log               ← cluster mode, broker 0
  │   ├── broker_6651.log               ← cluster mode, broker 1
  │   └── broker_6652.log               ← cluster mode, broker 2
  │
  └── scenarios/                        ← scenario outputs (created by scenario execution)
      ├── core-messaging/               ← scenario 1
      │   ├── producer.py
      │   ├── consumer.py
      │   └── output.log
      └── subscription-patterns/        ← scenario 2 (same infra session)
```

### Key Rules

1. **Binaries are NOT in `$TEST_RUN`** — they live in `bin/<version>/` at the repo root and are shared across all runs
2. **Configs are copied, not linked** — each run has its own copy of `danube_broker.yml` so configs are reproducible
3. **Brokers run FROM `$TEST_RUN`** — this is required because `storage.local_wal_root` resolves relative to the working directory
4. **Scenarios create subdirectories** — each scenario creates `$TEST_RUN/scenarios/<scenario-name>/` for its outputs
5. **Multiple scenarios share one run** — the user can run several scenarios against the same running infra
6. **Cleanup is simple** — `rm -rf runs/test_20260620_105703/` removes everything for that session

## Port Allocation

All setup methods use the same port scheme:

| Broker | Client | Admin | Raft | Prometheus |
|--------|--------|-------|------|------------|
| Broker 0 | 6650 | 50051 | 7650 | 9040 |
| Broker 1 | 6651 | 50052 | 7651 | 9041 |
| Broker 2 | 6652 | 50053 | 7652 | 9042 |

Additional services:

| Service | Port |
|---------|------|
| Prometheus UI | 9090 |
| Admin Server | 8080 |
| Admin Web UI | 8081 |
| MinIO API | 9000 |
| MinIO Console | 9001 |
| Edge MQTT | 1883 |
| Edge Broker | 6653 |
| Edge Admin | 50054 |

## Readiness Checks

Each setup method has a different way to verify brokers are ready:

### Local Brokers (binary or source)
```bash
# Poll until cluster status returns successfully
for i in $(seq 1 30); do
  danube-admin cluster status 2>/dev/null && break
  echo "Waiting for broker... ($i/30)"
  sleep 2
done
```

### Docker Compose
```bash
# Wait for healthchecks to pass
docker compose ps --format json | jq -r '.Health'
# Or check specific broker
docker compose exec broker1 curl -sf http://localhost:9040/metrics > /dev/null
```

### Kubernetes
```bash
kubectl wait --for=condition=ready pod -l app=danube-broker -n danube --timeout=120s
```

## Config Injection

Each setup method injects broker configs differently:

| Method | How Config Is Used |
|--------|--------------------|
| **Local Binary** | Standalone: no config. Cluster: `--config-file $TEST_RUN/danube_broker.yml` |
| **Local Source** | `CONFIG_FILE=$TEST_RUN/danube_broker.yml make brokers` or `--config-file` flag |
| **Docker Compose** | Volume mount: `$TEST_RUN/danube_broker.yml:/etc/danube_broker.yml:ro` |
| **Kubernetes** | ConfigMap: `kubectl create configmap danube-broker-config --from-file=danube_broker.yml` |

## Cleanup

Each setup has a dedicated cleanup command via `scripts/cleanup.sh`:

```bash
./scripts/cleanup.sh binary    # Stop local binary broker processes
./scripts/cleanup.sh source    # Stop source-built broker processes
./scripts/cleanup.sh docker    # Stop Docker Compose services and containers
./scripts/cleanup.sh k8s       # Remove Kubernetes deployment (Helm + namespace)
./scripts/cleanup.sh all       # All of the above + remove test-run directories
```

## AI Agent: Keeping Local Brokers Alive

**This section applies to `setup_local_binary.sh` and `setup_local_source.sh` only.** Docker Compose and Kubernetes are NOT affected — their processes are managed by Docker/K8s, not as child processes.

### The Problem

Local binary and source setups start brokers using `nohup ... &` as background child processes. In sandboxed AI environments (Claude Code, Cursor, Antigravity, etc.), when the setup script's command finishes, the sandbox terminates all child processes spawned by that command — including the `nohup`'d brokers. The brokers start successfully, pass all health checks, and then die seconds later when the parent command exits.

### The Solution

Run the setup script as a **background task** with `tail -f` appended to keep the parent process alive:

```bash
# Local Binary — standalone
./scripts/setup_local_binary.sh standalone v0.15.0 && tail -f runs/test_*/logs/broker_standalone.log

# Local Binary — cluster (3 brokers)
./scripts/setup_local_binary.sh cluster v0.15.0 3 && tail -f runs/test_*/logs/broker_6650.log

# Local Source — standalone
./scripts/setup_local_source.sh standalone && tail -f runs/test_*/logs/broker_standalone.log

# Local Source — cluster
./scripts/setup_local_source.sh cluster && tail -f runs/test_*/logs/broker_6650.log
```

**Why this works:** `tail -f` never exits — it keeps the background task alive, which keeps the process group alive, which keeps the broker processes alive. The brokers will stay running for the entire testing session until the user asks to tear down.

**How to run it:** Use a low `WaitMsBeforeAsync` (e.g., 500ms) so the command is sent to the background as a task. Then wait ~30 seconds for the setup script to complete before issuing further commands.

**How to tear down:** Kill the background task, then run `./scripts/cleanup.sh binary` (or `source`). Or just run the cleanup script — it will kill the broker processes, which will cause `tail -f` to exit naturally.

### Not Affected

- **`setup_docker_compose.sh`** — Docker manages container lifecycle. Containers survive command completion.
- **`setup_kubernetes.sh`** — Kubernetes manages pod lifecycle. Pods survive command completion.

## Troubleshooting (Common Across Methods)

### Port Already in Use
```bash
# Find what's using the port
ss -lntp | grep 6650
# Or
lsof -i :6650

# Kill the process
kill <PID>
```

### Broker Won't Start — Stale Raft Data
If a broker crashes or is killed, stale Raft data can prevent restart:
```bash
# Remove Raft data for a fresh start
rm -rf $TEST_RUN/data/*/
```

### Docker: Network Conflicts
```bash
docker network ls | grep danube
docker network rm danube_net
```
