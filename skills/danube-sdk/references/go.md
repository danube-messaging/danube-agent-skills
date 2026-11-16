# Go SDK (`danube-go`)

Core messaging, Schema Registry, Key-Shared, TLS/mTLS, and JWT support. Agent RPC wrappers (`extend_lease`, `report_progress`, `cancel_task_tree`, `request_reply`) are Rust-only in v0.17.

## Install

```bash
go get github.com/danube-messaging/danube-go
```

## Connect

```go
// Plain
client, err := danube.NewClient().ServiceURL("127.0.0.1:6650").Build()

// TLS + JWT
builder, err := danube.NewClient().
    ServiceURL("127.0.0.1:6650").
    WithTLS("./danube-data/tls/ca.pem")
client, err = builder.WithToken(os.Getenv("DANUBE_TOKEN")).Build()
```

For mTLS: `.WithMTLS(ca, clientCert, clientKey)`.

## Producer

```go
ctx := context.Background()
producer, err := client.NewProducer().
    WithTopic("/default/orders").
    WithName("orders-producer").
    WithDispatchStrategy(danube.NewReliableDispatchStrategy()).
    Build()
producer.Create(ctx)

producer.Send(ctx, []byte("hello"), map[string]string{"source": "go-svc"})
producer.SendWithKey(ctx, []byte("keyed"), nil, "customer-42")
```

Optional: `.WithPartitions(3)`, `.WithSchemaSubject("orders-value")`.

## Consumer

```go
consumer, err := client.NewConsumer().
    WithTopic("/default/orders").
    WithConsumerName("worker-1").
    WithSubscription("workers").
    WithSubscriptionType(danube.Shared). // Exclusive | Shared | FailOver | KeyShared
    Build()
consumer.Subscribe(ctx)
stream, err := consumer.Receive(ctx)

for msg := range stream {
    if err := process(msg); err != nil {
        consumer.Nack(ctx, msg, 1000, fmt.Sprintf("failed: %v", err))
    } else {
        consumer.Ack(ctx, msg)
    }
}
```
