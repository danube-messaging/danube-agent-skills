#!/usr/bin/env bash
# ============================================================================
# setup_local_binary.sh — Download pre-built Danube binaries and start brokers
#
# Usage:
#   ./scripts/setup_local_binary.sh standalone [VERSION]
#   ./scripts/setup_local_binary.sh cluster    [VERSION] [NUM_BROKERS]
#
# Examples:
#   ./scripts/setup_local_binary.sh standalone v0.15.0
#   ./scripts/setup_local_binary.sh cluster v0.15.0 3
#
# What it does (in one shot):
#   1. Creates a test-run directory under runs/
#   2. Downloads binaries to shared bin/<version>/ (if not already present)
#   3. Copies configs to the test-run directory
#   4. Starts broker(s) in the background
#   5. Waits for readiness
#   6. Verifies cluster health with danube-admin
#   7. Prints a summary and the cleanup command
#
# The script prints the TEST_RUN path so the caller can use it for cleanup.
# ============================================================================
set -euo pipefail

# ── Arguments ───────────────────────────────────────────────────────────────
MODE="${1:-standalone}"
VERSION="${2:-v0.15.0}"
NUM_BROKERS="${3:-3}"

if [[ "$MODE" != "standalone" && "$MODE" != "cluster" ]]; then
  echo "Usage: $0 <standalone|cluster> [VERSION] [NUM_BROKERS]"
  echo "  VERSION     — release tag (default: v0.15.0)"
  echo "  NUM_BROKERS — number of brokers for cluster mode (default: 3)"
  exit 1
fi

# ── Paths ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

TEST_RUN="runs/test_$(date +%Y%m%d_%H%M%S)"
DANUBE_BIN="bin/${VERSION}"

echo "═══════════════════════════════════════════════════════════"
echo "  Danube Local Binary Setup — ${MODE} mode"
echo "═══════════════════════════════════════════════════════════"
echo "  Version:      $VERSION"
echo "  Test Run:     $TEST_RUN"
echo "  Binaries:     $DANUBE_BIN"
[[ "$MODE" == "cluster" ]] && echo "  Brokers:      $NUM_BROKERS"
echo ""

# ── Step 1: Create test-run directory ───────────────────────────────────────
echo "▸ Step 1: Creating test-run directory..."
mkdir -p "$TEST_RUN"/{data,logs}

# ── Step 2: Detect OS/Architecture ──────────────────────────────────────────
echo "▸ Step 2: Detecting OS and architecture..."
OS_RAW=$(uname -s)
ARCH=$(uname -m)

case "$OS_RAW" in
  Linux)   OS_TARGET="x86_64-unknown-linux-gnu"   ;;
  Darwin)  OS_TARGET="aarch64-apple-darwin"        ;;
  MINGW*|MSYS*|CYGWIN*) OS_TARGET="x86_64-pc-windows-msvc" ;;
  *)       echo "ERROR: Unsupported OS: $OS_RAW"; exit 1 ;;
esac

case "$ARCH" in
  x86_64)
    case "$OS_RAW" in
      Linux)  OS_TARGET="x86_64-unknown-linux-gnu" ;;
      Darwin) OS_TARGET="x86_64-apple-darwin" ;;
    esac ;;
  aarch64|arm64)
    case "$OS_RAW" in
      Linux)  OS_TARGET="aarch64-unknown-linux-gnu" ;;
      Darwin) OS_TARGET="aarch64-apple-darwin" ;;
    esac ;;
  *) echo "ERROR: Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS_RAW" in
  MINGW*|MSYS*|CYGWIN*) EXT="zip" ;;
  *) EXT="tar.gz" ;;
esac

echo "  Detected: $OS_TARGET ($EXT)"

# ── Step 3: Download binaries (shared, skip if exists) ──────────────────────
echo "▸ Step 3: Downloading binaries..."
if [ -x "$DANUBE_BIN/danube-broker" ]; then
  echo "  Binaries already exist at $DANUBE_BIN — skipping download"
else
  mkdir -p "$DANUBE_BIN"
  for BINARY in danube-broker danube-cli danube-admin; do
    ARCHIVE="${BINARY}-${VERSION}-${OS_TARGET}.${EXT}"
    URL="https://github.com/danube-messaging/danube/releases/download/${VERSION}/${ARCHIVE}"
    echo "  Downloading $ARCHIVE..."
    curl -fSL "$URL" -o "$DANUBE_BIN/$ARCHIVE"
    cd "$DANUBE_BIN"
    if [ "$EXT" = "zip" ]; then
      unzip -o "$ARCHIVE"
    else
      tar xzf "$ARCHIVE"
    fi
    rm -f "$ARCHIVE"
    cd "$REPO_ROOT"
  done
  chmod +x "$DANUBE_BIN"/danube-*
fi

# Verify binaries exist
for BIN in danube-broker danube-cli danube-admin; do
  if [ ! -x "$DANUBE_BIN/$BIN" ]; then
    echo "ERROR: Binary not found or not executable: $DANUBE_BIN/$BIN"
    exit 1
  fi
