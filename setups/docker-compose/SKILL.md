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

## Prerequisites Check

```bash
# Check Docker
which docker && docker --version

# Check Docker Compose (V2)
docker compose version

# Check Docker is running
docker info > /dev/null 2>&1 && echo "Docker is running" || echo "Docker is NOT running"

# Check port availability
ss -lntp | grep -E '(6650|6651|6652|50051|50052|50053|9040|9041|9042|9090)'

# Check for existing Danube containers
docker ps --filter "name=danube" --format "table {{.Names}}\t{{.Status}}"
```

## Compose Flavors

The Danube repository provides four Docker Compose setups:

| Flavor | Directory | Services | Storage |
|--------|-----------|----------|---------|
| **quickstart** | `docker/quickstart/` | 3 Brokers + CLI + Prometheus | Filesystem |
| **with-ui** | `docker/with-ui/` | + Admin Server + Web UI | Filesystem |
| **with-cloud-storage** | `docker/with-cloud-storage/` | + MinIO + MC | S3/MinIO |
| **local-development** | `docker/local-development/` | All (built from source) | Filesystem |

> **Note**: Which flavor to use is determined by the **scenario**, not this setup. See `scenarios/SKILL.md` for the mapping.

## Steps

### Step 1: Create the Test-Run Directory

```bash
TEST_RUN="runs/test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_RUN"/{data,logs}
echo "Test run directory: $TEST_RUN"
```

### Step 2: Prepare Configuration

Always start from the default config and apply flavor overlays:

```bash
# 1. Copy the default config
cp configs/default.yml "$TEST_RUN/danube_broker.yml"

# 2. Apply the "Cluster" flavor from configs/flavors/SKILL.md:
#    Add seed_nodes with Docker service names to the meta_store section:
#      seed_nodes:
#        - "broker1:7650"
#        - "broker2:7650"
#        - "broker3:7650"

# 3. For specific scenarios, apply additional overlays from configs/flavors/SKILL.md:
#    - Cloud Storage: change storage.mode to object_store, add durable block
#    - Rebalance: enable rebalancing with aggressive settings
#    - Secure: change auth.mode to tls, add TLS/JWT config
```

> **Important**: For Docker Compose, seed_nodes must use Docker service names (`broker1:7650`), not `0.0.0.0` addresses. See the "Cluster" flavor in `configs/flavors/SKILL.md`.


### Step 3: Download Docker Compose Files

Download the compose files from the Danube repository using wget:

```bash
DANUBE_RAW="https://raw.githubusercontent.com/danube-messaging/danube/main/docker"

# Always needed: prometheus config
wget -q "$DANUBE_RAW/prometheus.yml" -O "$TEST_RUN/prometheus.yml"

# Pick the compose flavor (scenario determines which one):

# Quickstart (most common)
wget -q "$DANUBE_RAW/quickstart/docker-compose.yml" -O "$TEST_RUN/docker-compose.yml"

# With UI
# wget -q "$DANUBE_RAW/with-ui/docker-compose.yml" -O "$TEST_RUN/docker-compose.yml"

# With cloud storage (also needs the cloud broker config)
# wget -q "$DANUBE_RAW/with-cloud-storage/docker-compose.yml" -O "$TEST_RUN/docker-compose.yml"
# wget -q "$DANUBE_RAW/danube_broker_cloud.yml" -O "$TEST_RUN/danube_broker_cloud.yml"
```

> **Important**: The compose files reference `../danube_broker.yml` relative to their original directory. Since we download them to `$TEST_RUN/`, update the volume mount path in the compose file to `./danube_broker.yml` — see Step 4.

### Step 4: Adjust Volume Mounts for Flat Layout

The downloaded compose files expect the broker config at `../danube_broker.yml` (relative to `docker/quickstart/`). Since everything is flat in `$TEST_RUN/`, update the volume mount:

```bash
# Fix the config path in the compose file
sed -i 's|\.\.\(/danube_broker.*\.yml\)|.\1|g' "$TEST_RUN/docker-compose.yml"

# Fix the prometheus config path
sed -i 's|\.\.\(/prometheus\.yml\)|.\1|g' "$TEST_RUN/docker-compose.yml"
```

This changes `../danube_broker.yml` → `./danube_broker.yml` and `../prometheus.yml` → `./prometheus.yml`.

Verify the fix:
```bash
grep -n 'danube_broker\|prometheus.yml' "$TEST_RUN/docker-compose.yml"
```

### Step 5: Start the Cluster

```bash
cd "$TEST_RUN"
docker compose up -d
```

**Expected output**:
```
[+] Running 6/6
 ✔ Network danube_net          Created
 ✔ Container danube-broker1    Started
 ✔ Container danube-broker2    Started
 ✔ Container danube-broker3    Started
 ✔ Container danube-cli        Started
 ✔ Container danube-prometheus Started
```

### Step 6: Wait for Readiness

