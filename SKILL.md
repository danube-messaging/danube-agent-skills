---
name: danube-agent-skills
description: "Root router for Danube testing skills. Start here — present available scenarios to the user, agree on what to test, then set up infrastructure and run."
---

# Skill: Danube Agent Skills — Root Router

## What Is This Repository?

This repository teaches AI agents how to set up, test, and validate [Danube Messaging](https://github.com/danube-messaging/danube). It contains structured `SKILL.md` files that the AI composes together based on the user's request.

## AI Workflow — Scenario-First Approach

**Scenarios drive everything.** When a user wants to test Danube, follow this workflow:

```text
Step 1: PRESENT available scenarios → User selects what to test
Step 2: CONFIGURE the scenario → AI asks scenario-specific questions
Step 3: AGREE on infrastructure → Setup method + mode derived from scenario
Step 4: SET UP infrastructure → Run setup script, verify readiness
Step 5: EXECUTE the scenario → Run the test steps
Step 6: VERIFY results → Check pass/fail criteria
Step 7: NEXT ACTION → Ask user: another scenario, another aspect, or teardown
```

### Step 1 — Present Scenarios

Show the user what's available, organized by category. The user picks one or more scenarios to run on the same infrastructure.

#### User Functionality (for application developers)

- **Core Messaging** (`scenarios/core-messaging/SKILL.md`):
  Basic produce/consume — pick subscription type, reliability, partitions, schema.
  *Triggers: "test subscriptions", "send messages", "try schemas", "write a Python producer", "send messages with schema"*

- **Subscription Patterns** (`scenarios/subscription-patterns/SKILL.md`):
  Fan-out (broadcast) vs Queue (work distribution), consumer churn.
  *Triggers: "fan-out vs queue", "broadcast", "round-robin", "load balance", "consumer churn"*

- **Reliable Delivery** (`scenarios/reliable-delivery/SKILL.md`):
  NACK redelivery, ack timeout, failure policies (block/drop/dead-letter), consumer reconnection.
  *Triggers: "test reliable delivery", "NACK", "redelivery", "dead letter queue", "at-least-once"*

- **Schema Lifecycle** (`scenarios/schema-lifecycle/SKILL.md`):
  Schema registration, validation, compatibility modes (backward/forward/full/none), version selection, evolution.
  *Triggers: "test schema validation", "schema compatibility", "schema evolution", "schema registry"*

- **Key-Shared Advanced** (`scenarios/key-shared-advanced/SKILL.md`):
  Glob key filtering, partitioned key-shared, poison message handling with failure policies.
  *Triggers: "key filtering", "glob filter", "poison message handling", "key-shared with partitions"*

#### Operational (for platform teams / admins)

- **Broker Scaling & Rebalancing** (`scenarios/broker-scaling/SKILL.md`):
  Scale up/down, Raft membership changes, rebalancing, reliable topic move.
  *Triggers: "scale up", "add broker", "rebalance", "remove node", "topic move", "offset continuity"*

- **Cluster Health & Broker Restart** (`scenarios/cluster-health/SKILL.md`):
  Follower restart, leader restart with re-election, broker failover, health checks.
  *Triggers: "broker restart", "failover", "re-election", "cluster health", "diagnostics"*

- **Security & RBAC** (`scenarios/security-rbac/SKILL.md`):
  TLS certificates, JWT tokens, RBAC roles and bindings, PermissionDenied enforcement.
  *Triggers: "security", "TLS", "tokens", "RBAC", "roles", "permissions"*

- **Edge MQTT Replication** (`scenarios/edge-mqtt/SKILL.md`):
  MQTT ingestion via edge broker, schema validation, topic mapping, store-and-forward.
  *Triggers: "edge", "MQTT", "IoT", "gateway", "store-and-forward"*

#### Infrastructure Only

- **Bring Up Cluster** (`scenarios/bring-up-cluster/SKILL.md`):
  Get a running Danube (standalone or cluster) for ad-hoc use — no automated test.
  *Triggers: "I want to try Danube", "start Danube", "run a cluster", "run a quick test", "I'm developing Danube", "deploy to Kubernetes"*

### Step 2 — Configure the Scenario

Read the selected scenario's `SKILL.md` and follow its **AI Decision Flow** — each scenario asks targeted questions to narrow down what exactly to test. For example:
- `subscription-patterns/` asks: Fan-out or Queue or Both?
- `reliable-delivery/` asks: NACK redelivery or Failure policies or Dead letter?
- `schema-lifecycle/` asks: Backward or Forward or Full compatibility?

Every scenario SKILL.md follows this standardized structure:

1. **Objective** — What you're testing and why
2. **When to Use** — Keywords and triggers that match this scenario
3. **Compatible Infrastructure** — Which setup methods and modes (standalone/cluster) this scenario supports
4. **AI Decision Flow** — Questions to ask the user to configure the test
5. **Execution Steps** — Step-by-step actions
6. **Verification** — How to determine success
7. **Cleanup** — What this scenario's own resources to clean up (topics, scripts)

New scenarios must follow this structure.

### Step 3 — Agree on Infrastructure

Each scenario has a **Compatible Infrastructure** table. Confirm the setup method with the user — present the options and let them choose. Default: **Local Binary**.

| Setup Method | When to Use |
|-------------|------------|
| **Local Binary** (default) | Quickest, no dependencies beyond curl. Good for most tests |
| **Local Source** | User is developing on the Danube codebase |
| **Docker Compose** | User prefers containers. Supports special infra (MinIO, Valkey) |
| **Kubernetes** | User wants to test on a K8s cluster |

### Step 4 — Set Up Infrastructure

Run the prereq check, then the setup script. **Do not run individual commands manually — the scripts handle everything** (download, start, readiness check, verification).

```bash
# 1. Check prerequisites
./scripts/check_prereqs.sh binary   # or: source, docker, k8s

# 2. Run the setup script
./scripts/setup_local_binary.sh standalone v0.15.0   # standalone broker
./scripts/setup_local_binary.sh cluster v0.15.0 3    # 3-broker cluster
./scripts/setup_docker_compose.sh                    # Docker Compose
./scripts/setup_local_source.sh standalone            # build from source
./scripts/setup_kubernetes.sh                         # Kubernetes
```

The script creates `$TEST_RUN`, downloads binaries (if needed), starts brokers, waits for readiness, and prints a summary. Read `setups/SKILL.md` for details on the `$TEST_RUN` directory structure.

### Steps 5–6 — Execute & Verify

Follow the scenario's Execution Steps and Verification criteria. All outputs go into `$TEST_RUN/scenarios/<scenario-name>/`.

**Output capture:** Always pipe test execution through `tee` to create `output.log`:
```bash
python test_patterns.py 2>&1 | tee output.log
go run main.go 2>&1 | tee output.log
```

**Post-test summary:** After the test completes, present a summary to the user:
- **Artifacts created:** list the files in `$TEST_RUN/scenarios/<scenario-name>/` (scripts, logs, data)
- **Test results:** pass/fail for each test flow, with key numbers (e.g., "36/36 messages received")
- **Observations:** anything unexpected, API issues, or SKILL.md gaps discovered during the run
- **Output log path:** point the user to the `output.log` for the full execution trace

### Step 7 — Next Action

**After a test completes, ask the user what to do next:**
- Run another scenario on the **same infrastructure** (no teardown needed)
- Run another aspect/sub-test of the **same scenario** (no teardown needed)
- **Tear down** infrastructure and end the session, see `setups/SKILL.md` → **Cleanup**

**Never auto-teardown.** The user decides when infrastructure is torn down.


## Execution Rules

These rules apply to ALL AI agents using this repository:

### Rule 1: Scenarios First, Infrastructure Second
Always present the available scenarios to the user before asking about infrastructure. The scenario determines what infrastructure is needed, not the other way around.

### Rule 2: Always Ask Before Setting Up Infrastructure
Do not spin up Docker containers, start brokers, or download binaries without telling the user what you are about to do and confirming. Infrastructure decisions should be explicit.

### Rule 3: Check Before Act
Before running any setup, run the prerequisites check script:
```bash
./scripts/check_prereqs.sh binary   # for local binary setup
./scripts/check_prereqs.sh source   # for local source setup
./scripts/check_prereqs.sh docker   # for Docker Compose setup
./scripts/check_prereqs.sh k8s      # for Kubernetes setup
```
This checks required tools, port availability, and existing Danube processes in one command.

### Rule 4: Use the Setup Scripts
**Do not start brokers manually with individual commands.** Always use the setup scripts from `scripts/`. They handle directory creation, binary download, config copying, broker startup, readiness checks, and verification — all in one shot.

### Rule 5: Report Progress
Tell the user what you are doing at each major step. Do not run 20 commands in silence.

### Rule 6: Clean Up on Failure
If a scenario fails midway, still run cleanup to avoid orphaned processes. Port conflicts and stale containers from failed runs will break subsequent attempts. This does NOT mean auto-teardown after success — see **Step 7** for that.
```bash
./scripts/cleanup.sh binary    # Local binary processes
./scripts/cleanup.sh source    # Source-built processes
./scripts/cleanup.sh docker    # Docker Compose services
./scripts/cleanup.sh k8s       # Kubernetes deployment
./scripts/cleanup.sh all       # Everything + remove test-run directories
```

### Rule 7: Observe, Don't Guess
If a command fails, do not retry blindly. Read the relevant logs:
```bash
# Local broker logs
cat "$TEST_RUN/logs/broker_6650.log" | tail -50

# Docker container logs
docker logs danube-broker1 --tail 50

# Kubernetes pod logs
kubectl logs danube-core-broker-0 -n danube --tail 50
```

### Rule 8: Use the Config System
Never hardcode broker configuration. Always:
1. Copy `configs/default.yml` to `$TEST_RUN/danube_broker.yml`
2. Read `configs/flavors/SKILL.md` for the scenario-specific deltas
3. Apply only the documented changes to the copied config
4. Reference the modified config from the setup method

Read `configs/SKILL.md` for the full workflow.

### Rule 9: Scenarios Are Independent
**Scenarios are independent of each other.** There are no dependencies between scenarios — only infrastructure can be shared. The user may run multiple scenarios on the same `$TEST_RUN`:

```text
Infrastructure (runs/test_YYYYMMDD_HHMMSS/)
  ├── Scenario A  (can run on this infra if compatible)
  ├── Scenario B  (can run on this infra if compatible)
  └── Scenario C  (can run on this infra if compatible)
```

The AI must check each scenario's **Compatible Infrastructure** table against the current running setup before executing.

## Repository Structure

```text
danube-agent-skills/
├── SKILL.md                    ← You are here (read this first)
├── README.md                   # Human-readable overview
│
├── scenarios/                  # START HERE — what to test (each has a SKILL.md)
│   ├── bring-up-cluster/SKILL.md       # Get a running Danube
│   ├── core-messaging/SKILL.md         # Basic produce/consume with features
│   ├── subscription-patterns/SKILL.md  # Fan-out vs queue, consumer churn
│   ├── reliable-delivery/SKILL.md      # NACK, ack timeout, failure policies, DLQ
│   ├── schema-lifecycle/SKILL.md       # Registration, compatibility, version selection
│   ├── key-shared-advanced/SKILL.md    # Key filtering, partitioned key-shared, poison handling
│   ├── broker-scaling/SKILL.md         # Scale up/down, rebalance, reliable topic move
│   ├── cluster-health/SKILL.md         # Broker restart, failover, re-election
│   ├── security-rbac/SKILL.md          # TLS, tokens, RBAC roles, PermissionDenied
│   └── edge-mqtt/SKILL.md              # MQTT gateway, schema validation, store-and-forward
│
├── setups/                     # HOW to run Danube (infrastructure)
│   ├── SKILL.md                # Overview of all setup methods
│   ├── local-binary/SKILL.md   # Download pre-built binaries
│   ├── local-source/SKILL.md   # Build from danube source repo
│   ├── docker-compose/SKILL.md # Run via Docker Compose
│   └── kubernetes/SKILL.md     # Deploy to Kubernetes
│
├── scripts/                    # Executable setup & utility scripts
│   ├── check_prereqs.sh        # Verify prerequisites (tools, ports, processes)
│   ├── setup_local_binary.sh   # Download binaries + start brokers
│   ├── setup_local_source.sh   # Build from source + start brokers
│   ├── setup_docker_compose.sh # Docker Compose setup
│   ├── setup_kubernetes.sh     # Kubernetes Helm deployment
│   └── cleanup.sh              # Per-setup cleanup (binary|source|docker|k8s|all)
│
├── configs/                    # Broker configuration
│   ├── SKILL.md                # How the config system works
│   ├── default.yml             # Broker config template
│   ├── edge.yaml               # Edge broker template
│   └── flavors/SKILL.md        # Overlay reference per scenario
│
├── tools/                      # Operational tools
│   ├── SKILL.md                # Overview: CLI vs Admin
│   ├── danube-cli/SKILL.md     # Data plane operations
│   └── danube-admin/SKILL.md   # Control plane operations
│
├── clients/                    # Client libraries for test traffic
│   ├── SKILL.md                # Overview & language selection
│   ├── rust/SKILL.md           # Rust client (danube-client)
│   ├── python/SKILL.md         # Python client (danube-client)
│   ├── go/SKILL.md             # Go client (danube-go)
│   └── java/SKILL.md           # Java client (danube-client)
│
├── bin/                        # Shared downloaded binaries (git-ignored)
│   └── v0.15.0/                # One subdirectory per release version
│
└── runs/                       # Auto-generated test directories (git-ignored)
    └── test_YYYYMMDD_HHMMSS/   # One directory per infra session
        ├── configs/             # Generated broker configs
        ├── data/               # Broker data (Raft, WAL)
        ├── logs/               # Broker logs
        └── scenarios/          # Scenario outputs
            └── core-messaging/ # Scripts and logs from running a scenario
                ├── main.go     # Test script (or .py, .rs, .java)
                └── output.log  # Captured test output (created by tee)
```

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
