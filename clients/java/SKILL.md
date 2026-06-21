---
name: client-java
description: "Java client library for Danube. Use when generating Java producer/consumer code for testing."
---

# Skill: Java Client — danube-client

## Prerequisites

- Java 21+ installed
- Maven or Gradle

## Installation

**Gradle:**
```groovy
implementation 'com.danube-messaging:danube-client:0.4.0'
```

**Maven:**
```xml
<dependency>
    <groupId>com.danube-messaging</groupId>
    <artifactId>danube-client</artifactId>
    <version>0.4.0</version>
</dependency>
```

## Client Creation

```java
import com.danube.client.DanubeClient;

DanubeClient client = DanubeClient.builder()
        .serviceUrl("http://127.0.0.1:6650")
        .build();
```

## Producer

### Basic Producer

```java
import com.danube.client.Producer;
import java.util.Map;

Producer producer = client.newProducer()
        .withTopic("/default/my-topic")
        .withName("my-producer")
        .build();

producer.create();

long messageId = producer.send("Hello Danube!".getBytes(), Map.of());
System.out.printf("Sent message ID: %d%n", messageId);
```

### Send with Attributes

```java
Map<String, String> attributes = Map.of(
        "source",   "app-1",
        "priority", "high"
);

long messageId = producer.send("Important message".getBytes(), attributes);
```

### Partitioned Producer

```java
Producer producer = client.newProducer()
        .withTopic("/default/high-throughput")
        .withName("partitioned-producer")
        .withPartitions(3)
        .build();

producer.create();
```

### Reliable Dispatch Producer

```java
import com.danube.client.DispatchStrategy;

Producer producer = client.newProducer()
        .withTopic("/default/critical-events")
        .withName("reliable-producer")
        .withDispatchStrategy(DispatchStrategy.RELIABLE)
        .build();

producer.create();
```

### Schema-Linked Producer

```java
Producer producer = client.newProducer()
        .withTopic("/default/events")
        .withName("schema-producer")
        .withSchemaLatest("event-schema")
        .build();

producer.create();

String event = "{\"user_id\": \"user-123\", \"event\": \"login\", \"timestamp\": 1234567890}";
producer.send(event.getBytes(), Map.of());
```

## Consumer

### Basic Consumer (Exclusive)

```java
import com.danube.client.Consumer;
import com.danube.client.SubType;
import com.danube.client.StreamMessage;
import java.util.concurrent.Flow;

Consumer consumer = client.newConsumer()
        .withTopic("/default/my-topic")
        .withConsumerName("my-consumer")
        .withSubscription("my-subscription")
        .withSubscriptionType(SubType.EXCLUSIVE)
        .build();

consumer.subscribe();

consumer.receive().subscribe(new Flow.Subscriber<>() {
    @Override
    public void onSubscribe(Flow.Subscription s) {
        s.request(Long.MAX_VALUE);
    }

    @Override
    public void onNext(StreamMessage msg) {
        String payload = new String(msg.payload());
        System.out.println("Received: " + payload);
        consumer.ack(msg);
    }

    @Override public void onError(Throwable t) { t.printStackTrace(); }
    @Override public void onComplete() {}
});
```

### Subscription Types

```java
// Exclusive: single consumer, ordered
.withSubscriptionType(SubType.EXCLUSIVE)

// Shared: load balanced across consumers
.withSubscriptionType(SubType.SHARED)

// Failover: active/standby
.withSubscriptionType(SubType.FAIL_OVER)

// Key-Shared: per-key ordering with parallelism
.withSubscriptionType(SubType.KEY_SHARED)
```

### Accessing Message Fields

```java
@Override
public void onNext(StreamMessage msg) {
    String payload = new String(msg.payload());
    System.out.println("Payload: " + payload);

    Map<String, String> attributes = msg.attributes();
    attributes.forEach((k, v) -> System.out.printf("  %s: %s%n", k, v));

    consumer.ack(msg);
}
```

### NACK with Retry

```java
@Override
public void onNext(StreamMessage msg) {
    try {
        process(msg);
        consumer.ack(msg);
    } catch (Exception e) {
        consumer.nack(msg, 1000, "processing failed: " + e.getMessage());
    }
}
```

### Partitioned Consumer

```java
Consumer consumer = client.newConsumer()
        .withTopic("/default/my-topic")  // Parent topic name
        .withConsumerName("partition-consumer")
        .withSubscription("partition-sub")
        .withSubscriptionType(SubType.EXCLUSIVE)
        .build();

consumer.subscribe();
// Automatically receives from all partitions via Flow.Publisher
```

## Key-Shared

### Producer with Routing Keys

```java
// All "payment" messages go to the same consumer
producer.sendWithKey("Payment for #1001".getBytes(), Map.of(), "payment");

// "shipping" goes to (potentially) a different consumer
producer.sendWithKey("Order #1001 shipped".getBytes(), Map.of(), "shipping");
```

### Key-Shared Consumer

```java
Consumer consumer = client.newConsumer()
        .withTopic("/default/orders")
        .withConsumerName("worker_1")
        .withSubscription("orders_sub")
        .withSubscriptionType(SubType.KEY_SHARED)
        .build();

consumer.subscribe();

consumer.receive().subscribe(new Flow.Subscriber<>() {
    @Override public void onSubscribe(Flow.Subscription s) { s.request(Long.MAX_VALUE); }

    @Override
    public void onNext(StreamMessage msg) {
        String key = msg.routingKey() != null ? msg.routingKey() : "";
        System.out.printf("key=%s payload=%s%n", key, new String(msg.payload()));
        consumer.ack(msg);
    }

    @Override public void onError(Throwable t) {}
    @Override public void onComplete() {}
});
```

