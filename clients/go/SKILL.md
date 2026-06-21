---
name: client-go
description: "Go client library for Danube. Use when generating Go producer/consumer code for testing."
---

# Skill: Go Client — danube-go

## Prerequisites

- Go 1.21+ installed

## Installation

```bash
go get github.com/danube-messaging/danube-go
```

## Client Creation

```go
package main

import (
    "context"
    "fmt"
    "log"

    danube "github.com/danube-messaging/danube-go"
)

func main() {
    client, err := danube.NewClient().ServiceURL("127.0.0.1:6650").Build()
    if err != nil {
        log.Fatalf("Failed to create client: %v", err)
    }

    ctx := context.Background()
    _ = ctx
}
```

## Producer

### Basic Producer

```go
producer, err := client.NewProducer().
    WithName("my-producer").
    WithTopic("/default/my-topic").
    Build()
if err != nil {
    log.Fatalf("Failed to build producer: %v", err)
}

if err := producer.Create(ctx); err != nil {
    log.Fatalf("Failed to create producer: %v", err)
}

messageID, err := producer.Send(ctx, []byte("Hello Danube!"), nil)
if err != nil {
    log.Fatalf("Failed to send: %v", err)
}

fmt.Printf("Sent message ID: %v\n", messageID)
```

### Send with Attributes

```go
attributes := map[string]string{
    "source":   "app-1",
    "priority": "high",
}

messageID, err := producer.Send(ctx, []byte("Important message"), attributes)
```

### Partitioned Producer

```go
producer, err := client.NewProducer().
    WithName("partitioned-producer").
    WithTopic("/default/high-throughput").
    WithPartitions(3).
    Build()

producer.Create(ctx)
```

### Reliable Dispatch Producer

```go
reliableStrategy := danube.NewReliableDispatchStrategy()

producer, err := client.NewProducer().
    WithName("reliable-producer").
    WithTopic("/default/critical-events").
    WithDispatchStrategy(reliableStrategy).
    Build()

producer.Create(ctx)
```

### Schema-Linked Producer

```go
import "encoding/json"

producer, err := client.NewProducer().
    WithTopic("/default/events").
    WithName("schema-producer").
    WithSchemaSubject("event-schema").
    Build()

producer.Create(ctx)

event := map[string]interface{}{
    "user_id":   "user-123",
    "event":     "login",
    "timestamp": 1234567890,
}
jsonBytes, _ := json.Marshal(event)
producer.Send(ctx, jsonBytes, nil)
```

## Consumer

### Basic Consumer (Exclusive)

```go
consumer, err := client.NewConsumer().
    WithConsumerName("my-consumer").
    WithTopic("/default/my-topic").
    WithSubscription("my-subscription").
    WithSubscriptionType(danube.Exclusive).
    Build()
if err != nil {
    log.Fatalf("Failed to build consumer: %v", err)
}

if err := consumer.Subscribe(ctx); err != nil {
    log.Fatalf("Failed to subscribe: %v", err)
}

stream, err := consumer.Receive(ctx)
if err != nil {
    log.Fatalf("Failed to receive: %v", err)
}

for msg := range stream {
    payload := string(msg.GetPayload())
    fmt.Printf("Received: %s\n", payload)
    _, _ = consumer.Ack(ctx, msg)
}
```

### Subscription Types

```go
// Exclusive: single consumer, ordered
.WithSubscriptionType(danube.Exclusive)

// Shared: load balanced across consumers
.WithSubscriptionType(danube.Shared)

// Failover: active/standby
.WithSubscriptionType(danube.FailOver)

// Key-Shared: per-key ordering with parallelism
.WithSubscriptionType(danube.KeyShared)
```

### Accessing Message Fields

```go
for msg := range stream {
    fmt.Printf("Payload: %s\n", string(msg.GetPayload()))

    for key, value := range msg.GetAttributes() {
        fmt.Printf("  %s: %s\n", key, value)
    }

    _, _ = consumer.Ack(ctx, msg)
}
```

### NACK with Retry

> **API Note:** `Nack` takes pointer arguments: `delayMs *uint64, reason *string`. Use helper variables.

```go
for msg := range stream {
    if err := process(msg); err != nil {
        delayMs := uint64(1000)
        reason := fmt.Sprintf("processing failed: %v", err)
        _, _ = consumer.Nack(ctx, msg, &delayMs, &reason)
    } else {
        _, _ = consumer.Ack(ctx, msg)
    }
}
```

### Partitioned Consumer

```go
consumer, _ := client.NewConsumer().
    WithConsumerName("partition-consumer").
    WithTopic("/default/my-topic").
    WithSubscription("partition-sub").
    WithSubscriptionType(danube.Exclusive).
    Build()

consumer.Subscribe(ctx)
stream, _ := consumer.Receive(ctx)
// Automatically receives from all partitions
```

## Key-Shared

### Producer with Routing Keys

