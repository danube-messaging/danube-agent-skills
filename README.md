# Danube Agent Skills

AI-driven testing skills for [Danube Messaging](https://github.com/danube-messaging/danube).

Structured `SKILL.md` files guide AI agents (Claude Code, Antigravity, Cursor, Windsurf, VS Code Copilot, and others) through setting up clusters, running scenarios, and validating Danube features — from broker scaling to schema evolution to Edge/MQTT ingestion.

## How It Works

1. **Open this repository** in your AI-powered IDE
2. **Tell the AI what you want to test** — e.g., *"I want to test reliable delivery"*
3. **The AI reads `SKILL.md`** to understand the repo, picks the right setup and config, and asks you to confirm
4. **The AI executes the scenario** step by step, reporting progress
5. **Results and cleanup** — the AI reports what passed/failed and tears down the environment

Every test run creates an isolated directory under `runs/` with all generated configs, binaries, and logs. The instruction files are never modified.

## Prerequisites

| Tool | Required For | Install |
|------|-------------|---------|
| Docker + Docker Compose | Docker-based setups | [docs.docker.com](https://docs.docker.com/get-docker/) |
| `danube-cli` | Producing/consuming messages | [GitHub Releases](https://github.com/danube-messaging/danube/releases) |
| `danube-admin` | Cluster administration | [GitHub Releases](https://github.com/danube-messaging/danube/releases) |
| `kubectl` + `helm` | Kubernetes setups | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Rust toolchain | Building from source | [rustup.rs](https://rustup.rs/) |

Not all tools are needed — it depends on which setup method you choose.

## Repository Structure

```text
danube-agent-skills/
├── SKILL.md              # Start here — maps goals to skills
├── configs/              # Broker config templates & flavors
├── setups/               # How to run Danube (binary, Docker, K8s, source)
├── tools/                # danube-cli and danube-admin references
├── clients/              # Client code in Go, Python, Rust, Java
├── scenarios/            # End-to-end test workflows
└── runs/                 # Auto-generated test directories (git-ignored)
```

## Quick Start

Open this repo in your AI IDE and say:

> *"Set up a standalone Danube broker and run a quick produce/consume test"*

The AI will:
1. Read `SKILL.md` to understand the repo
2. Read `configs/SKILL.md` to pick the default config
3. Read `setups/local-binary/SKILL.md` to download and start a broker
4. Run a produce/consume test using `danube-cli`
5. Clean up

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
