# Skill: Local Binary Setup

## Objective

Download pre-built Danube binaries from GitHub releases and run brokers directly on the host machine. The simplest setup — no Docker, no build tools, just download and run.

## Difficulty
Beginner

## Required Setup
None — this IS the setup.

## Required Tools
- `curl` or `wget` (for downloading binaries)
- `tar` (for extracting archives)

## Prerequisites Check

```bash
# Check download tools
which curl || which wget

# Check for existing Danube processes
pgrep -la danube-broker

# Check port availability
ss -lntp | grep -E '(6650|6651|6652|50051|50052|50053|7650|7651|7652)'
```

## Steps

### Step 1: Create the Test-Run Directory

```bash
TEST_RUN="runs/test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_RUN"/{data,logs}
echo "Test run directory: $TEST_RUN"
```

### Step 2: Set the Release Version

The user must provide the Danube release version. **Ask the user which version to use.**

```bash
DANUBE_VERSION="v0.15.0"  # provided by the user
DANUBE_BIN="bin/${DANUBE_VERSION}"
```

### Step 3: Detect OS and Architecture

```bash
OS_RAW=$(uname -s)
ARCH=$(uname -m)

# Map to Danube release naming convention
case "$OS_RAW" in
  Linux)   OS_TARGET="x86_64-unknown-linux-gnu"   ;; # default for Linux x86_64
  Darwin)  OS_TARGET="aarch64-apple-darwin"        ;; # default for macOS Apple Silicon
  MINGW*|MSYS*|CYGWIN*) OS_TARGET="x86_64-pc-windows-msvc" ;;
  *)       echo "Unsupported OS: $OS_RAW"; exit 1 ;;
esac

# Refine by architecture
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
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Archive extension
case "$OS_RAW" in
  MINGW*|MSYS*|CYGWIN*) EXT="zip" ;;
  *) EXT="tar.gz" ;;
esac

echo "Detected: OS_TARGET=$OS_TARGET EXT=$EXT"
```

### Step 4: Download Binaries (shared across test runs)

Binaries are downloaded to `bin/<version>/` at the repo root and reused by all test runs. **Skip this step if binaries already exist for the requested version.**

The release page is: https://github.com/danube-messaging/danube/releases

Download URL pattern:
```
https://github.com/danube-messaging/danube/releases/download/<VERSION>/<BINARY>-<VERSION>-<OS_TARGET>.<EXT>
```

Examples:
- `danube-broker-v0.15.0-x86_64-unknown-linux-gnu.tar.gz`
- `danube-cli-v0.15.0-aarch64-apple-darwin.tar.gz`
- `danube-admin-v0.15.0-x86_64-pc-windows-msvc.zip`

```bash
# Check if binaries already exist
if [ -x "$DANUBE_BIN/danube-broker" ]; then
  echo "Binaries already exist at $DANUBE_BIN — skipping download"
else
  mkdir -p "$DANUBE_BIN"

  for BINARY in danube-broker danube-cli danube-admin; do
    ARCHIVE="${BINARY}-${DANUBE_VERSION}-${OS_TARGET}.${EXT}"
    URL="https://github.com/danube-messaging/danube/releases/download/${DANUBE_VERSION}/${ARCHIVE}"

    echo "Downloading $ARCHIVE..."
    curl -L "$URL" -o "$DANUBE_BIN/$ARCHIVE"

    # Extract
    cd "$DANUBE_BIN"
    if [ "$EXT" = "zip" ]; then
      unzip -o "$ARCHIVE"
    else
      tar xzf "$ARCHIVE"
    fi
    rm -f "$ARCHIVE"
    cd -
  done

  chmod +x "$DANUBE_BIN"/danube-*
fi

# Verify binaries
"$DANUBE_BIN/danube-broker" --version
"$DANUBE_BIN/danube-cli" --version
"$DANUBE_BIN/danube-admin" --version
```

**Expected**: Version output for each binary.

### Step 5: Prepare Configuration

Choose one of these options based on the scenario:

#### Option A: Standalone Mode (single broker, no config needed)

No config file required. The `--mode standalone` flag generates sensible defaults.

#### Option B: Standalone with Custom Config

```bash
cp configs/default.yml "$TEST_RUN/danube_broker.yml"
```

#### Option C: Multi-Broker Cluster

```bash
cp configs/default.yml "$TEST_RUN/danube_broker.yml"
```

Then add seed_nodes for the number of brokers:
```yaml
meta_store:
  data_dir: "./danube-data/raft"
  seed_nodes:
    - "0.0.0.0:7650"
    - "0.0.0.0:7651"
    - "0.0.0.0:7652"
```

#### Option D: Apply a Config Flavor

```bash
# Copy the default config
cp configs/default.yml "$TEST_RUN/danube_broker.yml"
# Then read configs/flavors/SKILL.md for the scenario-specific deltas
# and apply only the documented changes (e.g., enable rebalancing, change storage mode)
```


### Step 6: Start Brokers

#### Standalone Mode (simplest)

```bash
"$DANUBE_BIN/danube-broker" \
  --mode standalone \
  --data-dir "$TEST_RUN/data/standalone" \
  > "$TEST_RUN/logs/broker_standalone.log" 2>&1 &

echo "Standalone broker PID: $!"
```

**Expected**: Broker starts on `127.0.0.1:6650` (client), `127.0.0.1:50051` (admin).

