---
name: client-python
description: "Python client library for Danube. Use when generating Python producer/consumer code for testing."
---

# Skill: Python Client — danube-client

## Prerequisites

- Python 3.9+ installed
- pip installed

## Installation

```bash
pip install danube-client
```

## Client Creation

```python
from danube import DanubeClientBuilder

async def main():
    client = await (
        DanubeClientBuilder()
        .service_url("http://127.0.0.1:6650")
        .build()
    )
```

## Producer

### Basic Producer

```python
producer = (
    client.new_producer()
    .with_topic("/default/my-topic")
    .with_name("my-producer")
    .build()
)

await producer.create()

message_id = await producer.send("Hello Danube!".encode())
print(f"Sent message ID: {message_id}")
```

### Send with Attributes

```python
attributes = {
    "source": "app-1",
    "priority": "high",
}

message_id = await producer.send(b"Important message", attributes)
```

### Partitioned Producer

```python
producer = (
    client.new_producer()
    .with_topic("/default/high-throughput")
    .with_name("partitioned-producer")
    .with_partitions(3)
    .build()
)

await producer.create()
```

### Reliable Dispatch Producer

```python
from danube import DispatchStrategy

producer = (
    client.new_producer()
    .with_topic("/default/critical-events")
    .with_name("reliable-producer")
    .with_dispatch_strategy(DispatchStrategy.RELIABLE)
    .build()
)

await producer.create()
```

### Schema-Linked Producer

```python
import json

producer = (
    client.new_producer()
    .with_topic("/default/events")
    .with_name("schema-producer")
    .with_schema_subject("event-schema")
    .build()
)

await producer.create()

event = json.dumps({"user_id": "user-123", "event": "login", "timestamp": 1234567890})
await producer.send(event.encode())
```

## Consumer

### Basic Consumer (Exclusive)

```python
from danube import SubType

consumer = (
    client.new_consumer()
    .with_topic("/default/my-topic")
    .with_consumer_name("my-consumer")
    .with_subscription("my-subscription")
    .with_subscription_type(SubType.EXCLUSIVE)
    .build()
)

await consumer.subscribe()

queue = await consumer.receive()

while True:
    message = await queue.get()
    payload = message.payload.decode()
    print(f"Received: {payload}")
    await consumer.ack(message)
```

### Subscription Types

```python
# Exclusive: single consumer, ordered
.with_subscription_type(SubType.EXCLUSIVE)

# Shared: load balanced across consumers
.with_subscription_type(SubType.SHARED)

# Failover: active/standby
.with_subscription_type(SubType.FAIL_OVER)

# Key-Shared: per-key ordering with parallelism
.with_subscription_type(SubType.KEY_SHARED)
```

### NACK with Retry

```python
while True:
    message = await queue.get()
    try:
        process(message)
        await consumer.ack(message)
    except Exception as e:
        await consumer.nack(message, delay_ms=1000, reason=f"failed: {e}")
```

### Partitioned Consumer

```python
# Consumer auto-discovers all partitions
consumer = (
    client.new_consumer()
    .with_topic("/default/my-topic")  # Parent topic name
    .with_consumer_name("partition-consumer")
    .with_subscription("partition-sub")
    .with_subscription_type(SubType.EXCLUSIVE)
    .build()
)

await consumer.subscribe()
queue = await consumer.receive()
# Automatically receives from all partitions
```

## Key-Shared

### Producer with Routing Keys

```python
# All "payment" messages go to the same consumer
await producer.send_with_key(b"Payment for #1001", None, "payment")

# "shipping" goes to (potentially) a different consumer
await producer.send_with_key(b"Order #1001 shipped", None, "shipping")
```

### Key-Shared Consumer

```python
consumer = (
    client.new_consumer()
    .with_topic("/default/orders")
    .with_consumer_name("worker_1")
    .with_subscription("orders_sub")
    .with_subscription_type(SubType.KEY_SHARED)
    .build()
)

await consumer.subscribe()
queue = await consumer.receive()

while True:
    message = await queue.get()
    key = message.routing_key if message.HasField("routing_key") else ""
    print(f"key={key} payload={message.payload.decode()}")
    await consumer.ack(message)
```

### Key Filtering

```python
# Only receives "payment" and "invoice" messages
consumer = (
    client.new_consumer()
    .with_topic("/default/orders")
    .with_consumer_name("payments_worker")
    .with_subscription("orders_filtered")
    .with_subscription_type(SubType.KEY_SHARED)
    .with_key_filter("payment")
    .with_key_filter("invoice")
    .build()
)

# Or set multiple at once:
# .with_key_filters(["payment", "invoice"])
```

