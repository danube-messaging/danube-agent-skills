# Skill: Local Source Setup

## Objective

Build Danube from the source repository and run brokers locally. This setup is for users who are developing on the Danube codebase and want to test their local changes.

## Difficulty
Intermediate

## Required Setup
None — this IS the setup.

## Required Tools
- Rust toolchain (`cargo`, `rustc`) — install via [rustup.rs](https://rustup.rs/)
- The Danube source repository cloned locally
- `make` (GNU Make)

## Prerequisites Check

```bash
# Check Rust toolchain
which cargo && cargo --version
which rustc && rustc --version

# Check make
which make

# Check that the Danube repo exists
# Ask the user for the path to the Danube source repository
DANUBE_REPO=""  # ← user must provide this
ls "$DANUBE_REPO/Makefile" && echo "Danube repo found at $DANUBE_REPO"

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

### Step 2: Set the Danube Repo Path

**Ask the user where the Danube source repository is cloned.**

```bash
DANUBE_REPO=""  # provided by the user
ls "$DANUBE_REPO/Makefile" && echo "Found Danube repo at $DANUBE_REPO"
```

### Step 3: Prepare Configuration

Choose one based on the scenario:

#### Option A: Use the Default Repo Config (simplest)

```bash
# The Makefile uses the repo's own config by default
# No action needed — the Makefile points to ./config/danube_broker.yml
```

#### Option B: Use a Custom Config

```bash
# Copy a config template to the test-run directory
cp configs/default.yml "$TEST_RUN/danube_broker.yml"

# Modify as needed for your scenario, then pass it to make:
# CONFIG_FILE="$TEST_RUN/danube_broker.yml"
```

#### Option C: Use a Test-Specific Config from the Repo

The Danube repo includes test-specific configs:

```bash
ls "$DANUBE_REPO/config/for_tests/"
# danube_broker_rebalance.yml    — aggressive rebalancing
# danube_broker_shared_fs.yml    — shared filesystem storage
# danube_broker_write_buffer.yml — Valkey write buffer
```

### Step 4: Build and Start Brokers

Use the Makefile to build and start brokers:

```bash
cd "$DANUBE_REPO"

# Build and start 3 brokers (default)
make brokers

# Or with a custom config:
# make brokers CONFIG_FILE="$TEST_RUN/danube_broker.yml"

# Or with custom number of brokers:
# make brokers NUM_BROKERS=5
```

**Expected output**:
```
Building Danube brokers...
Seed nodes: 0.0.0.0:7650,0.0.0.0:7651,0.0.0.0:7652
Starting broker 0: client=6650 admin=50051 raft=7650 prom=9040
Starting broker 1: client=6651 admin=50052 raft=7651 prom=9041
Starting broker 2: client=6652 admin=50053 raft=7652 prom=9042

3 broker(s) started — cluster auto-bootstraps via seed nodes.
```

> **Note**: Logs are saved to `temp/broker_<port>.log` in the Danube repo directory.
> For standalone mode, use the `setups/local-binary/` setup instead.

### Step 5: Wait for Readiness

```bash
cd "$DANUBE_REPO"

# Check cluster status (also builds danube-admin if needed)
make cluster-status

# Or manually:
echo "Waiting for cluster readiness..."
for attempt in $(seq 1 30); do
  if ./target/release/danube-admin cluster status 2>/dev/null; then
    echo "Cluster is ready!"
    break
  fi
  echo "  Attempt $attempt/30 — waiting 2s..."
  sleep 2
done
```

**Expected**: Cluster status shows all brokers with a leader elected.

### Step 6: Verify Cluster Health

```bash
cd "$DANUBE_REPO"

# Raft cluster state
./target/release/danube-admin cluster status

# List all brokers and their status
./target/release/danube-admin brokers list

# Identify the cluster leader
./target/release/danube-admin brokers leader

# Check load distribution
./target/release/danube-admin brokers balance
```

**Expected**: All brokers show status `active`, a leader is elected, and load is balanced.

### Step 7: Check Broker Logs

The Makefile saves broker logs to `temp/` in the Danube repo:

```bash
# Check broker 0 logs
tail -30 "$DANUBE_REPO/temp/broker_6650.log"

# Check broker 1 logs
tail -30 "$DANUBE_REPO/temp/broker_6651.log"

# Check broker 2 logs
tail -30 "$DANUBE_REPO/temp/broker_6652.log"

# Look for errors across all brokers
grep -i "error\|panic\|fatal" "$DANUBE_REPO/temp/broker_"*.log
```

**Expected**: No errors or panics. Logs show successful Raft leader election and cluster formation.

### Available Makefile Targets

| Target | Description |
|--------|-------------|
| `make brokers` | Build and start N brokers (default: 3) |
| `make brokers-stop` | Stop all brokers (keep Raft data for restart testing) |
| `make brokers-clean` | Stop all brokers AND delete Raft data |
| `make broker-kill ID=N` | Kill one broker by index (e.g., `make broker-kill ID=0`) |
| `make broker-start ID=N` | Restart one broker by index |
| `make cluster-status` | Show Raft cluster status |
| `make data-clean` | Remove all Raft data directories |
| `make admin` | Start the admin HTTP server on port 8080 |
| `make admin-clean` | Stop the admin server |
| `make prom` | Start Prometheus in Docker on port 9090 |
| `make prom-clean` | Stop Prometheus container |

### Makefile Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NUM_BROKERS` | `3` | Number of broker instances to start |
| `CONFIG_FILE` | `./config/danube_broker.yml` | Path to broker config file |
| `BASE_BROKER_PORT` | `6650` | Starting port for client connections |
| `BASE_ADMIN_PORT` | `50051` | Starting port for admin API |
| `BASE_RAFT_PORT` | `7650` | Starting port for Raft transport |
| `BASE_PROM_PORT` | `9040` | Starting port for Prometheus metrics |

## Verification

- [ ] `cargo build --release` completes successfully
- [ ] `./target/release/danube-broker --version` outputs version
- [ ] `make cluster-status` shows all brokers and a leader
- [ ] `danube-admin brokers list` shows all brokers as `active`
- [ ] `danube-admin brokers balance` shows balanced load
- [ ] Broker logs show no errors: `grep -i error temp/broker_*.log`

## Cleanup

```bash
cd "$DANUBE_REPO"

# Stop all brokers (keep data for restart testing)
make brokers-stop

# Or stop and clean all data
make brokers-clean

# Stop admin server if running
make admin-clean

# Stop Prometheus if running
make prom-clean

# Verify nothing is running
pgrep -la danube-broker && echo "WARNING: still running" || echo "All stopped"
```

## Troubleshooting

- **Cargo build fails**: Ensure Rust toolchain is up to date: `rustup update`. Check that you're on a supported Rust version (check the repo's `rust-toolchain.toml` or `Cargo.toml`).

- **Broker crashes on start**: Check the log file: `tail -50 temp/broker_6650.log`. Common causes: port conflict, corrupted Raft data.

- **Raft cluster won't form**: Delete stale data: `make data-clean`, then restart: `make brokers`.

- **Build is slow**: First build compiles all dependencies (~5-10 minutes). Subsequent builds are incremental and much faster. Use `cargo build --release` for production-like binaries.

- **Can't find the binary**: After `make brokers`, binaries are at `$DANUBE_REPO/target/release/danube-broker` (and `danube-cli`, `danube-admin`).
