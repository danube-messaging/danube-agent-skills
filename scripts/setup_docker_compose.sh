#!/usr/bin/env bash
# ============================================================================
# setup_docker_compose.sh — Start Danube via Docker Compose
#
# Usage:
#   ./scripts/setup_docker_compose.sh [FLAVOR] [DANUBE_ADMIN_PATH]
#
# Flavors:
#   quickstart           — 3 brokers + CLI + Prometheus (default)
#   with-ui              — + Admin Server + Web UI
#   with-cloud-storage   — + MinIO
#
# Examples:
#   ./scripts/setup_docker_compose.sh quickstart
#   ./scripts/setup_docker_compose.sh with-ui ./bin/v0.15.0/danube-admin
#
# What it does (in one shot):
#   1. Creates a test-run directory under runs/
#   2. Downloads compose files from GitHub
#   3. Patches volume mount paths for flat layout
#   4. Copies broker config
#   5. Starts docker compose
#   6. Waits for readiness
#   7. Verifies cluster health with danube-admin (if available)
#   8. Prints a summary and the cleanup command
# ============================================================================
set -euo pipefail

# ── Arguments ───────────────────────────────────────────────────────────────
FLAVOR="${1:-quickstart}"
DANUBE_ADMIN="${2:-}"

VALID_FLAVORS="quickstart with-ui with-cloud-storage"
if ! echo "$VALID_FLAVORS" | grep -qw "$FLAVOR"; then
  echo "Usage: $0 <quickstart|with-ui|with-cloud-storage> [DANUBE_ADMIN_PATH]"
  exit 1
fi

# ── Paths ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

TEST_RUN="runs/test_$(date +%Y%m%d_%H%M%S)"
DANUBE_RAW="https://raw.githubusercontent.com/danube-messaging/danube/main/docker"

# Auto-detect danube-admin if not provided
if [[ -z "$DANUBE_ADMIN" ]]; then
  # Check common locations
  for candidate in \
    "$(ls -d bin/*/danube-admin 2>/dev/null | head -1)" \
    "$(which danube-admin 2>/dev/null)" \
  ; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      DANUBE_ADMIN="$candidate"
      break
    fi
  done
fi

echo "═══════════════════════════════════════════════════════════"
echo "  Danube Docker Compose Setup — ${FLAVOR}"
echo "═══════════════════════════════════════════════════════════"
echo "  Test Run:      $TEST_RUN"
echo "  Compose Flavor: $FLAVOR"
echo "  danube-admin:  ${DANUBE_ADMIN:-not found (cluster verification will be skipped)}"
echo ""