Filter patterns use glob syntax: `"payment"` (exact), `"ship*"` (prefix), `"eu-west-?"` (single char wildcard).

## Schema Registry

### Create Schema Client

```python
schema_client = client.schema()
```

### Register JSON Schema

```python
import json
from danube import SchemaType

json_schema = json.dumps({
    "type": "object",
    "properties": {
        "user_id": {"type": "string"},
        "event": {"type": "string"},
        "timestamp": {"type": "integer"},
    },
    "required": ["user_id", "event", "timestamp"],
})

schema_id = await (
    schema_client.register_schema("user-events")
    .with_type(SchemaType.JSON_SCHEMA)
    .with_schema_data(json_schema.encode())
    .execute()
)
```

### Register Avro Schema

```python
avro_schema = json.dumps({
    "type": "record",
    "name": "UserEvent",
    "fields": [
        {"name": "user_id", "type": "string"},
        {"name": "event", "type": "string"},
        {"name": "timestamp", "type": "long"},
    ],
})

schema_id = await (
    schema_client.register_schema("user-events-avro")
    .with_type(SchemaType.AVRO)
    .with_schema_data(avro_schema.encode())
    .execute()
)
```

### Get / List / Check

```python
# Get latest
schema = await schema_client.get_latest_schema("user-events")
print(f"Schema ID: {schema.schema_id}, Version: {schema.version}")

# List versions
versions = await schema_client.list_versions("user-events")

# Check compatibility
is_compatible, errors = await schema_client.check_compatibility(
    "user-events", new_schema.encode(), SchemaType.JSON_SCHEMA, None
)
```

### Producer Schema Version Strategies

```python
# Latest (default) — always uses newest version
.with_schema_subject("user-events")

# Pinned to version 2
.with_schema_version("user-events", 2)

# Minimum version 2 (uses latest >= 2)
.with_schema_min_version("user-events", 2)
```

## Complete Example: Simple Producer & Consumer

```python
import asyncio
import json
from danube import DanubeClientBuilder, SubType

async def main():
    client = await DanubeClientBuilder().service_url("http://127.0.0.1:6650").build()

    # Producer
    producer = (
        client.new_producer()
        .with_topic("/default/test_topic")
        .with_name("test_producer")
        .build()
    )
    await producer.create()

    for i in range(5):
        msg = f"Message {i}"
        msg_id = await producer.send(msg.encode())
        print(f"Sent: {msg} (ID: {msg_id})")

    # Consumer
    consumer = (
        client.new_consumer()
        .with_topic("/default/test_topic")
        .with_consumer_name("test_consumer")
        .with_subscription("test_sub")
        .with_subscription_type(SubType.EXCLUSIVE)
        .build()
    )
    await consumer.subscribe()

    queue = await consumer.receive()
    while True:
        message = await queue.get()
        print(f"Received: {message.payload.decode()}")
        await consumer.ack(message)

if __name__ == "__main__":
    asyncio.run(main())
```

## Reference Examples

Working examples in the [danube-py repository](https://github.com/danube-messaging/danube-py/tree/main/examples):
- `simple_producer_consumer.py` — basic produce/consume
- `json_producer.py` / `json_consumer.py` — JSON schema
- `avro_producer.py` / `avro_consumer.py` — Avro schema
- `key_shared_producer.py` / `key_shared_consumer.py` — Key-Shared subscription
- `key_shared_filtered_consumer.py` — Key filtering
- `partitions_producer.py` / `partitions_consumer.py` — Partitioned topics
- `reliable_dispatch_producer.py` / `reliable_dispatch_consumer.py` — Reliable delivery
- `schema_evolution.py` — Schema versioning

## Troubleshooting

### PEP 668: "externally-managed-environment" error

On modern Linux (Debian 12+, Ubuntu 24+), `pip install` fails with PEP 668 error. Use a virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install danube-client
```

The AI should create/reuse a venv automatically when installing the Python client.

### "no partitions found" on consumer.subscribe()

The topic **must exist** before calling `consumer.subscribe()`. If the topic doesn't exist, the consumer will fail with `"no partitions found"`. Create the topic first:

```bash
danube-admin topics create /default/my-topic
# or with reliable delivery:
danube-admin topics create /default/my-topic --dispatch-strategy reliable
```

This applies to all client libraries, not just Python.

