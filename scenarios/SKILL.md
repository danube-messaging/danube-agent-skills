---
name: scenarios
description: "End-to-end test workflow catalog. Use when running a specific test scenario — each scenario defines required setup, config, tools, and pass/fail criteria."
---

# Skill: Scenarios — End-to-End Test Workflows

## Objective

End-to-end test workflows that combine setups, tools, and clients to validate specific Danube features. Each scenario is a self-contained test with setup requirements, step-by-step instructions, verification criteria, and cleanup.

## Status
✅ **bring-up-cluster** — Implemented and tested
🚧 All other scenarios — Under construction

## Scenario Catalog

| Scenario | Directory | Difficulty | Min Brokers | What It Tests |
|----------|-----------|------------|-------------|---------------|
| **Bring Up Cluster** | `bring-up-cluster/` | Beginner | 1 | Get a running Danube (standalone or cluster) for ad-hoc use |
| **Subscription Types** | `subscription-types/` | Intermediate | 1 | Exclusive, Shared, Failover, Key-Shared |
| **Reliable Delivery** | `reliable-delivery/` | Intermediate | 1 | WAL-backed at-least-once, NACK + retry |
| **Partitioned Topics** | `partitioned-topics/` | Intermediate | 3 | Partitioning, routing modes |
| **Broker Scaling** | `broker-scaling/` | Advanced | 3+ | Scale up/down, Raft membership |
| **Topic Migration** | `topic-migration/` | Advanced | 3 | Reliable topic move, zero loss |
| **Schema Evolution** | `schema-evolution/` | Intermediate | 1 | Schema registry, compatibility |
| **Security RBAC** | `security-rbac/` | Advanced | 1 | TLS, JWT, RBAC roles |
| **Edge MQTT** | `edge-mqtt/` | Intermediate | 1+edge | MQTT ingestion, store-and-forward |
| **Cluster Health** | `cluster-health/` | Intermediate | 3 | Health checks, metrics, diagnostics |

## Scenario Infrastructure Requirements

Each scenario dictates which setup method, config flavors, and Docker Compose flavor to use. The setup and config pillars are dependencies of the scenario — not the other way around.

### Supported Setups per Scenario

| Scenario | Supported Setups | Recommended Setup |
|----------|-----------------|-------------------|
| `bring-up-cluster/` | local-binary, local-source, docker-compose, kubernetes | *(depends on user choice)* |
| `subscription-types/` | local-binary, docker-compose | docker-compose (includes Prometheus) |
| `reliable-delivery/` | docker-compose | docker-compose (needs MinIO) |
| `partitioned-topics/` | docker-compose, local-binary (multi-process) | docker-compose |
| `broker-scaling/` | docker-compose, kubernetes | docker-compose |
| `topic-migration/` | docker-compose | docker-compose |
| `schema-evolution/` | local-binary, docker-compose | local-binary |
| `security-rbac/` | docker-compose, local-binary | docker-compose |
| `edge-mqtt/` | docker-compose + local edge binary | docker-compose + local-binary |
| `cluster-health/` | docker-compose | docker-compose |

### Config Flavors per Scenario

| Scenario | Config Flavors to Apply |
|----------|------------------------|
| `bring-up-cluster/` | *(none — use default.yml as-is or standalone mode)* |
| `subscription-types/` | *(none)* |
| `reliable-delivery/` | Cloud Storage |
| `partitioned-topics/` | Cluster |
| `broker-scaling/` | Cluster + Rebalance |
| `topic-migration/` | Cluster |
| `schema-evolution/` | *(none)* |
| `security-rbac/` | Secure |
| `edge-mqtt/` | Cluster + `edge.yaml` |
| `cluster-health/` | Cluster |

### Docker Compose Flavor per Scenario

| Scenario | Compose Flavor |
|----------|---------------|
| `bring-up-cluster/` | *(depends on user choice)* |
| `subscription-types/` | quickstart (or with-ui for metrics) |
| `reliable-delivery/` | with-cloud-storage |
| `partitioned-topics/` | quickstart |
| `broker-scaling/` | quickstart |
| `topic-migration/` | quickstart (or with-cloud-storage) |
| `schema-evolution/` | quickstart |
| `security-rbac/` | quickstart (with Secure config overlay) |
| `edge-mqtt/` | quickstart + local edge binary |
| `cluster-health/` | with-ui |

## How Scenarios Work

Each scenario SKILL.md follows the template:

1. **Objective** — What you're testing and why
2. **Required Setup** — Which setup method and config flavor
3. **Required Tools** — Which CLI tools are needed
4. **Prerequisites Check** — Commands to verify readiness
5. **Steps** — Step-by-step test execution
6. **Verification** — How to determine pass/fail
7. **Cleanup** — Teardown commands
8. **Troubleshooting** — Common failure modes

The AI reads the scenario SKILL.md, sets up the required infrastructure, runs the steps, and reports results.

## Dependency Hierarchy

Scenarios sit at the top of the dependency chain:

```text
Scenario (what to test)
  └── dictates → Setup (how to run infrastructure)
  └── dictates → Config (which broker configuration)
  └── dictates → Tools & Clients (what to run against the brokers)
```

The scenario decides everything. Setups and configs are generic building blocks — they don't know about scenarios.