# ── Step 1: Prerequisites ──────────────────────────────────────────────────
echo "▸ Step 1: Checking prerequisites..."
which docker >/dev/null 2>&1 || { echo "ERROR: docker not found"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running"; exit 1; }
echo "  ✓ Docker $(docker --version)"
echo "  ✓ $(docker compose version)"

# ── Step 2: Create test-run directory ──────────────────────────────────────
echo "▸ Step 2: Creating test-run directory..."
mkdir -p "$TEST_RUN"/{data,logs}

# ── Step 3: Download compose files ──────────────────────────────────────────
echo "▸ Step 3: Downloading compose files ($FLAVOR)..."

# Always needed: prometheus config and broker config
wget -q "$DANUBE_RAW/prometheus.yml" -O "$TEST_RUN/prometheus.yml"
echo "  ✓ prometheus.yml"

# Broker config
cp configs/default.yml "$TEST_RUN/danube_broker.yml"
echo "  ✓ danube_broker.yml (from configs/default.yml)"

# Compose file for the selected flavor
wget -q "$DANUBE_RAW/${FLAVOR}/docker-compose.yml" -O "$TEST_RUN/docker-compose.yml"
echo "  ✓ docker-compose.yml ($FLAVOR)"

# Cloud storage flavor needs the cloud broker config too
if [[ "$FLAVOR" == "with-cloud-storage" ]]; then
  wget -q "$DANUBE_RAW/danube_broker_cloud.yml" -O "$TEST_RUN/danube_broker_cloud.yml"
  echo "  ✓ danube_broker_cloud.yml"
fi

# ── Step 4: Patch volume mount paths ────────────────────────────────────────
echo "▸ Step 4: Patching volume mount paths for flat layout..."
sed -i 's|\.\.\(/danube_broker.*\.yml\)|.\1|g' "$TEST_RUN/docker-compose.yml"
sed -i 's|\.\.\(/prometheus\.yml\)|.\1|g' "$TEST_RUN/docker-compose.yml"

# Verify the fix
REMAINING=$(grep -c '\.\.\/' "$TEST_RUN/docker-compose.yml" 2>/dev/null || echo 0)
if [ "$REMAINING" -gt 0 ]; then
  echo "  ⚠ Warning: $REMAINING relative paths still found in compose file"
  grep '\.\.\/' "$TEST_RUN/docker-compose.yml" | sed 's/^/    /'
else
  echo "  ✓ All paths patched"
fi

# ── Step 5: Start services ─────────────────────────────────────────────────
echo "▸ Step 5: Starting Docker Compose services..."
cd "$TEST_RUN"
docker compose up -d 2>&1
cd "$REPO_ROOT"

# ── Step 6: Wait for readiness ──────────────────────────────────────────────
echo ""
echo "▸ Step 6: Waiting for container readiness..."
READY=false
for attempt in $(seq 1 30); do
  RUNNING=$(cd "$TEST_RUN" && docker compose ps --format json 2>/dev/null | grep -c '"running"' || echo 0)
  echo "  Attempt $attempt/30 — $RUNNING container(s) running"

  if [ "$RUNNING" -ge 3 ]; then
    READY=true
    echo "  ✓ Containers ready"
    break
  fi
  sleep 5
done

if [ "$READY" = false ]; then
  echo "ERROR: Containers did not become ready within 150 seconds."
  cd "$TEST_RUN" && docker compose ps && docker compose logs --tail 30
  exit 1
fi

# ── Step 7: Verify cluster health ───────────────────────────────────────────
echo "▸ Step 7: Verifying cluster health..."
sleep 10  # Give Raft time to elect a leader

if [[ -n "$DANUBE_ADMIN" && -x "$DANUBE_ADMIN" ]]; then
  echo ""
  echo "── brokers list ──"
  "$DANUBE_ADMIN" --endpoint http://127.0.0.1:50051 brokers list || true

  echo ""
  echo "── cluster status ──"
  "$DANUBE_ADMIN" --endpoint http://127.0.0.1:50051 cluster status || true
else
  echo "  ⚠ danube-admin not available — skipping cluster verification"
  echo "  Download it with: ./scripts/setup_local_binary.sh standalone <version>"
  echo "  Then re-run with: $0 $FLAVOR ./bin/<version>/danube-admin"
fi

# ── Step 8: Check logs for errors ───────────────────────────────────────────
echo ""
echo "▸ Step 8: Scanning container logs for errors..."
ERRORS=$(cd "$TEST_RUN" && docker compose logs 2>&1 | grep -i "ERROR\|PANIC\|FATAL" | grep -v "transport error" | head -10 || true)
if [ -n "$ERRORS" ]; then
  echo "  ⚠ Found errors in logs:"
  echo "$ERRORS" | sed 's/^/    /'
else
  echo "  ✓ No errors found in container logs"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Setup complete — Docker Compose ($FLAVOR)"
echo "═══════════════════════════════════════════════════════════"
echo "  Test Run:  $TEST_RUN"
echo ""
echo "  Running containers:"
cd "$TEST_RUN" && docker compose ps --format "table {{.Name}}\t{{.Status}}" | sed 's/^/    /'
cd "$REPO_ROOT"
echo ""
echo "  To view logs:"
echo "    cd $TEST_RUN && docker compose logs -f"
echo ""
echo "  To clean up:"
echo "    cd $TEST_RUN && docker compose down -v"
echo ""
