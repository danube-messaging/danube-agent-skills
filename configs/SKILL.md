---
name: configs
description: "Manage Danube broker configurations. Use when you need to prepare a broker config file, understand when configs are needed (standalone vs cluster vs edge), or apply flavor overlays."
---

# Skill: Broker Configuration System

## Objective

Manage Danube broker configurations for testing. This pillar uses a **single default template** plus a **flavors overlay reference** that documents only the changes needed per scenario. No duplication — one source of truth.

## How It Works

```text
configs/
├── SKILL.md              ← You are here
├── default.yml            # Broker config template (used by cluster mode)
├── edge.yaml              # Edge broker template (used by edge mode)
└── flavors/
    └── SKILL.md           # Overlay reference: what to change per scenario
```

### When Is a Config File Needed?

| Broker Mode | Config File Required? | What to Use |
|-------------|----------------------|-------------|
| **Standalone** | No — `--mode standalone` auto-generates defaults | Nothing |
| **Cluster** | Yes — `--config-file` flag | `configs/default.yml` + flavor overlays |
| **Edge** | Yes — `--edge-config` flag | `configs/edge.yaml` |

### The Model: Copy → Overlay → Run (cluster mode only)

1. **Copy the default**: `cp configs/default.yml "$TEST_RUN/danube_broker.yml"`
2. **Read `configs/flavors/SKILL.md`** to find the changes for your scenario
3. **Apply only the listed deltas** to the copied config
4. **Run the broker** pointing to the modified config

This means:
- There is **exactly one** full config file (`default.yml`)
- Flavors are **documentation**, not files — they describe what to change
- If the default changes, all flavors inherit the change automatically
- Flavors are **composable** — apply multiple to the same config
- Standalone mode skips all of this — no config file needed

### Example: Setting Up a Cluster with Rebalancing

```bash
# 1. Copy default into the test-run directory (flat, no subfolders)
cp configs/default.yml "$TEST_RUN/danube_broker.yml"

# 2. Apply "cluster" flavor: add seed_nodes
#    (AI reads flavors/SKILL.md and edits the meta_store section)

# 3. Apply "rebalance" flavor: enable aggressive rebalancing
#    (AI reads flavors/SKILL.md and replaces the load_manager section)

# 4. Run the broker with the modified config
```

## Default Config (`default.yml`)

The config template for **cluster mode** brokers. Not needed for standalone mode (which auto-generates its own defaults).

| Section | Default | Notes |
|---------|---------|-------|
| `cluster_name` | `MY_CLUSTER` | Change for multi-cluster setups |
| `broker.ports` | client=6650, admin=50051, raft=7650, prom=9040 | Standard port scheme |
| `meta_store.seed_nodes` | *(commented out)* | Must be set for cluster mode |
| `auto_create_topics` | `true` | Producers auto-create topics |
| `auth.mode` | `none` | No authentication |
| `load_manager.assignment_strategy` | `fair` | Simple topic-count balancing |
| `load_manager.rebalancing.enabled` | `false` | No automated rebalancing |
| `storage.mode` | `local` | Local WAL only |
| `dispatch.max_unacked_messages` | `10` | Pipelining depth |
| `policies` | All unlimited (`0`) | No rate or count limits |

## Edge Config (`edge.yaml`)

A separate template for Edge/MQTT scenarios. Not an overlay — it's a different config file for a different broker mode.

```bash
cp configs/edge.yaml "$TEST_RUN/edge.yaml"
# Modify cluster_url to point to your running cluster broker
```

Key fields:
- `edge.edge_name` — Unique name, topics must be under `/{edge_name}/`
- `edge.cluster_url` — Where to replicate messages (default: `http://127.0.0.1:6650`)
- `mqtt.listener` — MQTT listen address (default: `0.0.0.0:1883`)
- `mqtt.topic_mappings` — MQTT → Danube topic routing rules

## Available Flavors

Read `configs/flavors/SKILL.md` for the full overlay reference. Summary:

| Flavor | What Changes | When to Use |
|--------|-------------|-------------|
| **Cluster** | Adds `seed_nodes` to `meta_store` | Any multi-broker scenario |
| **Rebalance** | Enables aggressive rebalancing in `load_manager` | broker-scaling, topic-migration |
| **Shared FS** | Changes `storage.mode` to `shared_fs`, adds `durable.root` | On-prem shared storage testing |
| **Cloud Storage** | Changes `storage.mode` to `object_store`, adds S3/GCS/Azure `durable` block | Cloud durability testing |
| **Write Buffer** | Adds `storage.write_buffer` with Valkey config | Crash recovery testing |
| **Secure** | Changes `auth.mode` to `tls`, adds TLS/JWT/RBAC | Security testing |

Flavors are composable: Cluster + Rebalance, Cluster + Cloud Storage + Write Buffer, etc.

## Configuration Reference

Full reference documentation:
- **Broker config**: https://danube-messaging.com/reference/broker-configuration/
- **Edge config**: https://danube-messaging.com/reference/edge-configuration/
- **Storage & durability**: https://danube-messaging.com/durability/configuration/
