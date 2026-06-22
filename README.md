# Danube Agent Skills

**Test [Danube Messaging](https://github.com/danube-messaging/danube) using AI — from basic messaging to cluster operations, with zero manual setup.**

This repository contains structured skill files that teach AI coding assistants how to set up, configure, and test Danube clusters. Open it in your AI-powered IDE, describe what you want to test, and the AI handles everything — downloading binaries, starting brokers, running tests, and reporting results.

## Why This Exists

Testing a distributed messaging system usually involves reading docs, downloading binaries, writing configs, and wiring up producers and consumers by hand. **Danube Agent Skills automates all of that.** You describe what you want to test in plain English, and the AI executes a structured, repeatable test scenario.

Whether you're a developer trying out Danube for the first time, or a platform engineer validating cluster failover — there's a scenario for that.

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/danube-messaging/danube-agent-skills.git
cd danube-agent-skills
```

### 2. Open in Your AI IDE

Open this folder in any AI-powered IDE or terminal:

- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code/overview) / [Antigravity](https://deepmind.google/)
- [Cursor](https://cursor.sh/) / [Windsurf](https://codeium.com/windsurf)
- [VS Code + Copilot](https://code.visualstudio.com/docs/copilot/overview)
- Or any agent that reads `SKILL.md` files

### 3. Tell the AI What You Want to Test

Just type a prompt. Here are some examples:

> *"I want to test reliable delivery with NACK redelivery"*

> *"Set up a 3-node cluster and test broker scaling"*

> *"Test fan-out vs queue subscription patterns using Python"*

> *"I want to try schema validation with backward compatibility"*

> *"Set up a secure cluster with TLS and test RBAC permissions"*

> *"Test edge MQTT ingestion with store-and-forward"*

> *"Just bring up a Danube cluster so I can play with it"*

The AI reads the `SKILL.md` files, asks you a few clarifying questions (what to test, which setup method), and then executes everything step by step.

### You Don't Need to Download Anything

The setup scripts handle everything automatically:

- **Binaries** — downloaded from GitHub Releases to a local `bin/` directory
- **Configs** — generated from templates in `configs/`
- **Client libraries** — installed via `pip`, `cargo`, `go get`, or `maven` as needed
- **Infrastructure** — brokers started, clusters formed, namespaces created

Each test run creates an isolated directory under `runs/` with all configs, logs, and data. Nothing is shared between runs.

## Scenarios

Scenarios are structured test workflows. Each one has a clear objective, deterministic test aspects to choose from, step-by-step instructions, and pass/fail criteria.

### User Functionality

For application developers building on top of Danube:

| Scenario | What It Tests |
|----------|--------------|
| **Core Messaging** | Basic produce/consume — pick your subscription type (Exclusive, Shared, Key-Shared, Failover), reliability mode, partitions, and schema. The foundational "hello world" for Danube. |
| **Subscription Patterns** | Fan-out (broadcast to all consumers) vs Queue (round-robin work distribution) vs Consumer Churn (join/leave mid-traffic). Understand how messages are routed. |
| **Reliable Delivery** | At-least-once guarantees — NACK redelivery, ack timeout, failure policies (block/drop/dead-letter), and consumer reconnection failover. The features that keep production systems reliable. |
| **Schema Lifecycle** | Schema registration, validation, compatibility modes (backward/forward/full/none), version pinning, and topic-level schema locking. Control how your data evolves. |
| **Key-Shared Advanced** | Glob-based key filtering, Key-Shared on partitioned topics, and poison message handling. Advanced routing beyond basic per-key affinity. |

### Operational

For platform teams and cluster administrators:

| Scenario | What It Tests |
|----------|--------------|
| **Broker Scaling & Rebalancing** | Scale up (add a broker via Raft join), scale down (safely decommission), and reliable topic move with zero message loss. The full cluster lifecycle. |
| **Cluster Health & Broker Restart** | Follower restart, leader restart with Raft re-election, and broker failover with topic reassignment. Verify your cluster recovers from failures. |
| **Security & RBAC** | TLS certificate setup, JWT token management, RBAC roles/bindings, and PermissionDenied enforcement. Secure your cluster end-to-end. |
| **Edge MQTT Replication** | MQTT devices publish to the edge gateway, which validates schemas, extracts attributes from topic wildcards, and replicates to the cluster. Includes store-and-forward during outages. |

### Infrastructure Only

| Scenario | What It Does |
|----------|-------------|
| **Bring Up Cluster** | Get a running Danube (standalone or cluster) for ad-hoc use — no automated test. Just a working Danube you can interact with. |

## Setup Methods

The AI will ask which setup method to use. Pick whichever fits your environment:

| Method | Best For |
|--------|---------|
| **Local Binary** | Quickest start — downloads pre-built binaries, no dependencies beyond `curl` |
| **Local Source** | Developers working on the Danube codebase — builds from source with `cargo` |
| **Docker Compose** | Container-based setups — supports special infrastructure (MinIO, Valkey) |
| **Kubernetes** | Production-like testing — deploys via Helm chart |

## Repository Structure

```text
danube-agent-skills/
├── SKILL.md              # AI entry point — routes to the right scenario
├── scenarios/            # Test workflows (one per feature area)
│   ├── core-messaging/
│   ├── subscription-patterns/
│   ├── reliable-delivery/
│   ├── schema-lifecycle/
│   ├── key-shared-advanced/
│   ├── broker-scaling/
│   ├── cluster-health/
│   ├── security-rbac/
│   ├── edge-mqtt/
│   └── bring-up-cluster/
├── setups/               # Infrastructure setup methods
│   ├── local-binary/
│   ├── local-source/
│   ├── docker-compose/
│   └── kubernetes/
├── configs/              # Broker config templates & flavors
├── tools/                # danube-cli and danube-admin references
├── clients/              # Client library skills (Python, Rust, Go, Java)
└── runs/                 # Auto-generated test directories (git-ignored)
```

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
