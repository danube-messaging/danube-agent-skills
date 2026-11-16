# Rust SDK (`danube-client`)

Full feature support including agent coordination primitives.

## Install

```bash
cargo add danube-client
cargo add tokio --features full
```

## Connect (plain, TLS, auto-TLS, JWT)

```rust
use danube_client::{DanubeClient, SubType};

// Plain
let client = DanubeClient::builder()
    .service_url("http://127.0.0.1:6650")
    .build()
    .await?;

// TLS / auto-TLS + JWT
let token = std::env::var("DANUBE_TOKEN")?;
let client = DanubeClient::builder()
    .service_url("https://127.0.0.1:6650")
    .with_tls("./danube-data/tls/ca.pem")?
    .with_token(token)
    .build()
    .await?;
```

If linking multiple `rustls` crypto backends, install one once at startup:
`rustls::crypto::ring::default_provider().install_default().ok();`

## Producer

```rust
let mut producer = client
    .new_producer()
    .with_topic("/default/orders")
    .with_name("orders-producer")
    .with_reliable_dispatch() // optional if topic already exists as reliable
    .build()?;
producer.create().await?;

producer.send(b"hello".to_vec(), None).await?;
producer.send_with_key(b"keyed".to_vec(), None, "customer-42").await?;
```

Optional builder methods: `.with_partitions(3)`, `.with_schema_subject("orders-value")`, `.with_schema_version("orders-value", 2)`, `.with_schema_min_version("orders-value", 2)`.

## Consumer + ack / nack

```rust
let mut consumer = client
    .new_consumer()
    .with_topic("/default/orders")
    .with_consumer_name("worker-1")
    .with_subscription("workers")
    .with_subscription_type(SubType::Shared) // Exclusive | Shared | FailOver | KeyShared
    .build()?;
consumer.subscribe().await?;
let mut stream = consumer.receive().await?;

while let Some(msg) = stream.recv().await {
    match handle_msg(&msg) {
        Ok(()) => consumer.ack(&msg).await?,
        Err(e) => {
            consumer.nack(&msg, Some(1000), Some(format!("failed: {e}"))).await?;
        }
    }
}
consumer.close().await;
```

## Agent coordination primitives (Rust-only in v0.17)

```rust
use std::collections::HashMap;
use std::time::Duration;
use danube_core::message::{ATTR_COMPUTE_COST_UNITS, ATTR_PARENT_MSG_ID, ATTR_ROOT_MSG_ID};

// 1. Tag subtasks with parent/root/cost headers on produce
let attrs = HashMap::from([
    (ATTR_PARENT_MSG_ID.to_string(), parent_id),
    (ATTR_ROOT_MSG_ID.to_string(), root_id),
    (ATTR_COMPUTE_COST_UNITS.to_string(), "150".to_string()),
]);
producer.send(payload, Some(attrs)).await?;

// 2. Extend lease and save a 64 KiB max checkpoint in broker dispatcher memory
let lease = consumer.extend_lease(&msg, 30_000).await?;
let progress = consumer
    .report_progress(&msg, br#"{"step":3}"#.to_vec(), 30_000)
    .await?;
// On redelivery after worker crash: msg.checkpoint_b64() holds the saved base64 bytes.

// 3. Cancel every subtask sharing a root_msg_id on a target topic
if let Some(root) = msg.root_msg_id() {
    consumer.cancel_task_tree("/agents/subtasks", root, Some("cancelled".into())).await?;
}

// 4. Request/Reply RPC (expects a Non-Reliable reply topic)
let reply = client
    .request_reply("/agents/rpc", "/agents/rpc-replies", b"ping".to_vec(), None, Duration::from_secs(10))
    .await?;
```
