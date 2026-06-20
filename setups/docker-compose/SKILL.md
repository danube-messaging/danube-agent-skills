---
name: docker-compose
description: "Run Danube via Docker Compose with published container images. Use for multi-broker cluster testing with Prometheus, optional Admin UI, or MinIO cloud storage."
---

# Skill: Docker Compose Setup

## Objective

Run Danube via Docker Compose using published container images. This is the recommended setup for most testing scenarios — it provides a multi-broker cluster with Prometheus, CLI, and optional services (MinIO, Admin UI) with a single command.

## Difficulty
Beginner

## Required Setup
None — this IS the setup.

## Required Tools
- Docker Engine 20.10+
- Docker Compose 2.0+ (`docker compose` — V2 syntax)

## How to Run

Use the setup script. It downloads compose files from GitHub, patches volume mount paths, copies broker config, starts services, waits for readiness, and verifies cluster health — all in one command.

```bash
# Quickstart (3 brokers + CLI + Prometheus)
./scripts/setup_docker_compose.sh quickstart

# With Admin UI
./scripts/setup_docker_compose.sh with-ui

# With cloud storage (MinIO)
./scripts/setup_docker_compose.sh with-cloud-storage

# Cleanup
cd runs/test_<timestamp> && docker compose down -v
# Or cleanup everything:
./scripts/cleanup.sh
```

The script is at `scripts/setup_docker_compose.sh` — read it for the full implementation details.

## Compose Flavors

The Danube repository provides four Docker Compose setups. Which flavor to use is determined by the **scenario**, not this setup.

| Flavor | Services | Storage |
|--------|----------|---------|
| **quickstart** | 3 Brokers + CLI + Prometheus | Filesystem |
| **with-ui** | + Admin Server + Web UI | Filesystem |
| **with-cloud-storage** | + MinIO + MC | S3/MinIO |
| **local-development** | All (built from source) | Filesystem |

Compose files are downloaded from GitHub at runtime:
```
https://raw.githubusercontent.com/danube-messaging/danube/main/docker/<flavor>/docker-compose.yml
```

## Key Concepts

### Compose Files Are Downloaded, Not Local
The setup script downloads compose files from the Danube GitHub repository using `wget`. It does not require the Danube source repo to be cloned locally.

### Volume Mount Path Patching
The downloaded compose files reference configs at `../danube_broker.yml` (relative to their original `docker/<flavor>/` directory). Since everything is flat in `$TEST_RUN/`, the script patches these to `./danube_broker.yml` and `./prometheus.yml` using `sed`.

### Seed Nodes Use Docker Service Names
For Docker Compose, the broker config must use Docker service names for seed_nodes (`broker1:7650`, `broker2:7650`), not `0.0.0.0` addresses. See the "Cluster" flavor in `configs/flavors/SKILL.md`.

### danube-cli vs danube-admin in Docker
The `danube-cli` container only has `danube-cli` — it does **NOT** include `danube-admin`. They are separate images. Use host-installed `danube-admin` via the mapped admin port (50051) for cluster operations:

```bash
danube-admin --endpoint http://127.0.0.1:50051 brokers list
```

If `danube-admin` is not installed on the host, download it using the local-binary setup:
```bash
./scripts/setup_local_binary.sh standalone <version>
# Then use: ./bin/<version>/danube-admin --endpoint http://127.0.0.1:50051 brokers list
```

### Port Mappings
Docker Compose maps the same ports as local setups (6650-6652 for clients, 50051-50053 for admin, 9090 for Prometheus).

## Viewing Logs

```bash
cd $TEST_RUN

# All services
docker compose logs -f

# Specific broker
docker compose logs -f broker1

# Last 50 lines
docker logs danube-broker1 --tail 50

# Check for errors
docker compose logs 2>&1 | grep -i "ERROR\|PANIC\|FATAL"
```

## Verification Checklist

- [ ] `docker compose ps` shows all services running
- [ ] All broker healthchecks pass (status: "healthy")
- [ ] `danube-admin --endpoint http://127.0.0.1:50051 cluster status` shows leader and voters
- [ ] `danube-admin --endpoint http://127.0.0.1:50051 brokers list` shows all brokers as `active`
- [ ] Broker logs show no errors
- [ ] Prometheus accessible: `curl http://localhost:9090/-/healthy`

## Cleanup

```bash
cd $TEST_RUN
docker compose down -v

# Or for complete cleanup (all test runs + orphaned containers):
./scripts/cleanup.sh --all
```

## Troubleshooting

- **Port conflicts**: `ss -lntp | grep <port>`. Stop conflicting processes or change host port mappings in the compose file.

- **Container exits immediately**: Check logs: `docker logs danube-broker1`. Common cause: invalid config YAML or missing config file mount.

- **Seed node mismatch**: Ensure the config's `seed_nodes` use Docker service names (`broker1:7650`), not `0.0.0.0` or `localhost`.

- **Healthcheck failing**: Brokers take 15-30 seconds to initialize. If still failing after that, check broker logs.

- **`docker compose` vs `docker-compose`**: Use `docker compose` (V2, space-separated). V1 (`docker-compose`) may work but V2 is recommended.

- **Image not found**: `docker pull ghcr.io/danube-messaging/danube-broker:latest`. Check firewall/proxy settings if behind a network.

- **Network conflicts**: If `danube_net` already exists: `docker network rm danube_net` then retry.
