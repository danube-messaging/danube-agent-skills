---
name: client-rust
description: "Rust client library for Danube. Use when generating Rust producer/consumer code for testing."
---

# Skill: Rust Client — danube-client

## Prerequisites

- Rust toolchain installed (`rustc`, `cargo`)

## Installation

```bash
cargo add danube-client
cargo add tokio --features full
cargo add serde_json  # for JSON messages
```

## Client Creation

```rust
use danube_client::DanubeClient;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = DanubeClient::builder()
        .service_url("http://127.0.0.1:6650")
        .build()
        .await?;

    Ok(())
}
```

## Producer

### Basic Producer

```rust
let mut producer = client
    .new_producer()
    .with_topic("/default/my-topic")
    .with_name("my-producer")
    .build()?;

producer.create().await?;

let message_id = producer
    .send("Hello Danube!".as_bytes().to_vec(), None)
    .await?;

println!("Sent message ID: {}", message_id);
```

### Send with Attributes

```rust
use std::collections::HashMap;

let mut attributes = HashMap::new();
attributes.insert("source".to_string(), "app-1".to_string());
attributes.insert("priority".to_string(), "high".to_string());

let message_id = producer
    .send(b"Important message".to_vec(), Some(attributes))
    .await?;
```

### Partitioned Producer

```rust
let mut producer = client
    .new_producer()
    .with_topic("/default/high-throughput")
    .with_name("partitioned-producer")
    .with_partitions(3)
    .build()?;

producer.create().await?;
```

### Reliable Dispatch Producer

```rust
let mut producer = client
    .new_producer()
    .with_topic("/default/critical-events")
    .with_name("reliable-producer")
    .with_reliable_dispatch()
    .build()?;

producer.create().await?;
```

### Schema-Linked Producer

```rust
let mut producer = client
    .new_producer()
    .with_topic("/default/events")
    .with_name("schema-producer")
    .with_schema_subject("event-schema")
    .build()?;

producer.create().await?;

let event = serde_json::to_vec(&serde_json::json!({
    "user_id": "user-123",
    "event": "login",
    "timestamp": 1234567890
}))?;

producer.send(event, None).await?;
```

## Consumer

### Basic Consumer (Exclusive)

```rust
use danube_client::SubType;

let mut consumer = client
    .new_consumer()
    .with_topic("/default/my-topic")
    .with_consumer_name("my-consumer")
    .with_subscription("my-subscription")
    .with_subscription_type(SubType::Exclusive)
    .build()?;

consumer.subscribe().await?;

let mut stream = consumer.receive().await?;

while let Some(message) = stream.recv().await {
    let payload = String::from_utf8_lossy(&message.payload);
    println!("Received: {}", payload);
    consumer.ack(&message).await?;
}
```

### Subscription Types

```rust
// Exclusive: single consumer, ordered
.with_subscription_type(SubType::Exclusive)

// Shared: load balanced across consumers
.with_subscription_type(SubType::Shared)

// Failover: active/standby
.with_subscription_type(SubType::FailOver)

// Key-Shared: per-key ordering with parallelism
.with_subscription_type(SubType::KeyShared)
```

### Accessing Message Fields

```rust
while let Some(message) = stream.recv().await {
    let payload = String::from_utf8_lossy(&message.payload);
    println!("Payload: {}", payload);

    if let Some(attributes) = &message.attributes {
        for (key, value) in attributes {
            println!("  {}: {}", key, value);
        }
    }

    consumer.ack(&message).await?;
}
```

### NACK with Retry

```rust
while let Some(message) = stream.recv().await {
    match process(&message) {
        Ok(_) => consumer.ack(&message).await?,
        Err(e) => {
            consumer.nack(
                &message,
                Some(1000),                           // retry after 1s
                Some(format!("processing failed: {}", e)),
            ).await?;
        }
    }
}
```

### Partitioned Consumer

```rust
// Consumer auto-discovers all partitions
let mut consumer = client
    .new_consumer()
    .with_topic("/default/my-topic")  // Parent topic name
    .with_consumer_name("partition-consumer")
    .with_subscription("partition-sub")
    .with_subscription_type(SubType::Exclusive)
    .build()?;

consumer.subscribe().await?;
// Automatically receives from all partitions
```

## Key-Shared

### Producer with Routing Keys

```rust
// All "payment" messages go to the same consumer
producer.send_with_key(b"Payment for #1001".to_vec(), None, "payment").await?;

// "shipping" goes to (potentially) a different consumer
producer.send_with_key(b"Order #1001 shipped".to_vec(), None, "shipping").await?;
```

### Key-Shared Consumer

```rust
let mut consumer = client
    .new_consumer()
    .with_topic("/default/orders")
    .with_consumer_name("worker_1")
    .with_subscription("orders_sub")
    .with_subscription_type(SubType::KeyShared)
    .build()?;

consumer.subscribe().await?;
let mut stream = consumer.receive().await?;

while let Some(message) = stream.recv().await {
    let key = message.routing_key.as_deref().unwrap_or("<none>");
    let payload = String::from_utf8_lossy(&message.payload);
    println!("key={:<10} | '{}'", key, payload);
    consumer.ack(&message).await?;
}
```

