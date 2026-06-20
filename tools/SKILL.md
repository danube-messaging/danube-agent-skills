---
name: tools
description: "Overview of Danube operational tools. Use to understand the difference between danube-cli (data plane) and danube-admin (control plane)."
---

# Skill: Tools — Operational Tool References

## Objective

Teach the AI how to use `danube-cli` (data plane) and `danube-admin` (control plane) as instruments for testing Danube broker functionality.

## Tool Overview

| Tool | Scope | When to Use |
|------|-------|-------------|
| **danube-cli** | Data plane: produce, consume, schemas | Every scenario — generating and reading test traffic |
| **danube-admin** | Control plane: cluster, brokers, topics, RBAC | Multi-broker scenarios — managing cluster state |

## Sub-Skills

- `tools/danube-cli/SKILL.md` — Produce, consume, schema operations
- `tools/danube-admin/SKILL.md` — Cluster, broker, topic, namespace, schema, security management

## Quick Decision

| User Goal | Tool |
|-----------|------|
| Send and receive messages | `danube-cli` |
| Register or check schemas | `danube-cli` (register/get/check) or `danube-admin` (set compatibility, delete, configure topic schema) |
| Create topics with specific dispatch strategy | `danube-admin topics create` |
| Check cluster health | `danube-admin cluster status` + `danube-admin brokers list` |
| Manage namespaces | `danube-admin namespaces` |
| Scale brokers up/down | `danube-admin cluster add-node/remove-node` |

## Installation

Both tools are downloaded as part of the setup scripts (`scripts/setup_local_binary.sh` downloads them to `bin/<version>/`). They can also be installed manually:

```bash
# Linux
curl -L -o danube-cli https://github.com/danube-messaging/danube/releases/latest/download/danube-cli-linux
curl -L -o danube-admin https://github.com/danube-messaging/danube/releases/latest/download/danube-admin-linux
chmod +x danube-cli danube-admin
sudo mv danube-cli danube-admin /usr/local/bin/
```
