# Python SDK (`danube-client`)

Async client built on `asyncio` and `grpc.aio`. Core messaging, Schema Registry, Key-Shared, TLS/mTLS, and JWT support. Agent RPC wrappers (`extend_lease`, `report_progress`, `cancel_task_tree`, `request_reply`) are Rust-only in v0.17.

## Install

```bash
pip install danube-client
```

## Connect

```python
import os
from danube import DanubeClientBuilder, DispatchStrategy, SubType

# Plain
client = await DanubeClientBuilder().service_url("http://127.0.0.1:6650").build()

# TLS + JWT
client = await (
    DanubeClientBuilder()
    .service_url("https://127.0.0.1:6650")
    .with_tls("./danube-data/tls/ca.pem")
    .with_token(os.environ["DANUBE_TOKEN"])
    .build()
)
```

For mTLS: `.with_mtls(ca, client_cert, client_key)`.

## Producer

```python
producer = (
    client.new_producer()
    .with_topic("/default/orders")
    .with_name("orders-producer")
    .with_dispatch_strategy(DispatchStrategy.RELIABLE)
    .build()
)
await producer.create()

await producer.send(b"hello", {"source": "py-svc"})
await producer.send_with_key(b"keyed", None, "customer-42")
```

Optional: `.with_partitions(3)`, `.with_schema_subject("orders-value")`.

## Consumer

```python
consumer = (
    client.new_consumer()
    .with_topic("/default/orders")
    .with_consumer_name("worker-1")
    .with_subscription("workers")
    .with_subscription_type(SubType.SHARED)  # EXCLUSIVE | SHARED | FAIL_OVER | KEY_SHARED
    .build()
)
await consumer.subscribe()
queue = await consumer.receive()

while True:
    msg = await queue.get()
    try:
        process(msg)
        await consumer.ack(msg)
    except Exception as e:
        await consumer.nack(msg, delay_ms=1000, reason=f"failed: {e}")
```