```go
// All "payment" messages go to the same consumer
producer.SendWithKey(ctx, []byte("Payment for #1001"), nil, "payment")

// "shipping" goes to (potentially) a different consumer
producer.SendWithKey(ctx, []byte("Order #1001 shipped"), nil, "shipping")
```

### Key-Shared Consumer

```go
consumer, _ := client.NewConsumer().
    WithConsumerName("worker_1").
    WithTopic("/default/orders").
    WithSubscription("orders_sub").
    WithSubscriptionType(danube.KeyShared).
    Build()

consumer.Subscribe(ctx)
stream, _ := consumer.Receive(ctx)

for msg := range stream {
    fmt.Printf("key=%s payload=%s\n",
        msg.GetRoutingKey(), string(msg.GetPayload()))
    _, _ = consumer.Ack(ctx, msg)
}
```

### Key Filtering

```go
// Only receives "payment" and "invoice" messages
consumer, _ := client.NewConsumer().
    WithConsumerName("payments_worker").
    WithTopic("/default/orders").
    WithSubscription("orders_filtered").
    WithSubscriptionType(danube.KeyShared).
    WithKeyFilter("payment").
    WithKeyFilter("invoice").
    Build()

// Or set multiple at once:
// .WithKeyFilters([]string{"payment", "invoice"})
```

Filter patterns use glob syntax: `"payment"` (exact), `"ship*"` (prefix), `"eu-west-?"` (single char wildcard).

## Schema Registry

### Create Schema Client

```go
schemaClient := client.Schema()
```

### Register JSON Schema

```go
jsonSchema := `{"type": "object", "properties": {"user_id": {"type": "string"}, "event": {"type": "string"}, "timestamp": {"type": "integer"}}, "required": ["user_id", "event", "timestamp"]}`

schemaID, err := client.Schema().RegisterSchema("user-events").
    WithType(danube.SchemaTypeJSONSchema).
    WithSchemaData([]byte(jsonSchema)).
    Execute(ctx)
```

### Register Avro Schema

```go
avroSchema := `{"type": "record", "name": "UserEvent", "fields": [{"name": "user_id", "type": "string"}, {"name": "event", "type": "string"}, {"name": "timestamp", "type": "long"}]}`

schemaID, err := client.Schema().RegisterSchema("user-events-avro").
    WithType(danube.SchemaTypeAvro).
    WithSchemaData([]byte(avroSchema)).
    Execute(ctx)
```

### Get / List

```go
// Get latest
schema, err := client.Schema().GetLatestSchema(ctx, "user-events")
fmt.Printf("Schema ID: %d, Version: %d\n", schema.SchemaID, schema.Version)

// List versions
versions, _ := client.Schema().ListSchemaVersions(ctx, "user-events")
```

### Producer Schema Version Strategies

```go
// Latest (default)
.WithSchemaSubject("user-events")

// Pinned to version 2
.WithSchemaVersion("user-events", 2)

// Minimum version 2
.WithSchemaMinVersion("user-events", 2)
```

## Complete Example: Simple Producer & Consumer

```go
package main

import (
    "context"
    "fmt"
    "log"

    danube "github.com/danube-messaging/danube-go"
)

func main() {
    client, err := danube.NewClient().ServiceURL("127.0.0.1:6650").Build()
    if err != nil {
        log.Fatal(err)
    }

    ctx := context.Background()

    // Producer
    producer, _ := client.NewProducer().
        WithName("test_producer").
        WithTopic("/default/test_topic").
        Build()
    producer.Create(ctx)

    for i := 0; i < 5; i++ {
        msg := fmt.Sprintf("Message %d", i)
        id, _ := producer.Send(ctx, []byte(msg), nil)
        fmt.Printf("Sent: %s (ID: %v)\n", msg, id)
    }

    // Consumer
    consumer, _ := client.NewConsumer().
        WithConsumerName("test_consumer").
        WithTopic("/default/test_topic").
        WithSubscription("test_sub").
        WithSubscriptionType(danube.Exclusive).
        Build()
    consumer.Subscribe(ctx)

    stream, _ := consumer.Receive(ctx)
    for msg := range stream {
        fmt.Printf("Received: %s\n", string(msg.GetPayload()))
        _, _ = consumer.Ack(ctx, msg)
    }
}
```

## Reference Examples

Working examples in the [danube-go repository](https://github.com/danube-messaging/danube-go/tree/main/examples):
- `schema_string/` — basic produce/consume
- `schema_json/` — JSON schema
- `key_shared/` — Key-Shared subscription
- `multi_partitions/` — Partitioned topics
- `reliable_dispatch/` — Reliable delivery

## Troubleshooting

### "no partitions found" on consumer.Subscribe()

The topic **must exist** before calling `consumer.Subscribe()`. If the topic doesn't exist, the consumer will fail with `"no partitions found"`. Create the topic first:

```bash
danube-admin topics create /default/my-topic
# or with reliable delivery:
danube-admin topics create /default/my-topic --dispatch-strategy reliable
```

