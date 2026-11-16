# Java SDK (`danube-client`)

Java 21+, virtual threads, and reactive `Flow.Publisher` API. Core messaging, Schema Registry, Key-Shared, TLS/mTLS, and JWT support. Agent RPC wrappers (`extend_lease`, `report_progress`, `cancel_task_tree`, `request_reply`) are Rust-only in v0.17.

## Install

```groovy
// Gradle
implementation 'com.danube-messaging:danube-client:0.4.0'
```

```xml
<!-- Maven -->
<dependency>
    <groupId>com.danube-messaging</groupId>
    <artifactId>danube-client</artifactId>
    <version>0.4.0</version>
</dependency>
```

## Connect

```java
// Plain
DanubeClient client = DanubeClient.builder()
        .serviceUrl("http://127.0.0.1:6650")
        .build();

// TLS + JWT
DanubeClient client = DanubeClient.builder()
        .serviceUrl("https://127.0.0.1:6650")
        .withTls(Path.of("./danube-data/tls/ca.pem"))
        .withToken(System.getenv("DANUBE_TOKEN"))
        .build();
```

For mTLS: `.withMutualTls(caPath, clientCertPath, clientKeyPath)`.

## Producer

```java
Producer producer = client.newProducer()
        .withTopic("/default/orders")
        .withName("orders-producer")
        .withDispatchStrategy(DispatchStrategy.RELIABLE)
        .build();
producer.create();

producer.send("hello".getBytes(), Map.of("source", "java-svc"));
producer.sendWithKey("keyed".getBytes(), Map.of(), "customer-42");
```

Optional: `.withPartitions(3)`, `.withSchemaLatest("orders-value")`.

## Consumer

```java
Consumer consumer = client.newConsumer()
        .withTopic("/default/orders")
        .withConsumerName("worker-1")
        .withSubscription("workers")
        .withSubscriptionType(SubType.SHARED) // EXCLUSIVE | SHARED | FAIL_OVER | KEY_SHARED
        .build();
consumer.subscribe();

consumer.receive().subscribe(new Flow.Subscriber<>() {
    @Override public void onSubscribe(Flow.Subscription s) { s.request(Long.MAX_VALUE); }

    @Override
    public void onNext(StreamMessage msg) {
        try {
            process(msg);
            consumer.ack(msg);
        } catch (Exception e) {
            consumer.nack(msg, 1000, "failed: " + e.getMessage());
        }
    }

    @Override public void onError(Throwable t) { t.printStackTrace(); }
    @Override public void onComplete() {}
});
```
