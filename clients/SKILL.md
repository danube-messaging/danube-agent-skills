---
name: clients
description: "Client library reference for generating test traffic. Use when writing producer/consumer code in Rust, Go, Python, or Java."
---

# Skill: Clients — Programming Language Libraries

## Objective

Generate producer/consumer scripts in Rust, Go, Python, or Java for testing Danube messaging features. Each language has its own SKILL.md with installation, API reference, and complete code examples.

## Language Selection

| Language | Directory | Install | Best For |
|----------|-----------|---------|----------|
| **Rust** | `clients/rust/` | `cargo add danube-client` | Native performance, Danube development |
| **Python** | `clients/python/` | `pip install danube-client` | Quick prototyping, scripting |
| **Go** | `clients/go/` | `go get github.com/danube-messaging/danube-go` | Microservices, cloud-native |
| **Java** | `clients/java/` | Maven/Gradle dependency | Enterprise, JVM ecosystem |

## AI Decision: Which Language?

Ask the user which language they prefer. If unclear, use this fallback:

| Clue | Language |
|------|----------|
| User says "quick", "script", "simple" | Python |
| User has Go projects open | Go |
| User is developing on Danube source | Rust |
| User mentions Maven, Spring, JVM | Java |
| No preference stated | Ask the user |

## Feature Matrix

All four clients support the same features:

| Feature | Rust | Go | Java | Python |
|---------|:----:|:--:|:----:|:------:|
| Producers & Consumers | ✅ | ✅ | ✅ | ✅ |
| Partitioned Topics | ✅ | ✅ | ✅ | ✅ |
| Reliable Dispatch | ✅ | ✅ | ✅ | ✅ |
| Exclusive Subscription | ✅ | ✅ | ✅ | ✅ |
| Shared Subscription | ✅ | ✅ | ✅ | ✅ |
| Failover Subscription | ✅ | ✅ | ✅ | ✅ |
| Key-Shared Subscription | ✅ | ✅ | ✅ | ✅ |
| JSON Schema | ✅ | ✅ | ✅ | ✅ |
| Avro | ✅ | ✅ | ✅ | ✅ |
| Protobuf | ✅ | ✅ | ✅ | ✅ |
| TLS / mTLS | ✅ | ✅ | ✅ | ✅ |
| JWT Authentication | ✅ | ✅ | ✅ | ✅ |

## Common API Pattern

All clients use the same builder pattern:

1. **Create client** → `DanubeClient.builder().service_url("http://...").build()`
2. **Create producer** → `client.new_producer().with_topic(...).with_name(...).build()`
3. **Create consumer** → `client.new_consumer().with_topic(...).with_subscription(...).with_subscription_type(...).build()`
4. **Register on broker** → `producer.create()` / `consumer.subscribe()`
5. **Send/receive** → `producer.send(payload)` / `consumer.receive()`
6. **Acknowledge** → `consumer.ack(message)`

## Installation

The AI should auto-install the client library for the chosen language. Read the specific language SKILL.md for the install command.

## Sub-Skills

Read the specific language SKILL.md for full API reference and code examples:

- `clients/rust/SKILL.md` — Rust async client (Tokio)
- `clients/python/SKILL.md` — Python async client (asyncio)
- `clients/go/SKILL.md` — Go client (context-based, gRPC)
- `clients/java/SKILL.md` — Java 21+ client (virtual threads, Flow.Publisher)
