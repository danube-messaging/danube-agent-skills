# Skill: Danube Agent Skills — Root Router

## What Is This Repository?

This repository teaches AI agents how to set up, test, and validate [Danube Messaging](https://github.com/danube-messaging/danube). It contains structured `SKILL.md` files organized into five pillars that the AI composes together based on the user's request.

## Repository Structure

```text
danube-agent-skills/
├── SKILL.md                    ← You are here (read this first)
├── README.md                   # Human-readable overview
│
├── configs/                    # Broker configuration templates & flavors
│   ├── SKILL.md                # How the config system works
│   ├── default.yml             # Broker config template (used by cluster mode)
│   ├── edge.yaml               # Edge broker template (for MQTT scenarios)
│   └── flavors/
│       └── SKILL.md            # Overlay reference: what to change per scenario
│
├── setups/                     # How to run Danube (infrastructure)
│   ├── SKILL.md                # Overview of all setup methods
│   ├── local-binary/           # Download pre-built binaries
│   │   └── SKILL.md
│   ├── local-source/           # Build from danube source repo
│   │   └── SKILL.md
│   ├── docker-compose/         # Run via Docker Compose
│   │   └── SKILL.md
│   └── kubernetes/             # Deploy to Kubernetes
│       └── SKILL.md
│
├── scripts/                    # Executable setup scripts (run in one command)
│   ├── setup_local_binary.sh   # Download binaries + start brokers
│   ├── setup_local_source.sh   # Build from source + start brokers
│   ├── setup_docker_compose.sh # Docker Compose setup
│   └── cleanup.sh              # Stop all processes and containers
│
├── tools/                      # Operational tool references
│   ├── SKILL.md                # Overview: CLI vs Admin
│   ├── danube-cli/             # Data plane operations
│   │   └── SKILL.md
│   └── danube-admin/           # Control plane operations
│       └── SKILL.md
│
├── clients/                    # Client libraries for test traffic
│   └── SKILL.md                # Overview & language matrix
│
├── scenarios/                  # End-to-end test workflows
│   └── SKILL.md                # Scenario catalog
│
├── bin/                        # Shared downloaded binaries (git-ignored)
│   └── v0.15.0/                # One subdirectory per release version
│       ├── danube-broker
│       ├── danube-cli
│       └── danube-admin
│
└── runs/                       # Auto-generated test directories (git-ignored)
    └── test_20260619_073955/   # Example: one test run
        ├── danube_broker.yml   # Generated configs (flat at root)
        ├── docker-compose.yml
        ├── data/               # Broker data (Raft, WAL)
        └── logs/               # Broker and test logs
```

## The Five Pillars

| Pillar | Purpose | When to Read |
|--------|---------|-------------|
| **configs/** | One default config + overlay deltas per scenario | Before any setup — choose the right config |
| **setups/** | Infrastructure bootstrapping (binary, Docker, K8s, source) | To spin up Danube brokers |
| **tools/** | How to use `danube-cli` and `danube-admin` | To execute commands against brokers |
| **clients/** | Client code in Go, Python, Rust, Java | To generate test traffic programmatically |
| **scenarios/** | End-to-end test workflows combining all pillars | To run a specific test |

## Setup Selection Decision Tree

When a user wants to test Danube, follow this tree to pick the right setup method:

```text
User wants to test Danube
├── Is the user developing on the Danube source code?
│   ├── YES → setups/local-source/
│   └── NO → continue
├── Does the user prefer Docker?
│   ├── YES → Does the scenario require special infra (MinIO, Valkey)?
│   │   ├── YES → setups/docker-compose/ (with-cloud-storage flavor)
│   │   └── NO → setups/docker-compose/ (quickstart flavor)
│   └── NO → continue
├── Does the scenario require Kubernetes features?
│   ├── YES → setups/kubernetes/
│   └── NO → continue
├── Is a single standalone broker sufficient?
│   ├── YES → setups/local-binary/ (standalone mode)
│   └── NO → setups/local-binary/ (cluster mode with port offsets)
└── Default: setups/docker-compose/ (quickstart)
```

### Scenario → Infrastructure Mapping

Each scenario dictates which setup, config, and tools it needs. See `scenarios/SKILL.md` for the full requirements table.

## Test-Run Isolation Model

**Every test execution creates a unique directory under `runs/`.**

The directory name follows the pattern: `test_<YYYYMMDD_HHMMSS>`

Example: `runs/test_20260619_073955/`

### What goes into a test-run directory:

Configuration files live flat at the root. Runtime data and logs get subdirectories:

| Location | Contents |
|----------|----------|
| `danube_broker.yml` | Generated broker config (for cluster mode) |
| `edge.yaml` | Generated edge config (for edge mode) |
| `docker-compose.yml` | Generated Docker Compose file |
| `prometheus.yml` | Prometheus scrape config |
| `*.pem` | TLS certificates (for secure scenarios) |
| `data/` | Broker data directories (Raft state, WAL files) |
| `logs/` | Broker logs, test output, command transcripts |

> **Binaries are NOT in $TEST_RUN.** They live in the shared `bin/<version>/` directory at the repo root and are reused across all test runs. See `setups/local-binary/SKILL.md`.

### Why isolation matters:

1. **No interference** — Each test run is independent; previous test artifacts don't affect new runs
2. **Clean instruction files** — The SKILL.md files and config templates are never modified
3. **Easy cleanup** — Delete the `runs/test_xxx/` directory to remove all artifacts
4. **Reproducibility** — The generated configs capture exactly what was tested

### How the AI creates a test run:

```bash
# 1. Create the test-run directory
TEST_RUN="runs/test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_RUN"/{data,logs}

# 2. Copy and modify configs as needed (flat at root, no configs/ subfolder)
cp configs/default.yml "$TEST_RUN/danube_broker.yml"
# ... modify for the scenario ...

# 3. Binaries come from shared bin/ directory
DANUBE_BIN="bin/v0.15.0"  # version provided by user

# 4. All subsequent commands use $DANUBE_BIN for binaries, $TEST_RUN for everything else
```

## Execution Rules

These rules apply to ALL AI agents using this repository:

### Rule 1: Always Ask Before Setting Up Infrastructure
Do not spin up Docker containers, start brokers, or download binaries without telling the user what you are about to do and confirming. Infrastructure decisions should be explicit.

### Rule 2: Check Before Act
Before running any setup, verify the environment:
```bash
# Check required tools
which danube-admin && danube-admin --version
which docker && docker --version
docker compose version

# Check port availability
ss -lntp | grep -E '(6650|6651|6652|50051|50052|50053|7650|7651|7652)'

# Check for existing Danube processes
pgrep -la danube-broker
docker ps --filter "name=danube"
```

### Rule 3: Wait for Readiness
A process starting does not mean it is ready. After starting brokers:
- **Local brokers**: Poll with `danube-admin cluster status` until leader is elected
- **Docker Compose**: Wait for `docker compose ps` to show `Up (healthy)` for all brokers
- **Kubernetes**: Wait for `kubectl get pods -n danube` to show `Running` and `1/1 READY`

### Rule 4: Report Progress
Tell the user what you are doing at each major step. Do not run 20 commands in silence.

### Rule 5: Teardown Is Mandatory
If a scenario fails midway, still run cleanup. Port conflicts and orphaned containers from failed runs will break subsequent attempts.

### Rule 6: Observe, Don't Guess
If a command fails, do not retry blindly. Read the relevant logs:
```bash
# Local broker logs
cat "$TEST_RUN/logs/broker_6650.log" | tail -50

# Docker container logs
docker logs danube-broker1 --tail 50

# Kubernetes pod logs
kubectl logs danube-core-broker-0 -n danube --tail 50
```

### Rule 7: Use the Config System
Never hardcode broker configuration. Always:
1. Copy `configs/default.yml` to `$TEST_RUN/danube_broker.yml`
2. Read `configs/flavors/SKILL.md` for the scenario-specific deltas
3. Apply only the documented changes to the copied config
4. Reference the modified config from the setup method

Read `configs/SKILL.md` for the full workflow.

## Port Allocation Scheme

All setup methods use this consistent port scheme:

| Broker Index | Client Port | Admin Port | Raft Port | Prometheus Port |
|-------------|------------|------------|-----------|-----------------|
| 0 | 6650 | 50051 | 7650 | 9040 |
| 1 | 6651 | 50052 | 7651 | 9041 |
| 2 | 6652 | 50053 | 7652 | 9042 |

Additional services:
- **Prometheus**: 9090
- **Admin UI**: 8081
- **Admin Server**: 8080
- **MinIO API**: 9000, **Console**: 9001
- **Edge MQTT**: 1883
- **Edge Broker**: 6653 / 50054 / 7653

## Quick Start: What to Read for Common Tasks

| User Goal | Read These Skills |
|-----------|------------------|
| "I want to try Danube" | `./scripts/setup_docker_compose.sh quickstart` |
| "Run a quick test" | `./scripts/setup_local_binary.sh standalone v0.15.0` |
| "Test broker scaling" | `configs/flavors/SKILL.md` (Cluster + Rebalance) → `setups/docker-compose/SKILL.md` → `scenarios/broker-scaling/SKILL.md` |
| "I'm developing Danube" | `./scripts/setup_local_source.sh /path/to/danube` |
| "Deploy to Kubernetes" | `configs/SKILL.md` → `setups/kubernetes/SKILL.md` |
| "Test Edge/MQTT" | `configs/edge.yaml` → `setups/local-binary/SKILL.md` (edge mode) |
