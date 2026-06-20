---
name: danube-admin
description: "Control plane operations with danube-admin. Use for cluster management — broker listing, leader election, rebalancing, namespace management, and cluster status."
---

# Skill: danube-admin — Control Plane Operations

## Objective

Reference for using `danube-admin` to manage Danube clusters, brokers, topics, schemas, security, and MCP server mode.

## Status
🚧 **Coming soon** — Full skill content is under construction.

## Capabilities

| Capability | Command | Used In |
|------------|---------|---------|
| Cluster status | `cluster status` | Every multi-broker scenario |
| Add broker (learner) | `cluster add-node --node-addr` | broker-scaling |
| Promote to voter | `cluster promote-node --node-id` | broker-scaling |
| Remove from cluster | `cluster remove-node --node-id` | broker-scaling |
| List brokers | `brokers list` | Every multi-broker scenario |
| Activate broker | `brokers activate <ID>` | broker-scaling |
| Unload broker | `brokers unload <ID> [--dry-run]` | broker-scaling, topic-migration |
| Check balance | `brokers balance` | broker-scaling, topic-migration, cluster-health |
| Rebalance | `brokers rebalance [--dry-run]` | broker-scaling, topic-migration |
| Create topic | `topics create <path>` | Several scenarios |
| Describe topic | `topics describe <path>` | Several scenarios |
| MCP server mode | `serve --mode mcp` | cluster-health (optional) |

## Installation

Download from [GitHub Releases](https://github.com/danube-messaging/danube/releases) or build from source.
