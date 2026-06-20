---
name: local-source
description: "Build Danube from source and run brokers locally via Makefile. Use when the user is developing on the Danube codebase and wants to test local changes."
---

# Skill: Local Source Setup

## Objective

Build Danube from the source repository and run brokers locally. This setup is for users who are developing on the Danube codebase and want to test their local changes.

## Prerequisites (verify before running)

Before running the setup script, the AI must confirm these prerequisites:

1. **Ask the user for the Danube source repository path.** The user must have the repo cloned locally. Do not assume or hardcode any path.
2. **Verify the Rust toolchain is installed:** `cargo --version` and `rustc --version`. If not installed, direct the user to [rustup.rs](https://rustup.rs/).
3. **Verify `make` is installed:** `which make`. Required for building and managing brokers.

## How to Run

Once prerequisites are confirmed, run the setup script with the user-provided repo path:

```bash
# Build and start a 3-broker cluster from source
./scripts/setup_local_source.sh /path/to/danube 3

# Cleanup
cd /path/to/danube && make brokers-clean
```

The script is at `scripts/setup_local_source.sh` — read it for the full implementation details.

## Key Concepts

### The Makefile Drives Everything
The Danube source repo has a Makefile that handles building and running brokers. The setup script calls `make brokers` — it does not build or start brokers manually.

Logs are saved to `temp/broker_<port>.log` in the Danube repo directory (not in `$TEST_RUN`).

### This Setup Is Cluster-Only
The Makefile always runs brokers in cluster mode (with config file + seed nodes). For standalone mode, use `setups/local-binary/` instead.

### Config Options
- **Default**: The Makefile uses `./config/danube_broker.yml` from the Danube repo
- **Custom**: Pass `CONFIG_FILE=<path>` to make (e.g., `make brokers CONFIG_FILE=path/to/config.yml`)
- **Test-specific**: The repo includes configs in `config/for_tests/` (rebalance, shared_fs, write_buffer)

### Binaries Are Built Locally
`make brokers` only builds `danube-broker`. The setup script builds `danube-admin` separately for verification (`cargo build --release --package danube-admin`). Binaries are at `$DANUBE_REPO/target/release/`.

## Available Makefile Targets

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

## Makefile Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NUM_BROKERS` | `3` | Number of broker instances to start |
| `CONFIG_FILE` | `./config/danube_broker.yml` | Path to broker config file |
| `BASE_BROKER_PORT` | `6650` | Starting port for client connections |
| `BASE_ADMIN_PORT` | `50051` | Starting port for admin API |
| `BASE_RAFT_PORT` | `7650` | Starting port for Raft transport |
| `BASE_PROM_PORT` | `9040` | Starting port for Prometheus metrics |

## Verification

The setup script (`scripts/setup_local_source.sh`) runs these checks automatically. The expected output is documented here so the AI can confirm the setup is healthy.

### `./target/release/danube-admin brokers list`

All brokers must show status `active`. One broker has role `Cluster_Leader`, the rest are `Cluster_Follower`.

```text
BROKER ID       STATUS   ADDRESS              ROLE              ADMIN ADDR
---------------------------------------------------------------------------
5804156356...   active   http://0.0.0.0:6650  Cluster_Leader    http://0.0.0.0:50051
9393761688...   active   http://0.0.0.0:6651  Cluster_Follower  http://0.0.0.0:50052
1293191161...   active   http://0.0.0.0:6652  Cluster_Follower  http://0.0.0.0:50053
```

### `./target/release/danube-admin cluster status`

The `Leader` field must show a valid node ID (not `none`). All broker node IDs should appear in the `Voters` list.

```text
Raft Cluster Status:
  Self Node ID:  5804156356532636512
  Raft Address:  0.0.0.0:7650
  Leader:        5804156356532636512
  Term:          1
  Last Applied:  18
  Voters:        [5804156356532636512, 9393761688591103413, 12931911617355319510]
```

**Fail indicators:**
- Any broker with status other than `active`
- `Leader: none` in cluster status (no leader elected)
- Fewer voters than expected brokers
- `ERROR`, `PANIC`, or `FATAL` in broker logs: `grep -i "ERROR\|PANIC\|FATAL" temp/broker_*.log`

## Troubleshooting

- **Cargo build fails**: Ensure Rust toolchain is up to date: `rustup update`. Check the repo's `rust-toolchain.toml` or `Cargo.toml` for the required Rust version.

- **Broker crashes on start**: Check the log file: `tail -50 temp/broker_6650.log`. Common causes: port conflict, corrupted Raft data.

- **Raft cluster won't form**: Delete stale data: `make data-clean`, then restart: `make brokers`.

- **Build is slow**: First build compiles all dependencies (~5-10 minutes). Subsequent builds are incremental and much faster.

- **Can't find the binary**: After `make brokers`, binaries are at `$DANUBE_REPO/target/release/danube-broker` (and `danube-cli`, `danube-admin`).