```bash
echo "Waiting for brokers to be healthy..."
for attempt in $(seq 1 30); do
  HEALTHY=$(docker compose ps --format json 2>/dev/null | grep -c '"healthy"' || echo 0)
  TOTAL=$(docker compose ps --format json 2>/dev/null | grep -c '"running"' || echo 0)
  echo "  Attempt $attempt/30 — $HEALTHY healthy, $TOTAL running"

  if [ "$HEALTHY" -ge 3 ]; then
    echo "All brokers healthy!"
    break
  fi
  sleep 5
done

# Verify cluster status via host-installed danube-admin (admin port is mapped to host)
danube-admin cluster status --admin-addr 127.0.0.1:50051
```

> **Note**: The `danube-cli` container only has `danube-cli`, NOT `danube-admin`. They are separate Docker images (see Dockerfile). Use host-installed `danube-admin` via the mapped port (50051) for cluster operations.

**Expected**: All 3 brokers healthy, cluster status shows leader elected.

### Step 7: Verify Cluster Health

Use host-installed `danube-admin` via the mapped admin port:

```bash
# Raft cluster state
danube-admin cluster status --admin-addr 127.0.0.1:50051

# List all brokers and their status
danube-admin brokers list --admin-addr 127.0.0.1:50051

# Identify the cluster leader
danube-admin brokers leader --admin-addr 127.0.0.1:50051

# Check load distribution
danube-admin brokers balance --admin-addr 127.0.0.1:50051
```

If `danube-admin` is not installed on the host, download it from `bin/<version>/` (see `setups/local-binary/SKILL.md`).

**Expected**: All brokers show status `active`, a leader is elected, and load is balanced.

### Step 8: Check Broker Logs

```bash
# All broker logs
docker compose logs

# Specific broker
docker compose logs broker1

# Last 50 lines
docker logs danube-broker1 --tail 50

# Check for errors
docker compose logs 2>&1 | grep -i "error\|panic\|fatal"
```

**Expected**: No errors or panics. Logs show successful Raft leader election and cluster formation.

## Using the CLI and Admin Containers

The Docker Compose setup includes a `danube-cli` container connected to the broker network. **It only has `danube-cli`, not `danube-admin`** — they are separate images.

### danube-cli (produce/consume via Docker network)
```bash
# Interactive shell
docker exec -it danube-cli /bin/sh

# Run danube-cli commands
docker exec danube-cli danube-cli produce --help
```

### danube-admin (cluster operations via host ports)

Use host-installed `danube-admin` with the mapped admin ports:
```bash
# Cluster status (admin port 50051 mapped to host)
danube-admin cluster status --admin-addr 127.0.0.1:50051

# List brokers
danube-admin brokers list --admin-addr 127.0.0.1:50051

# Cluster leader
danube-admin brokers leader --admin-addr 127.0.0.1:50051

# Load distribution
danube-admin brokers balance --admin-addr 127.0.0.1:50051
```

If `danube-admin` is not installed on the host, download it from `bin/<version>/` (see `setups/local-binary/SKILL.md`).

## Viewing Logs

```bash
# All services
docker compose logs -f

# Specific broker
docker compose logs -f broker1

# Last 50 lines of a specific broker
docker logs danube-broker1 --tail 50
```

## Verification

- [ ] `docker compose ps` shows all services running
- [ ] All broker healthchecks pass (status: "healthy")
- [ ] `danube-admin cluster status` shows leader and voters
- [ ] `danube-admin brokers list` shows all brokers as `active`
- [ ] `danube-admin brokers balance` shows balanced load
- [ ] Broker logs show no errors: `docker compose logs 2>&1 | grep -i error`
- [ ] Prometheus accessible: `curl http://localhost:9090/-/healthy`

## Cleanup

```bash
cd "$TEST_RUN"

# Stop and remove containers, networks, and volumes
docker compose down -v

# Verify nothing remains
docker ps --filter "name=danube" --format "{{.Names}}"
docker volume ls --filter "name=danube"
docker network ls --filter "name=danube"
```

For a complete reset:
```bash
docker compose down -v
docker volume prune -f
docker network prune -f
```

## Troubleshooting

- **Port conflicts**: Check `ss -lntp | grep <port>`. Stop conflicting processes or change the host port mappings in the compose file.

- **Container exits immediately**: Check logs: `docker logs danube-broker1`. Common cause: invalid config YAML or missing config file mount.

- **Seed node mismatch**: Ensure the config's `seed_nodes` use Docker service names (`broker1:7650`), not `0.0.0.0` or `localhost` addresses.

- **Healthcheck failing**: Brokers take 15-30 seconds to initialize. Wait for `start_period` to elapse. If still failing, check broker logs for startup errors.

- **`docker compose` vs `docker-compose`**: Use `docker compose` (V2, space-separated). If you only have `docker-compose` (V1), the compose files should still work but V2 is recommended.

- **Image not found**: Ensure you can pull the image: `docker pull ghcr.io/danube-messaging/danube-broker:latest`. If you're behind a firewall, you may need to configure Docker proxy settings.

- **Network conflicts**: If `danube_net` already exists: `docker network rm danube_net` then retry.
