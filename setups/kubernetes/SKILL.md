---
name: kubernetes
description: "Deploy Danube to Kubernetes using Helm charts. Use when the user wants to test in a Kubernetes-native environment with Kind or a managed cluster (EKS, GKE, AKS)."
---

# Skill: Kubernetes Setup

## Objective

Deploy Danube to a Kubernetes cluster using Helm charts. This skill deploys Danube into an **existing** Kubernetes cluster — it does not create the cluster itself.

## Prerequisites

Run the prerequisites check before setup:

```bash
./scripts/check_prereqs.sh k8s
```

This verifies `kubectl`, `helm`, Kubernetes cluster connectivity, and checks for existing Danube namespace.

## How to Run

Once prerequisites are confirmed, run the setup script:

```bash
# Deploy Danube to Kubernetes (3 brokers + Envoy proxy + Prometheus)
./scripts/setup_kubernetes.sh

# Cleanup
./scripts/cleanup.sh k8s
```

The script is at `scripts/setup_kubernetes.sh` — read it for the full implementation details.

## Architecture

A Danube Kubernetes deployment uses two Helm charts:

| Chart | What It Deploys |
|-------|----------------|
| **danube-envoy** | Envoy gRPC proxy that routes client requests to the correct broker |
| **danube-core** | Danube broker StatefulSet (3 pods) + Prometheus |

The proxy is installed first because brokers need its address for the `connectUrl` (the external address clients use to connect).

**Traffic flow**: Client → Envoy Proxy → Broker (topic owner)

## Key Concepts

### `externalAccess.enabled=true` Is Required

**This is critical.** The Helm install must include `--set broker.externalAccess.enabled=true`. Without it:
- Brokers don't pass `--advertised-addr` to the container
- The broker's `broker_url` stays `http://0.0.0.0:6650`
- The Raft node can't derive an advertised Raft address from `0.0.0.0`
- Seed peer discovery fails silently — each broker waits forever for manual `danube-admin cluster add-node`
- The cluster **never forms** even though all pods show `Running/Ready`

### Helm Chart Source
Charts are published at `https://danube-messaging.github.io/danube_helm`.

### Seed Nodes Are Automatic
The Helm chart generates `--seed-nodes` from StatefulSet DNS names (e.g., `danube-core-broker-0.danube-core-broker-headless.danube.svc.cluster.local:7650`). No manual seed_nodes config is needed. The `configs/default.yml` has `seed_nodes` commented out — **do not uncomment them** for Kubernetes, the Helm chart handles this via CLI args.

### ConfigMap for Broker Config
The chart expects a ConfigMap named `danube-broker-config` containing `danube_broker.yml`. The setup script creates this from `configs/default.yml`. Do not add `seed_nodes` to this ConfigMap — the Helm chart passes them as CLI arguments.

### Admin Access via Port-Forward
Since brokers run inside the cluster, admin commands require port-forwarding:
```bash
kubectl port-forward danube-core-broker-0 50051:50051 -n danube &
danube-admin brokers list
```

### Image Version
The chart's `appVersion` in `Chart.yaml` controls which broker image tag is used. Override with `--set broker.image.tag=<version>` if needed.

## Verification

The setup script (`scripts/setup_kubernetes.sh`) runs these checks automatically. The expected output is documented here so the AI can confirm the setup is healthy.

### `kubectl get pods -n danube`

All pods must be in `Running` status with `1/1` ready:

```text
NAME                                      READY   STATUS    AGE
danube-core-broker-0                      1/1     Running   2m
danube-core-broker-1                      1/1     Running   2m
danube-core-broker-2                      1/1     Running   2m
danube-core-prometheus-xxxxxxxxx          1/1     Running   3m
danube-envoy-xxxxxxxxx                    1/1     Running   5m
```

### `danube-admin brokers list` (via port-forward)

All brokers must show status `active`. One broker has role `Cluster_Leader`, the rest are `Cluster_Follower`.

```text
BROKER ID       STATUS   ADDRESS                                                              ROLE
---------------------------------------------------------------------------
5804156356...   active   http://danube-core-broker-0.danube-core-broker-headless...:6650       Cluster_Leader
9393761688...   active   http://danube-core-broker-1.danube-core-broker-headless...:6650       Cluster_Follower
1293191161...   active   http://danube-core-broker-2.danube-core-broker-headless...:6650       Cluster_Follower
```

### `danube-admin cluster status` (via port-forward)

```text
Raft Cluster Status:
  Leader:        5804156356532636512
  Term:          1
  Voters:        [5804156356532636512, 9393761688591103413, 12931911617355319510]
```

**Fail indicators:**
- Pods not in `Running` state or `0/1` ready
- `Leader: none` in cluster status
- Fewer voters than expected brokers
- `ERROR`, `PANIC`, or `FATAL` in pod logs

## Cleanup

```bash
./scripts/cleanup.sh k8s
```

## Troubleshooting

- **Pods stuck in Pending**: Check PersistentVolumeClaims: `kubectl get pvc -n danube`. Kind clusters need a default StorageClass (usually provided automatically).

- **Pods in CrashLoopBackOff**: Check pod logs: `kubectl logs danube-core-broker-0 -n danube`. Common causes: invalid config, image pull errors.

- **Envoy proxy not routing**: Check envoy logs: `kubectl logs -l app.kubernetes.io/name=danube-envoy -n danube`.

- **Helm chart not found**: Run `helm repo update` and verify: `helm search repo danube`.

- **Image pull errors**: `docker pull ghcr.io/danube-messaging/danube-broker:latest`. Ensure cluster has access to GitHub Container Registry.

- **Port-forward already running**: `pkill -f "kubectl port-forward"` before retrying.
