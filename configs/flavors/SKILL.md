# Skill: Configuration Flavors — Overlay Reference

## Objective

This file documents the **changes** that each flavor applies on top of `configs/default.yml`. The AI never uses a separate config file per flavor — it copies the default and applies only the documented deltas.

## How to Use

1. **Copy the default**: `cp configs/default.yml "$TEST_RUN/danube_broker.yml"`
2. **Read this file** to find the flavor matching your scenario
3. **Apply only the listed changes** to the copied config
4. **Leave everything else untouched** — the default values are correct

---

## Flavor: Cluster

**When**: Any multi-broker scenario (partitioned-topics, broker-scaling, topic-migration, cluster-health).

**What changes**: Add `seed_nodes` so brokers discover each other via Raft.

### For Docker Compose (brokers are Docker services):
```yaml
# REPLACE in meta_store section:
meta_store:
  data_dir: "./danube-data/raft"
  seed_nodes:
    - "broker1:7650"
    - "broker2:7650"
    - "broker3:7650"
```

### For local binary (brokers on the same host with port offsets):
```yaml
# REPLACE in meta_store section:
meta_store:
  data_dir: "./danube-data/raft"
  seed_nodes:
    - "0.0.0.0:7650"
    - "0.0.0.0:7651"
    - "0.0.0.0:7652"
```

> **Note**: Seed nodes list ALL initial peers including the broker's own Raft address. For Kubernetes, the Helm chart handles seed_nodes via StatefulSet DNS — you typically don't need to set them manually.

---

## Flavor: Rebalance

**When**: broker-scaling, topic-migration, or any scenario testing automated rebalancing.

**What changes**: Enable rebalancing with aggressive settings for fast test feedback.

```yaml
# REPLACE the entire load_manager section:
load_manager:
  assignment_strategy: "fair"
  load_report_interval_seconds: 5       # was: 30 — faster load updates

  rebalancing:
    enabled: true                        # was: false
    aggressiveness: "aggressive"         # was: "balanced" — CV threshold 20%
    check_interval_seconds: 5            # was: 300 — check every 5s
    max_moves_per_hour: 30               # was: 10 — higher limit for testing
    cooldown_seconds: 2                  # was: 60 — short cooldown
    min_brokers_for_rebalance: 2
    min_topic_age_seconds: 30            # was: 300 — eligible after 30s
    blacklist_topics: []
```

> **Combine with**: Cluster flavor (add seed_nodes too).

---

## Flavor: Shared Filesystem Storage

**When**: Testing durable segment export to a shared directory (simulating NFS/EFS).

**What changes**: Switch storage mode from `local` to `shared_fs` and add the durable backend.

```yaml
# REPLACE the storage section:
storage:
  mode: shared_fs                        # was: local
  metadata_prefix: "/danube"
  durable:
    root: "./danube-data/shared-fs"      # ADD: shared directory path
  local_retention:
    time_minutes: 2880
    size_mb: 20480
    check_interval_minutes: 5
  wal:
    rotation:
      max_bytes: 536870912
```

> **Note**: Remove `local_wal_root` — in `shared_fs` mode, the broker auto-derives the local WAL cache path from `meta_store.data_dir`.

---

## Flavor: Cloud Storage (S3/MinIO)

**When**: Testing object store durability with MinIO (Docker) or real S3/GCS/Azure.

**What changes**: Switch storage mode to `object_store`, add durable backend with S3 credentials, optionally use `balanced` assignment strategy.

### For MinIO (Docker Compose with-cloud-storage):
```yaml
# REPLACE the storage section:
storage:
  mode: object_store                     # was: local
  local_wal_root: "./danube-data/wal"
  metadata_prefix: "/danube"
  durable:                               # ADD: entire durable block
    backend: "s3"
    root: "s3://danube-messages/cluster-data"
    region: "us-east-1"
    endpoint: "http://minio:9000"        # MinIO endpoint inside Docker
    access_key: "minioadmin"
    secret_key: "minioadmin123"
    anonymous: false
    virtual_host_style: false
  local_retention:
    time_minutes: 2880
    size_mb: 20480
    check_interval_minutes: 5
  wal:
    rotation:
      max_bytes: 536870912
    advanced:                            # ADD: optional tuning for cloud
      cache_capacity: 1024
      file_sync:
        interval_ms: 5000
        max_batch_bytes: 10485760
```

Optionally change assignment strategy for production-like behavior:
```yaml
# CHANGE in load_manager:
load_manager:
  assignment_strategy: "balanced"        # was: "fair"
```

And increase message size limit:
```yaml
# CHANGE in policies:
policies:
  max_message_size: 52428800             # was: 10485760 (50 MB vs 10 MB)
```

### For AWS S3 (production):
```yaml
# Same as above, but:
#   - Remove endpoint (uses AWS default)
#   - Remove access_key/secret_key (use IAM roles)
#   - Set real bucket and region
storage:
  mode: object_store
  durable:
    backend: "s3"
    root: "s3://your-bucket/danube"
    region: "us-west-2"
```

### For GCS:
```yaml
storage:
  mode: object_store
  durable:
    backend: gcs
    root: "gcs://your-bucket/danube"
    # credentials_path: "/path/to/service-account.json"
```

### For Azure Blob:
```yaml
storage:
  mode: object_store
  durable:
    backend: azblob
    root: "your-container/danube"
    # endpoint: "https://<account>.blob.core.windows.net"
    # account_name: "<account>"
```

---

## Flavor: Write Buffer (Valkey)

**When**: Testing crash recovery, cross-node durability via Valkey double-writes.

