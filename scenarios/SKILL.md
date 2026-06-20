---
name: scenarios
description: "End-to-end test workflow catalog. Use when running a specific test scenario — each scenario defines required setup, config, tools, and pass/fail criteria."
---

# Skill: Scenarios — End-to-End Test Workflows

## Objective

End-to-end test workflows that combine setups, tools, and clients to validate specific Danube features. Each scenario is a self-contained workflow with setup requirements, step-by-step instructions, and verification criteria.

## Implemented Scenarios

| Scenario | Directory | What It Does |
|----------|-----------|-------------|
| **Bring Up Cluster** | `bring-up-cluster/` | Get a running Danube (standalone or cluster) for ad-hoc use |
| **Core Messaging** | `core-messaging/` | Test subscriptions, schemas, reliable delivery, partitioned topics |

## How Scenarios Work

Each scenario SKILL.md follows this structure:

1. **Objective** — What you're testing and why
2. **AI Decision Flow** — Questions to ask the user to configure the test
3. **Prerequisites** — What must be running before the scenario starts
4. **Execution Steps** — Step-by-step actions
5. **Verification** — How to determine success
6. **Cleanup** — Teardown commands

The AI reads the scenario SKILL.md, asks the user any necessary questions, sets up the required infrastructure, runs the steps, and reports results.

## Dependency Hierarchy

Scenarios sit at the top of the dependency chain:

```text
Scenario (what to test)
  └── dictates → Setup (how to run infrastructure)
  └── dictates → Config (which broker configuration)
  └── dictates → Tools & Clients (what to run against the brokers)
```

The scenario decides everything. Setups and configs are generic building blocks.

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

## Maybe (Future Ideas)

These scenarios are ideas for future implementation. They are not yet built.

| Scenario | Difficulty | What It Would Test |
|----------|------------|-------------------|
| Subscription Types Deep Dive | Intermediate | Exclusive vs Shared vs Failover vs Key-Shared side-by-side comparison |
| Reliable Delivery Stress Test | Intermediate | WAL-backed at-least-once under load, NACK + retry |
| Partitioned Topics | Intermediate | Partitioning, routing modes, cross-partition ordering |
| Broker Scaling | Advanced | Scale up/down, Raft membership changes |
| Topic Migration | Advanced | Reliable topic move between brokers, zero message loss |
| Schema Evolution | Intermediate | Schema versioning, compatibility modes, breaking change detection |
| Security RBAC | Advanced | TLS, JWT tokens, RBAC roles and bindings |
| Edge MQTT | Intermediate | MQTT ingestion via edge broker, store-and-forward |
| Cluster Health | Intermediate | Health checks, metrics, diagnostics under failure |
