---
name: bring-up-cluster
description: "Get a running Danube instance (standalone or cluster). Use when the user wants Danube running so they can interact with it — the simplest and most common scenario."
---

# Scenario: Bring Up a Danube Cluster

## Objective

Get a running Danube instance — either a single standalone broker or a multi-broker cluster — based on the user's needs and environment. The cluster stays running until the user asks to tear it down.

This is the simplest scenario. It deploys Danube infrastructure and hands it to the user for ad-hoc interaction (produce, consume, inspect, develop, etc.). No automated test steps or pass/fail criteria — just a working Danube.

## When to Use

- User says they want to "try Danube", "start Danube", "run a cluster", "spin up brokers", etc.
- User needs a running Danube to develop against or test with
- User wants to explore the CLI, admin tools, or client libraries
- Any time a running Danube is needed but no specific test scenario is requested

## AI Decision Flow

The AI must gather the following information before running any setup. Ask the user if any are unclear.

### 1. Standalone or Cluster?

| User says | Mode |
|-----------|------|
| "quick test", "single broker", "standalone", "just try it" | **Standalone** (1 broker, no config needed) |
| "cluster", "multi-broker", "3 brokers", "raft", "production-like" | **Cluster** (3 brokers with Raft consensus) |
| *(unclear)* | Ask: "Do you need a single standalone broker for quick testing, or a multi-broker cluster?" |

### 2. Which Setup Method?

| User says | Setup | Script |
|-----------|-------|--------|
| "from source", "I'm developing", "build it" | **Local Source** | `./scripts/setup_local_source.sh` |
| "docker", "compose", "containers" | **Docker Compose** | `./scripts/setup_docker_compose.sh` |
| "kubernetes", "k8s", "helm" | **Kubernetes** | `./scripts/setup_kubernetes.sh` |
| "binary", "download", "no docker" | **Local Binary** | `./scripts/setup_local_binary.sh` |
| *(unclear)* | Ask: "How would you like to run Danube?" and present the options |

**If still unclear**, use this fallback logic:
- User has Docker? → Docker Compose (quickstart)
- User has the Danube repo cloned? → Local Source
- User has a K8s cluster? → Kubernetes
- Default → Local Binary (standalone)

### 3. Additional Parameters

Once mode and setup are known, gather any remaining parameters:

| Setup | What to Ask |
|-------|-------------|
| **Local Binary** | Version to download (default: latest, currently `v0.15.0`) |
| **Local Source** | Path to cloned Danube repository |
| **Docker Compose** | Compose flavor: `quickstart` (default), `with-ui`, `with-cloud-storage` |
| **Kubernetes** | Confirm cluster is accessible (`kubectl cluster-info`) |

## Prerequisites

Prerequisites depend on the chosen setup. Read the setup SKILL.md for the full list:

| Setup | Prerequisites SKILL |
|-------|-------------------|
| Local Binary | `setups/local-binary/SKILL.md` — needs curl/wget, tar |
| Local Source | `setups/local-source/SKILL.md` — needs Rust toolchain, make, cloned repo |
| Docker Compose | `setups/docker-compose/SKILL.md` — needs Docker, Docker Compose, wget |
| Kubernetes | `setups/kubernetes/SKILL.md` — needs kubectl, helm, running cluster |

## Execution

Once all decisions are made, run the appropriate setup script:

```bash
# Standalone broker (local binary)
./scripts/setup_local_binary.sh standalone v0.15.0

# 3-broker cluster (local binary)
./scripts/setup_local_binary.sh cluster v0.15.0 3

# 3-broker cluster (from source)
./scripts/setup_local_source.sh /path/to/danube 3

# 3-broker cluster (Docker Compose)
./scripts/setup_docker_compose.sh quickstart

# 3-broker cluster (Kubernetes)
./scripts/setup_kubernetes.sh
```

## Verification

After setup completes, the script runs verification automatically. The AI should confirm:

### Standalone Mode
- Broker process is running
- `danube-admin cluster status` shows the broker is operational

### Cluster Mode (any setup)
- All brokers are active: `danube-admin brokers list` shows 3 brokers with status `active`
- Leader is elected: `danube-admin cluster status` shows a Leader ID (not `none`)
- All brokers are voters: `Voters` list has 3 entries
- No errors in logs

See the specific setup SKILL.md for expected output formats.

## After Setup

Once the cluster is running, inform the user what they can do:

- **Produce/consume messages**: Use `danube-cli` (see `tools/danube-cli/SKILL.md`)
- **Inspect cluster state**: Use `danube-admin` (see `tools/danube-admin/SKILL.md`)
- **Run a specific scenario**: See `scenarios/SKILL.md` for available test workflows
- **Develop with client libraries**: See `clients/SKILL.md`

## Cleanup

The cluster stays running until the user asks to tear it down. When they do:

```bash
./scripts/cleanup.sh binary    # Local binary
./scripts/cleanup.sh source    # Local source
./scripts/cleanup.sh docker    # Docker Compose
./scripts/cleanup.sh k8s       # Kubernetes
```

## Config Flavors

This scenario uses the **default config** (`configs/default.yml`) with no overlays. For specialized configurations (cloud storage, security, edge), the user should use a more specific scenario or apply config overlays manually — see `configs/flavors/SKILL.md`.
