---
name: scenarios
description: "End-to-end test workflow catalog. Use when running a specific test scenario — each scenario defines required setup, config, tools, and pass/fail criteria."
---

# Skill: Scenarios — End-to-End Test Workflows

## Objective

End-to-end test workflows that combine setups, tools, and clients to validate specific Danube features. Each scenario is a self-contained workflow with setup requirements, step-by-step instructions, and verification criteria.

Scenarios are split into two categories:

- **User Functionality** — validates features that application developers use (messaging, schemas, subscriptions)
- **Operational** — validates features that platform teams / admins use (scaling, migration, security, monitoring)

## Implemented Scenarios

### Infrastructure

| Scenario | Directory | What It Does |
|----------|-----------|-------------|
| **Bring Up Cluster** | `bring-up-cluster/` | Get a running Danube (standalone or cluster) for ad-hoc use |

### User Functionality

| Scenario | Directory | What It Does | Difficulty |
|----------|-----------|-------------|-----------|
| **Core Messaging** | `core-messaging/` | Basic produce/consume with any subscription type, reliability, partitions, schema | Easy |
| **Subscription Patterns** | `subscription-patterns/` | Fan-out (pub-sub) vs queue (work distribution), consumer churn | Easy |
| **Reliable Delivery** | `reliable-delivery/` | NACK redelivery, ack timeout, failure policies (block/drop/dead-letter), reconnection | Intermediate |
| **Schema Lifecycle** | `schema-lifecycle/` | Registration, validation, compatibility modes, version selection, evolution | Intermediate |
| **Key-Shared Advanced** | `key-shared-advanced/` | Glob key filtering, partitioned key-shared, poison handling, consumer churn | Intermediate |

### Operational (Future)

| Scenario | Directory | What It Would Test | Difficulty |
|----------|-----------|-------------------|-----------|
| Topic Migration | *(not implemented)* | Reliable topic move between brokers, offset continuity, zero message loss | Advanced |
| Broker Scaling | *(not implemented)* | Scale up/down, Raft membership changes, rebalancing | Advanced |
| Security RBAC | *(not implemented)* | TLS, JWT tokens, RBAC roles and bindings | Advanced |
| Edge MQTT | *(not implemented)* | MQTT ingestion via edge broker, store-and-forward | Intermediate |
| Cluster Health | *(not implemented)* | Health checks, metrics, diagnostics under failure | Intermediate |

## How Scenarios Work

Each scenario SKILL.md follows this standardized structure:

1. **Objective** — What you're testing and why
2. **When to Use** — Keywords and triggers that match this scenario
3. **Compatible Infrastructure** — Which setup methods and modes (standalone/cluster) this scenario supports. The AI checks if the current running infra is compatible before executing
4. **AI Decision Flow** — Questions to ask the user to configure the test
5. **Execution Steps** — Step-by-step actions
6. **Verification** — How to determine success
7. **Cleanup** — What this scenario's own resources to clean up (topics, scripts)

New scenarios must follow this structure.

## Scenario Independence

**Scenarios are independent of each other.** There are no dependencies between scenarios — only infrastructure can be shared.

```text
Infrastructure (runs/test_YYYYMMDD_HHMMSS/)
  ├── Scenario A  (can run on this infra if compatible)
  ├── Scenario B  (can run on this infra if compatible)
  └── Scenario C  (can run on this infra if compatible)
```

The user may run multiple scenarios on the same infrastructure session. The AI must check the scenario's **Compatible Infrastructure** table against the current running setup to determine if it's possible.

```text
Scenario (what to test)
  └── requires → Compatible infrastructure (setup method + mode)
  └── uses    → Tools & Clients (what to run against the brokers)
  └── may use → Config overlays (if scenario needs specific config)
```

## Runs Directory Convention

Scenario outputs (generated scripts, logs) go **inside the active infra run directory**, not in a separate folder:

```text
runs/test_YYYYMMDD_HHMMSS/          ← created by setup script (infra)
  ├── configs/                       ← broker configs
  ├── data/                          ← broker data (Raft, WAL)
  ├── logs/                          ← broker logs
  └── scenarios/                     ← created by scenario execution
      ├── core-messaging/            ← scenario 1 outputs
      │   ├── producer.py
      │   ├── consumer.py
      │   └── output.log
      └── another-scenario/          ← scenario 2 outputs
```

The AI should detect the active run directory (most recent `runs/test_*/` or the one the user specified) and create `scenarios/<scenario-name>/` inside it.

This keeps everything scoped to one session — the user can run multiple scenarios against the same infra, and `rm -rf runs/test_YYYYMMDD_HHMMSS/` cleans up everything.

## Infrastructure Lifecycle

**Scenarios never tear down infrastructure automatically.** The user may want to run additional scenarios on the same cluster. Scenarios only clean up their own resources (e.g., topics they created).

The user decides when to tear down. When they do:

```bash
./scripts/cleanup.sh binary    # Local binary
./scripts/cleanup.sh source    # Local source
./scripts/cleanup.sh docker    # Docker Compose
./scripts/cleanup.sh k8s       # Kubernetes
```
