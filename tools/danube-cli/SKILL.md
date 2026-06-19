# Skill: danube-cli — Data Plane Operations

## Objective

Reference for using `danube-cli` to produce messages, consume messages, manage schemas, and interact with the Danube data plane.

## Status
🚧 **Coming soon** — Full skill content is under construction.

## Capabilities

| Capability | Key Flags | Used In |
|------------|-----------|---------|
| Produce text messages | `-s`, `-t`, `-m`, `-c`, `--interval` | Every scenario |
| Produce with reliable delivery | `--reliable` | reliable-delivery, topic-migration |
| Produce to partitioned topics | `--partitions` | partitioned-topics |
| Produce with schema | `--schema-subject`, `--schema-file`, `--schema-type` | schema-evolution |
| Produce with attributes | `--attributes "key:val"` | subscription-types (Key-Shared) |
| Consume with subscription types | `--sub-type shared\|exclusive\|fail-over` | subscription-types |
| Schema register/get/versions/check | `schema register`, `schema get` | schema-evolution |

## Installation

Download from [GitHub Releases](https://github.com/danube-messaging/danube/releases) or build from source.