**What changes**: Add a `write_buffer` block inside `storage`. This is **additive** — it works with any storage mode (`local`, `shared_fs`, or `object_store`).

```yaml
# ADD inside the storage section (after the wal block):
storage:
  # ... keep existing mode, local_wal_root, retention, wal settings ...

  write_buffer:                          # ADD: entire block
    backend: valkey
    endpoints:
      - "redis://127.0.0.1:6379"        # standalone Valkey
    wait_replicas: 0                     # 0 for standalone, 1+ for replicated
    wait_timeout_ms: 100
    on_wait_timeout: fail                # "fail" = reject write, "ack" = proceed
    max_cached_closed_segments: 5
```

> **Prerequisite**: Start Valkey before the broker:
> ```bash
> docker run -d --name valkey -p 6379:6379 valkey/valkey:latest
> ```
>
> For Docker Compose, add a Valkey service and change endpoint to `redis://valkey:6379`.

### Valkey sizing guide:

| `wait_replicas` | Deployment | Durability |
|-----------------|-----------|------------|
| `0` | Standalone (dev/test) | Survives broker crash, not Valkey crash |
| `1` | Valkey with 1 replica | Survives broker + Valkey primary crash |
| `1` | Valkey Cluster (3+ masters) | Full HA |

| `on_wait_timeout` | Behavior | Use |
|--------------------|----------|-----|
| `fail` | Reject write on timeout | Production |
| `ack` | Proceed anyway, log warning | Development |

---

## Flavor: Secure (TLS + JWT + RBAC)

**When**: security-rbac scenario, or any test requiring authentication.

**What changes**: Switch `auth.mode` from `none` to `tls`, add TLS cert paths, JWT config, and super_admins.

```yaml
# REPLACE the auth section:
auth:
  mode: tls                              # was: none
  tls:                                   # ADD: certificate paths
    cert_file: "./cert/server-cert.pem"
    key_file: "./cert/server-key.pem"
    ca_file: "./cert/ca-cert.pem"
  jwt:                                   # ADD: token config
    secret_key: "your-secret-key"
    issuer: "danube-auth"
    expiration_time: 3600
  super_admins:                          # ADD: bootstrap admin
    - "admin"
```

> **Prerequisites**:
> 1. Generate certificates: `cd cert/ && bash gen_certs.sh` (from the Danube repo)
> 2. Copy certs to test-run directory: `cp cert/*.pem "$TEST_RUN/"`
> 3. Update cert paths in config to point to `$TEST_RUN/`
> 4. After starting, create an admin token:
>    ```bash
>    danube-admin security tokens create --subject admin --secret-key "your-secret-key"
>    ```

---

## Flavor Combinations

Flavors are composable — apply multiple to the same config:

| Scenario | Flavors to Apply |
|----------|-----------------|
| Basic cluster test | Cluster |
| Cluster with rebalancing | Cluster + Rebalance |
| Cloud storage durability | Cluster + Cloud Storage |
| Crash recovery testing | Cluster + Write Buffer |
| Secure cluster | Cluster + Secure |
| Full production-like | Cluster + Cloud Storage + Write Buffer + Secure |
| Edge with cluster | Cluster (for broker config) + Edge template (`configs/edge.yaml`) |

**Apply order**: Cluster first (seed_nodes), then storage/auth changes, then additions (write_buffer).

---

## Configuration Reference

For the complete field reference, see the Danube documentation:
- **Broker config**: https://danube-messaging.com/reference/broker-configuration/
- **Edge config**: https://danube-messaging.com/reference/edge-configuration/
- **Storage & durability**: https://danube-messaging.com/durability/configuration/

### Quick Field Reference

#### Cluster Identity
| Field | Default | Description |
|-------|---------|-------------|
| `cluster_name` | `"MY_CLUSTER"` | Cluster identifier in metrics/logs |

#### Broker Ports
| Field | Default | Description |
|-------|---------|-------------|
| `broker.ports.client` | `6650` | Producer/consumer gRPC |
| `broker.ports.admin` | `50051` | Admin API (danube-admin) |
| `broker.ports.raft` | `7650` | Raft inter-node transport |
| `broker.ports.prometheus` | `9040` | Metrics scrape endpoint |

#### Metadata Store (Raft)
| Field | Default | Description |
|-------|---------|-------------|
| `meta_store.data_dir` | `./danube-data/raft` | Raft log, snapshots, node identity |
| `meta_store.seed_nodes` | *(empty)* | Raft peers for cluster formation. Omit for standalone. |

#### Security Modes
| Mode | Encryption | Auth | Use |
|------|-----------|------|-----|
| `none` | Off | Off | Development |
| `tls` | TLS + mTLS | JWT + RBAC | Production |

#### Storage Modes
| Mode | Backend | Use |
|------|---------|-----|
| `local` | Local WAL only | Single-node, dev |
| `shared_fs` | Shared filesystem | On-prem multi-broker |
| `object_store` | S3/GCS/Azure | Cloud multi-broker |

#### Assignment Strategies
| Strategy | Algorithm | Best For |
|----------|-----------|----------|
| `fair` | Topic count only | Testing |
| `balanced` | Multi-factor (topic_load × 0.3 + CPU × 0.35 + Mem × 0.35) | Production |
| `weighted_load` | Adaptive bottleneck detection | Variable workloads |

#### Rebalancing Aggressiveness Presets
| Level | CV Threshold | Check Interval | Max Moves/Hour | Cooldown |
|-------|-------------|----------------|----------------|----------|
| `conservative` | > 40% | 600s | 5 | 120s |
| `balanced` | > 30% | 300s | 10 | 60s |
| `aggressive` | > 20% | 180s | 20 | 30s |
