---
name: local-source
description: "Build Danube from source and run brokers locally via Makefile. Use when the user is developing on the Danube codebase and wants to test local changes."
---

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

## How to Run

Use the setup script. It validates the repo path, builds via the Makefile, waits for readiness, and verifies cluster health — all in one command.

```bash
# Build and start a 3-broker cluster from source
./scripts/setup_local_source.sh /path/to/danube 3

# Cleanup
cd /path/to/danube && make brokers-clean
```

The user **must provide the path** to their local Danube source repository. Do not hardcode any path.

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
After `make brokers`, binaries are at `$DANUBE_REPO/target/release/danube-broker` (and `danube-cli`, `danube-admin`). These are local to the source repo, not shared in `bin/<version>/`.

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

## Verification Checklist

- [ ] `cargo build --release` completes successfully
- [ ] `make cluster-status` shows all brokers and a leader
- [ ] `danube-admin brokers list` shows all brokers as `active`
- [ ] `danube-admin brokers balance` shows balanced load
- [ ] Broker logs show no errors: `grep -i "ERROR\|PANIC\|FATAL" temp/broker_*.log`

## Troubleshooting

- **Cargo build fails**: Ensure Rust toolchain is up to date: `rustup update`. Check the repo's `rust-toolchain.toml` or `Cargo.toml` for the required Rust version.

- **Broker crashes on start**: Check the log file: `tail -50 temp/broker_6650.log`. Common causes: port conflict, corrupted Raft data.

- **Raft cluster won't form**: Delete stale data: `make data-clean`, then restart: `make brokers`.

- **Build is slow**: First build compiles all dependencies (~5-10 minutes). Subsequent builds are incremental and much faster.

- **Can't find the binary**: After `make brokers`, binaries are at `$DANUBE_REPO/target/release/danube-broker` (and `danube-cli`, `danube-admin`).