### Key Filtering

```rust
// Only receives "payment" and "invoice" messages
let mut consumer = client
    .new_consumer()
    .with_topic("/default/orders")
    .with_consumer_name("payments_worker")
    .with_subscription("orders_filtered")
    .with_subscription_type(SubType::KeyShared)
    .with_key_filter("payment")
    .with_key_filter("invoice")
    .build()?;

// Or set multiple at once:
// .with_key_filters(vec!["payment".into(), "invoice".into()])
```

Filter patterns use glob syntax: `"payment"` (exact), `"ship*"` (prefix), `"eu-west-?"` (single char wildcard).

## Schema Registry

### Create Schema Client

```rust
let schema_client = client.schema();
```

### Register JSON Schema

```rust
use danube_client::SchemaType;

let json_schema = r#"{
    "type": "object",
    "properties": {
        "user_id": {"type": "string"},
        "event": {"type": "string"},
        "timestamp": {"type": "integer"}
    },
    "required": ["user_id", "event", "timestamp"]
}"#;

let schema_id = schema_client
    .register_schema("user-events")
    .with_type(SchemaType::JsonSchema)
    .with_schema_data(json_schema.as_bytes())
    .execute()
    .await?;
```

### Register Avro Schema

```rust
let avro_schema = r#"{
    "type": "record",
    "name": "UserEvent",
    "namespace": "com.example",
    "fields": [
        {"name": "user_id", "type": "string"},
        {"name": "event", "type": "string"},
        {"name": "timestamp", "type": "long"},
        {"name": "metadata", "type": ["null", "string"], "default": null}
    ]
}"#;

let schema_id = schema_client
    .register_schema("user-events-avro")
    .with_type(SchemaType::Avro)
    .with_schema_data(avro_schema.as_bytes())
    .execute()
    .await?;
```

### Get / List / Check

```rust
// Get latest
let schema = schema_client.get_latest_schema("user-events").await?;
println!("Schema ID: {}, Version: {}", schema.schema_id, schema.version);

// List versions
let versions = schema_client.list_versions("user-events").await?;

// Check compatibility
let result = schema_client
    .check_compatibility("user-events", new_schema.as_bytes(), SchemaType::JsonSchema, None)
    .await?;
```

### Producer Schema Version Strategies

```rust
// Latest (default) — always uses newest version
.with_schema_subject("user-events")

// Pinned to version 2
.with_schema_version("user-events", 2)

// Minimum version 2 (uses latest >= 2)
.with_schema_min_version("user-events", 2)
```

## Complete Example: Simple Producer & Consumer

```rust
use danube_client::{DanubeClient, SubType};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = DanubeClient::builder()
        .service_url("http://127.0.0.1:6650")
        .build()
        .await?;

    // Producer
    let mut producer = client
        .new_producer()
        .with_topic("/default/test_topic")
        .with_name("test_producer")
        .build()?;
    producer.create().await?;

    // Send messages
    for i in 0..5 {
        let msg = format!("Message {}", i);
        let id = producer.send(msg.as_bytes().to_vec(), None).await?;
        println!("Sent: {} (ID: {})", msg, id);
    }

    // Consumer
    let mut consumer = client
        .new_consumer()
        .with_topic("/default/test_topic")
        .with_consumer_name("test_consumer")
        .with_subscription("test_sub")
        .with_subscription_type(SubType::Exclusive)
        .build()?;
    consumer.subscribe().await?;

    let mut stream = consumer.receive().await?;
    while let Some(message) = stream.recv().await {
        println!("Received: {}", String::from_utf8_lossy(&message.payload));
        consumer.ack(&message).await?;
    }

    Ok(())
}
```

## Reference Examples

Working examples in the Danube source repository at `/danube-client/examples/`:
- `simple_producer_consumer.rs` — basic produce/consume
- `json_producer.rs` / `json_consumer.rs` — JSON schema
- `avro_producer.rs` / `avro_consumer.rs` — Avro schema
- `key_shared_producer.rs` / `key_shared_consumer.rs` — Key-Shared subscription
- `key_shared_filtered_consumer.rs` — Key filtering
- `partitions_producer.rs` / `partitions_consumer.rs` — Partitioned topics
- `reliable_dispatch_producer.rs` / `reliable_dispatch_consumer.rs` — Reliable delivery
- `schema_evolution.rs` — Schema versioning

## Troubleshooting

### "no partitions found" on consumer.subscribe()

The topic **must exist** before calling `consumer.subscribe()`. If the topic doesn't exist, the consumer will fail with `"no partitions found"`. Create the topic first:

```bash
danube-admin topics create /default/my-topic
# or with reliable delivery:
danube-admin topics create /default/my-topic --dispatch-strategy reliable
```

