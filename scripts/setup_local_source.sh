#!/usr/bin/env bash
# ============================================================================
# setup_local_source.sh — Build Danube from source and start brokers
#
# Usage:
#   ./scripts/setup_local_source.sh <DANUBE_REPO_PATH> [NUM_BROKERS]
#
# Examples:
#   ./scripts/setup_local_source.sh /home/user/danube
#   ./scripts/setup_local_source.sh /home/user/danube 5
#
# What it does (in one shot):
#   1. Validates the Danube source repository path
#   2. Builds brokers via `make brokers`
#   3. Waits for readiness
#   4. Verifies cluster health with danube-admin
#   5. Prints a summary and the cleanup command
# ============================================================================
set -euo pipefail

# ── Arguments ───────────────────────────────────────────────────────────────
DANUBE_REPO="${1:-}"
NUM_BROKERS="${2:-3}"

if [[ -z "$DANUBE_REPO" ]]; then
  echo "Usage: $0 <DANUBE_REPO_PATH> [NUM_BROKERS]"
  echo "  DANUBE_REPO  — path to the cloned Danube source repository"
  echo "  NUM_BROKERS  — number of brokers to start (default: 3)"
  exit 1
fi

# ── Validate repo ──────────────────────────────────────────────────────────
if [ ! -f "$DANUBE_REPO/Makefile" ]; then
  echo "ERROR: Makefile not found at $DANUBE_REPO/Makefile"
  echo "Are you sure this is the Danube source repository?"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════"
echo "  Danube Local Source Setup"
echo "═══════════════════════════════════════════════════════════"
echo "  Danube Repo:  $DANUBE_REPO"
echo "  Brokers:      $NUM_BROKERS"
echo ""

# ── Step 1: Check prerequisites ────────────────────────────────────────────
echo "▸ Step 1: Checking prerequisites..."
which cargo >/dev/null 2>&1 || { echo "ERROR: cargo not found. Install Rust: https://rustup.rs/"; exit 1; }
which make  >/dev/null 2>&1 || { echo "ERROR: make not found."; exit 1; }
echo "  ✓ cargo $(cargo --version 2>/dev/null | head -1)"
echo "  ✓ make found"

# ── Step 2: Clean previous state ───────────────────────────────────────────
echo "▸ Step 2: Cleaning previous broker state..."
cd "$DANUBE_REPO"
make brokers-clean 2>/dev/null || true

# ── Step 3: Build and start brokers ─────────────────────────────────────────
echo "▸ Step 3: Building and starting $NUM_BROKERS brokers..."
echo "  (This may take several minutes on first build)"
make brokers NUM_BROKERS="$NUM_BROKERS"

# ── Step 4: Wait for readiness ──────────────────────────────────────────────
echo ""
echo "▸ Step 4: Waiting for cluster readiness..."
READY=false
for attempt in $(seq 1 30); do
  if ./target/release/danube-admin brokers list 2>/dev/null | grep -q "active"; then
    READY=true
    echo "  ✓ Cluster ready after $attempt attempt(s)"
    break
  fi
  echo "  Attempt $attempt/30 — waiting 2s..."
  sleep 2
done

if [ "$READY" = false ]; then
  echo ""
  echo "ERROR: Cluster did not become ready within 60 seconds."
  echo "Check logs:"
  ls -1 "$DANUBE_REPO/temp/broker_"*.log 2>/dev/null | while read -r f; do
    echo "  tail -20 $f"
  done
  exit 1
fi

# ── Step 5: Verify health ──────────────────────────────────────────────────
echo "▸ Step 5: Verifying cluster health..."
echo ""
echo "── brokers list ──"
./target/release/danube-admin brokers list

echo ""
echo "── cluster status ──"
./target/release/danube-admin cluster status || true

echo ""
echo "── leader broker ──"
./target/release/danube-admin brokers leader-broker || true

echo ""
echo "── cluster balance ──"
./target/release/danube-admin brokers balance || true

# ── Step 6: Check logs for errors ───────────────────────────────────────────
echo ""
echo "▸ Step 6: Scanning logs for errors..."
ERRORS=$(grep -i "ERROR\|PANIC\|FATAL" "$DANUBE_REPO/temp/broker_"*.log 2>/dev/null | grep -v "transport error" || true)
if [ -n "$ERRORS" ]; then
  echo "  ⚠ Found errors in logs:"
  echo "$ERRORS" | head -10
else
  echo "  ✓ No errors found in logs"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Setup complete — $NUM_BROKERS-broker cluster"
echo "═══════════════════════════════════════════════════════════"
echo "  Danube Repo:  $DANUBE_REPO"
echo "  Logs:         $DANUBE_REPO/temp/broker_*.log"
echo ""
echo "  Running brokers:"
pgrep -la danube-broker | sed 's/^/    /' || true
echo ""
echo "  To clean up:"
echo "    cd $DANUBE_REPO && make brokers-clean"
echo ""
