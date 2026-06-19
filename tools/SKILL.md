# Skill: Tools — Operational Tool References

## Objective

Teach the AI how to use `danube-cli` (data plane) and `danube-admin` (control plane) as instruments for testing Danube broker functionality.

## Status
🚧 **Coming soon** — This pillar is under construction.

## Tool Overview

| Tool | Scope | When to Use |
|------|-------|-------------|
| **danube-cli** | Data plane: produce, consume, schemas | Every scenario — generating and reading test traffic |
| **danube-admin** | Control plane: cluster, brokers, topics, RBAC, MCP | Multi-broker scenarios — managing cluster state |

## Sub-Skills

- `tools/danube-cli/SKILL.md` — Produce, consume, schema operations
- `tools/danube-admin/SKILL.md` — Cluster, broker, topic, security management

## Quick Reference

### danube-cli (data plane)
```bash
# Produce
danube-cli produce -s http://127.0.0.1:6650 -t /default/topic -c 10 -m "Hello"

# Consume
danube-cli consume -s http://127.0.0.1:6650 -t /default/topic -m my-subscription

# Produce with reliable delivery
danube-cli produce -s http://127.0.0.1:6650 -t /default/topic -c 10 -m "Hello" --reliable
```

### danube-admin (control plane)
```bash
# Cluster status
danube-admin cluster status

# List brokers
danube-admin brokers list

# Check balance
danube-admin brokers balance

# Create topic
danube-admin topics create /default/my-topic
```