#### Multi-Broker Cluster (3 brokers)

```bash
SEED_NODES="0.0.0.0:7650,0.0.0.0:7651,0.0.0.0:7652"

for i in 0 1 2; do
  broker_port=$((6650 + i))
  admin_port=$((50051 + i))
  raft_port=$((7650 + i))
  prom_port=$((9040 + i))
  data_dir="$TEST_RUN/data/broker-$i"
  log_file="$TEST_RUN/logs/broker_${broker_port}.log"

  mkdir -p "$data_dir"

  "$DANUBE_BIN/danube-broker" \
    --config-file "$TEST_RUN/danube_broker.yml" \
    --broker-addr "0.0.0.0:$broker_port" \
    --admin-addr "0.0.0.0:$admin_port" \
    --raft-addr "0.0.0.0:$raft_port" \
    --prom-exporter "0.0.0.0:$prom_port" \
    --data-dir "$data_dir" \
    --seed-nodes "$SEED_NODES" \
    > "$log_file" 2>&1 &

  echo "Broker $i started: client=$broker_port admin=$admin_port raft=$raft_port (PID: $!)"
  sleep 2
done
```

**Expected**: Three brokers start, Raft consensus elects a leader within ~10 seconds.

### Step 7: Wait for Readiness

```bash
echo "Waiting for broker readiness..."
for attempt in $(seq 1 30); do
  if "$DANUBE_BIN/danube-admin" cluster status 2>/dev/null; then
    echo "Cluster is ready!"
    break
  fi
  echo "  Attempt $attempt/30 — waiting 2s..."
  sleep 2
done
```

**Expected**: `danube-admin cluster status` returns cluster membership and leader info.

### Step 8: Verify Cluster Health

```bash
# Raft cluster state
"$DANUBE_BIN/danube-admin" cluster status

# List all brokers and their status
"$DANUBE_BIN/danube-admin" brokers list

# Identify the cluster leader
"$DANUBE_BIN/danube-admin" brokers leader

# Check load distribution
"$DANUBE_BIN/danube-admin" brokers balance
```

**Expected**: All brokers show status `active`, a leader is elected, and load is balanced.

### Step 9: Check Broker Logs

```bash
# Check logs for errors
tail -30 "$TEST_RUN/logs/broker_6650.log"
tail -30 "$TEST_RUN/logs/broker_6651.log"
tail -30 "$TEST_RUN/logs/broker_6652.log"

# Look for errors across all brokers
grep -i "error\|panic\|fatal" "$TEST_RUN/logs/"*.log
```

**Expected**: No errors or panics. Logs show successful Raft leader election and cluster formation.

## Edge Mode

To run an edge broker alongside a cluster broker:

### Step 1: Ensure a cluster broker is running (see above)

### Step 2: Prepare edge config

```bash
cp configs/edge.yaml "$TEST_RUN/edge.yaml"
# Set cluster_url to point to the running cluster broker
# (default is http://127.0.0.1:6650 which works for local setup)
```

### Step 3: Start edge broker

```bash
"$DANUBE_BIN/danube-broker" \
  --mode edge \
  --data-dir "$TEST_RUN/data/edge" \
  --edge-config "$TEST_RUN/edge.yaml" \
  --broker-addr "0.0.0.0:6653" \
  --admin-addr "0.0.0.0:50054" \
  --raft-addr "0.0.0.0:7653" \
  > "$TEST_RUN/logs/edge_broker.log" 2>&1 &

echo "Edge broker PID: $!"
```

### Step 4: Test MQTT ingestion (requires mosquitto_pub)

```bash
mosquitto_pub -h 127.0.0.1 -p 1883 \
  -t "device/sensor-1/telemetry" \
  -m '{"temperature": 25.5, "device_id": "sensor-1"}'
```

## Verification

- [ ] Binaries downloaded and executable
- [ ] `danube-broker --version` outputs version string
- [ ] Broker process running: `pgrep -la danube-broker`
- [ ] `danube-admin cluster status` shows leader and voters
- [ ] `danube-admin brokers list` shows all brokers as `active`
- [ ] `danube-admin brokers balance` shows balanced load
- [ ] Broker logs show no errors: `grep -i error "$TEST_RUN/logs/"*.log`
- [ ] Prometheus metrics accessible: `curl http://localhost:9040/metrics | head`

## Cleanup

```bash
# Stop all Danube processes
pkill -f danube-broker
pkill -f danube-admin

# Verify they stopped
sleep 2
pgrep -la danube-broker && echo "WARNING: brokers still running" || echo "All brokers stopped"

# The test-run directory can be deleted if no longer needed:
# rm -rf "$TEST_RUN"
```

## Troubleshooting

- **Binary not found or wrong architecture**: Check `uname -m` and verify the download URL matches. The release page may have different naming conventions (e.g., `gnu` vs `musl`).

- **Permission denied**: Make the binary executable: `chmod +x "$DANUBE_BIN/danube-broker"`

- **Port already in use**: Another broker or process is using the port. Check with `ss -lntp | grep <port>` and kill the offending process.

- **Raft cluster not forming**: Ensure all seed_nodes addresses are correct and all brokers can reach each other. Check logs: `tail -20 "$TEST_RUN/logs/broker_6650.log"`

- **Standalone mode ignores config file**: In `--mode standalone`, the broker generates its own config. To use a config file, omit `--mode standalone` and use `--config-file` instead.