### Key Filtering

```java
// Only receives "payment" and "invoice" messages
Consumer consumer = client.newConsumer()
        .withTopic("/default/orders")
        .withConsumerName("payments_worker")
        .withSubscription("orders_filtered")
        .withSubscriptionType(SubType.KEY_SHARED)
        .withKeyFilter("payment")
        .withKeyFilter("invoice")
        .build();

// Or set multiple at once:
// .withKeyFilters(List.of("payment", "invoice"))
```

Filter patterns use glob syntax: `"payment"` (exact), `"ship*"` (prefix), `"eu-west-?"` (single char wildcard).

## Schema Registry

### Create Schema Client

```java
import com.danube.client.SchemaRegistryClient;

SchemaRegistryClient schemaClient = client.newSchemaRegistry();
```

### Register JSON Schema

```java
import com.danube.client.SchemaType;

String jsonSchema = """
        {
          "type": "object",
          "properties": {
            "user_id":   {"type": "string"},
            "event":     {"type": "string"},
            "timestamp": {"type": "integer"}
          },
          "required": ["user_id", "event", "timestamp"]
        }""";

var registration = schemaClient.registerSchema(
        schemaClient.newRegistration()
                .withSubject("user-events")
                .withSchemaType(SchemaType.JSON_SCHEMA)
                .withSchemaDefinition(jsonSchema.getBytes()));
```

### Register Avro Schema

```java
String avroSchema = """
        {
          "type": "record",
          "name": "UserEvent",
          "fields": [
            {"name": "user_id",   "type": "string"},
            {"name": "event",     "type": "string"},
            {"name": "timestamp", "type": "long"}
          ]
        }""";

var registration = schemaClient.registerSchema(
        schemaClient.newRegistration()
                .withSubject("user-events-avro")
                .withSchemaType(SchemaType.AVRO)
                .withSchemaDefinition(avroSchema.getBytes()));
```

### Get / List / Check

```java
// Get latest
SchemaInfo schema = schemaClient.getLatestSchema("user-events");
System.out.println("Schema ID: " + schema.schemaId());
System.out.println("Version: " + schema.version());

// List versions
List<SchemaVersionInfo> versions = schemaClient.listVersions("user-events");

// Check compatibility
CompatibilityCheck result = schemaClient.checkCompatibility(
        "user-events", newSchema.getBytes(), SchemaType.JSON_SCHEMA);
if (result.compatible()) {
    System.out.println("Safe to register!");
}
```

### Producer Schema Version Strategies

```java
// Latest (default)
.withSchemaLatest("user-events")

// Pinned to version 2
.withSchemaPinnedVersion("user-events", 2)
```

## Complete Example: Simple Producer & Consumer

```java
import com.danube.client.*;
import java.util.Map;
import java.util.concurrent.Flow;
import java.util.concurrent.CountDownLatch;

public class SimpleProducerConsumer {
    public static void main(String[] args) throws Exception {
        DanubeClient client = DanubeClient.builder()
                .serviceUrl("http://127.0.0.1:6650")
                .build();

        // Producer
        Producer producer = client.newProducer()
                .withTopic("/default/test_topic")
                .withName("test_producer")
                .build();
        producer.create();

        for (int i = 0; i < 5; i++) {
            String msg = "Message " + i;
            long id = producer.send(msg.getBytes(), Map.of());
            System.out.printf("Sent: %s (ID: %d)%n", msg, id);
        }

        // Consumer
        Consumer consumer = client.newConsumer()
                .withTopic("/default/test_topic")
                .withConsumerName("test_consumer")
                .withSubscription("test_sub")
                .withSubscriptionType(SubType.EXCLUSIVE)
                .build();
        consumer.subscribe();

        CountDownLatch latch = new CountDownLatch(5);
        consumer.receive().subscribe(new Flow.Subscriber<>() {
            @Override public void onSubscribe(Flow.Subscription s) { s.request(Long.MAX_VALUE); }

            @Override
            public void onNext(StreamMessage msg) {
                System.out.println("Received: " + new String(msg.payload()));
                consumer.ack(msg);
                latch.countDown();
            }

            @Override public void onError(Throwable t) { t.printStackTrace(); }
            @Override public void onComplete() {}
        });

        latch.await();
    }
}
```

## Reference Examples

Working examples in the [danube-java repository](https://github.com/danube-messaging/danube-java/tree/main/examples):
- `SimpleProducerConsumer.java` — basic produce/consume
- `JsonProducer.java` / `JsonConsumer.java` — JSON schema
- `KeySharedProducer.java` / `KeySharedConsumer.java` — Key-Shared subscription
- `KeySharedFilteredConsumer.java` — Key filtering
- `PartitionsProducer.java` / `PartitionsConsumer.java` — Partitioned topics
- `ReliableDispatchProducer.java` / `ReliableDispatchConsumer.java` — Reliable delivery
- `SchemaEvolution.java` — Schema versioning
- `SchemaRegistryProducerExample.java` — Schema registry API

## Troubleshooting

### "no partitions found" on consumer.subscribe()

The topic **must exist** before calling `consumer.subscribe()`. If the topic doesn't exist, the consumer will fail with `"no partitions found"`. Create the topic first:

```bash
danube-admin topics create /default/my-topic
# or with reliable delivery:
danube-admin topics create /default/my-topic --dispatch-strategy reliable
```

