---
name: clients
description: "Client library reference for generating test traffic. Use when you need to write producer/consumer code in Go, Python, Rust, or Java."
---

# Skill: Clients — Test Traffic Generators

## Objective

Client code in Go, Python, Rust, and Java for generating test traffic against Danube brokers. Each client has a SKILL.md explaining how to build, configure, and run it.

## Status
🚧 **Coming soon** — Client implementations are under construction.

## Planned Clients

| Client | Directory | Language | Prerequisites |
|--------|-----------|----------|---------------|
| Rust | `client-rust/` | Rust | `cargo` |
| Go | `client-go/` | Go | `go 1.21+` |
| Python | `client-python/` | Python | `python 3.9+`, `pip` |
| Java | `client-java/` | Java | `java 17+`, `maven` |

## Client Selection Guide

| Scenario | Recommended Client |
|----------|-------------------|
| Quick tests | Use `danube-cli` (no client code needed) |
| Custom producer/consumer logic | Pick the language you're most comfortable with |
| Schema testing | Rust or Go (best schema support) |
| Load testing | Go or Rust (best performance) |
