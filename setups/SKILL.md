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

## Cleanup Priority

Always clean up in this order:
1. Stop producers and consumers
2. Stop/delete brokers
3. Remove data directories or volumes
4. Remove Docker networks or K8s namespaces
5. Verify no orphaned processes or containers remain

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
