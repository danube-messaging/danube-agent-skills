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
```

### Step 1 — Present Scenarios

Show the user what's available, organized by category. The user picks one or more scenarios to run on the same infrastructure.

#### User Functionality (for application developers)

| Scenario | What You're Testing | Difficulty |
|----------|-------------------|-----------|
| **Core Messaging** | Basic produce/consume — pick subscription type, reliability, partitions, schema | Easy |
| **Subscription Patterns** | Fan-out (broadcast) vs Queue (work distribution), consumer churn | Easy |
| **Reliable Delivery** | NACK redelivery, ack timeout, failure policies (block/drop/dead-letter), reconnection | Intermediate |
| **Schema Lifecycle** | Schema registration, validation, compatibility modes, version selection, evolution | Intermediate |
| **Key-Shared Advanced** | Glob key filtering, partitioned key-shared, poison message handling | Intermediate |

#### Operational (for platform teams / admins) — future

| Scenario | What You're Testing | Status |
|----------|-------------------|--------|
| Topic Migration | Reliable topic move between brokers, offset continuity | Not implemented |
| Broker Scaling | Scale up/down, Raft membership changes | Not implemented |
| Security RBAC | TLS, JWT tokens, RBAC roles and bindings | Not implemented |
| Edge MQTT | MQTT ingestion via edge broker, store-and-forward | Not implemented |
| Cluster Health | Health checks, metrics, diagnostics under failure | Not implemented |

#### Infrastructure Only

| Scenario | What You're Doing |
|----------|------------------|
| **Bring Up Cluster** | Get a running Danube (standalone or cluster) for ad-hoc use — no automated test |

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

Each scenario has a **Compatible Infrastructure** table. Check what the scenario supports and ask the user which setup method to use:

| Setup Method | When to Use |
|-------------|------------|
| **Local Binary** | Quickest, no dependencies beyond curl. Good for most tests |
| **Local Source** | User is developing on the Danube codebase |
| **Docker Compose** | User prefers containers. Supports special infra (MinIO, Valkey) |
| **Kubernetes** | User wants to test on a K8s cluster |

If the user selected multiple scenarios, verify all are compatible with the chosen infrastructure.

**If still unclear**, use this fallback:
```text
├── Is the user developing on the Danube source code?
│   ├── YES → setups/local-source/
│   └── NO → continue
├── Does the user prefer Docker?
│   ├── YES → setups/docker-compose/
│   └── NO → continue
├── Does the scenario require Kubernetes features?
│   ├── YES → setups/kubernetes/
│   └── NO → continue
└── Default → setups/local-binary/ (standalone)
```

### Step 4 — Set Up Infrastructure

Run `scenarios/bring-up-cluster/` to deploy Danube, or verify an existing cluster is running. See `setups/SKILL.md` for details on the `$TEST_RUN` directory structure.

### Steps 5–6 — Execute & Verify

Follow the scenario's Execution Steps and Verification criteria. All outputs go into `$TEST_RUN/scenarios/<scenario-name>/` (see `setups/SKILL.md` → **Test-Run Directory**).

## Scenario Independence & Infrastructure Lifecycle

**Scenarios are independent of each other.** There are no dependencies between scenarios — only infrastructure can be shared. The user may run multiple scenarios on the same `$TEST_RUN`:

```text
Infrastructure (runs/test_YYYYMMDD_HHMMSS/)
  ├── Scenario A  (can run on this infra if compatible)
  ├── Scenario B  (can run on this infra if compatible)
  └── Scenario C  (can run on this infra if compatible)
```

The AI must check each scenario's **Compatible Infrastructure** table against the current running setup before executing.

**Scenarios never tear down infrastructure automatically.** They only clean up their own resources (e.g., topics they created). The user decides when to tear down — see `setups/SKILL.md` → **Cleanup**.

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
│   └── key-shared-advanced/SKILL.md    # Key filtering, partitioned key-shared, poison handling
│
├── setups/                     # HOW to run Danube (infrastructure)
│   ├── SKILL.md                # Overview of all setup methods
│   ├── local-binary/SKILL.md   # Download pre-built binaries
│   ├── local-source/SKILL.md   # Build from danube source repo
│   ├── docker-compose/SKILL.md # Run via Docker Compose
│   └── kubernetes/SKILL.md     # Deploy to Kubernetes
│
├── scripts/                    # Executable setup scripts
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
```

## Quick Start: What to Read for Common Tasks

| User Goal | Scenario |
|-----------|----------|
| "I want to try Danube" | `scenarios/bring-up-cluster/` → AI picks setup method |
| "Run a quick test" | `scenarios/bring-up-cluster/` → standalone binary |
| "Test subscriptions" | `scenarios/core-messaging/` → AI asks which type |
| "Fan-out vs queue" | `scenarios/subscription-patterns/` → compare both patterns |
| "Consumer churn" | `scenarios/subscription-patterns/` → churn test |
| "Test reliable delivery" | `scenarios/reliable-delivery/` → NACK, timeout, policies |
| "Dead letter queue" | `scenarios/reliable-delivery/` → DLQ flow |
| "Test schema validation" | `scenarios/schema-lifecycle/` → registration + validation |
| "Schema compatibility" | `scenarios/schema-lifecycle/` → backward/forward/full |
| "Key filtering" | `scenarios/key-shared-advanced/` → glob filter test |
| "Poison message handling" | `scenarios/key-shared-advanced/` → block/drop policies |
| "Send messages with schema" | `scenarios/core-messaging/` → schema=yes |
| "Write a Python producer" | `scenarios/core-messaging/` → Python client |
| "I'm developing Danube" | `scenarios/bring-up-cluster/` → local source setup |
| "Deploy to Kubernetes" | `scenarios/bring-up-cluster/` → kubernetes setup |



## Execution Rules

These rules apply to ALL AI agents using this repository:

### Rule 1: Scenarios First, Infrastructure Second
Always present the available scenarios to the user before asking about infrastructure. The scenario determines what infrastructure is needed, not the other way around.

### Rule 2: Always Ask Before Setting Up Infrastructure
Do not spin up Docker containers, start brokers, or download binaries without telling the user what you are about to do and confirming. Infrastructure decisions should be explicit.

### Rule 3: Check Before Act
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

### Rule 4: Wait for Readiness
A process starting does not mean it is ready. After starting brokers:
- **Local brokers**: Poll with `danube-admin cluster status` until leader is elected
- **Docker Compose**: Wait for `docker compose ps` to show `Up (healthy)` for all brokers
- **Kubernetes**: Wait for `kubectl get pods -n danube` to show `Running` and `1/1 READY`

### Rule 5: Report Progress
Tell the user what you are doing at each major step. Do not run 20 commands in silence.

### Rule 6: Teardown Is Mandatory
If a scenario fails midway, still run cleanup. Port conflicts and orphaned containers from failed runs will break subsequent attempts.
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