done
echo "  ✓ All binaries verified"

# ── Step 4: Start broker(s) ────────────────────────────────────────────────
# Run brokers from inside $TEST_RUN so that relative paths in the config
# (e.g., local_wal_root: "./data/wal") resolve inside the test run directory.
DANUBE_BIN_ABS="$(cd "$DANUBE_BIN" && pwd)"
cd "$TEST_RUN"

if [[ "$MODE" == "standalone" ]]; then
  echo "▸ Step 4: Starting standalone broker..."
  "$DANUBE_BIN_ABS/danube-broker" \
    --mode standalone \
    --data-dir "./data/standalone" \
    > "./logs/broker_standalone.log" 2>&1 &
  BROKER_PID=$!
  echo "  Broker PID: $BROKER_PID (client=6650, admin=50051)"

else
  echo "▸ Step 4: Starting $NUM_BROKERS-broker cluster..."
  # Copy config (relative paths in default.yml resolve from $TEST_RUN)
  cp "$REPO_ROOT/configs/default.yml" "./danube_broker.yml"

  # Build seed nodes string
  SEED_NODES=""
  for i in $(seq 0 $((NUM_BROKERS - 1))); do
    [[ -n "$SEED_NODES" ]] && SEED_NODES+=","
    SEED_NODES+="0.0.0.0:$((7650 + i))"
  done

  for i in $(seq 0 $((NUM_BROKERS - 1))); do
    broker_port=$((6650 + i))
    admin_port=$((50051 + i))
    raft_port=$((7650 + i))
    prom_port=$((9040 + i))
    data_dir="./data/broker-$i"
    log_file="./logs/broker_${broker_port}.log"

    mkdir -p "$data_dir"

    "$DANUBE_BIN_ABS/danube-broker" \
      --config-file "./danube_broker.yml" \
      --broker-addr "0.0.0.0:$broker_port" \
      --admin-addr "0.0.0.0:$admin_port" \
      --raft-addr "0.0.0.0:$raft_port" \
      --prom-exporter "0.0.0.0:$prom_port" \
      --data-dir "$data_dir" \
      --seed-nodes "$SEED_NODES" \
      > "$log_file" 2>&1 &

    echo "  Broker $i: client=$broker_port admin=$admin_port raft=$raft_port (PID: $!)"
    sleep 2
  done
fi

cd "$REPO_ROOT"

# ── Step 5: Wait for readiness ──────────────────────────────────────────────
echo "▸ Step 5: Waiting for broker readiness..."
READY=false
for attempt in $(seq 1 30); do
  if "$DANUBE_BIN/danube-admin" brokers list 2>/dev/null | grep -q "active"; then
    READY=true
    echo "  ✓ Broker(s) ready after $attempt attempt(s)"
    break
  fi
  echo "  Attempt $attempt/30 — waiting 2s..."
  sleep 2
done

if [ "$READY" = false ]; then
  echo ""
  echo "ERROR: Brokers did not become ready within 60 seconds."
  echo "Check logs:"
  ls -1 "$TEST_RUN/logs/"*.log 2>/dev/null | while read -r f; do
    echo "  tail -20 $f"
  done
  exit 1
fi

# ── Step 6: Verify health ──────────────────────────────────────────────────
echo "▸ Step 6: Verifying cluster health..."
echo ""
echo "── brokers list ──"
"$DANUBE_BIN/danube-admin" brokers list

if [[ "$MODE" == "cluster" ]]; then
  echo ""
  echo "── cluster status ──"
  "$DANUBE_BIN/danube-admin" cluster status || true
fi

echo ""
echo "── prometheus metrics (first 5 lines) ──"
curl -s http://localhost:9040/metrics 2>/dev/null | head -5 || echo "  (metrics endpoint not reachable)"

# ── Step 7: Check logs for errors ───────────────────────────────────────────
echo ""
echo "▸ Step 7: Scanning logs for errors..."
ERRORS=$(grep -i "ERROR\|PANIC\|FATAL" "$TEST_RUN/logs/"*.log 2>/dev/null | grep -v "transport error" || true)
if [ -n "$ERRORS" ]; then
  echo "  ⚠ Found errors in logs:"
  echo "$ERRORS" | head -10
else
  echo "  ✓ No errors found in logs"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Setup complete — ${MODE} mode"
echo "═══════════════════════════════════════════════════════════"
echo "  Test Run:  $TEST_RUN"
echo "  Binaries:  $DANUBE_BIN"
echo "  Logs:      $TEST_RUN/logs/"
echo ""
echo "  Running brokers:"
pgrep -la danube-broker | sed 's/^/    /'
echo ""
echo "  To clean up:"
echo "    ./scripts/cleanup.sh binary"
echo "    rm -rf $TEST_RUN  # optional: remove test-run data"
echo ""
