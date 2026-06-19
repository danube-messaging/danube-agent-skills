# Skill: Kubernetes Setup

## Objective

Deploy Danube to a Kubernetes cluster using Helm charts. This setup is for users who want to test Danube in a Kubernetes-native environment, either locally with Kind or on a managed cluster (EKS, GKE, AKS).

## Difficulty
Advanced

## Required Setup
None — this IS the setup.

## Required Tools
- `kubectl` — Kubernetes CLI
- `helm` 3.0+ — Helm package manager
- A Kubernetes cluster (Kind for local, or existing EKS/GKE/AKS)
- `docker` — Required for Kind clusters
- `danube-cli` — For testing (local binary or from test-run binaries)

## Prerequisites Check

```bash
# Check kubectl
which kubectl && kubectl version --client

# Check Helm
which helm && helm version

# Check Docker (for Kind)
which docker && docker --version

# Check for existing Danube namespace
kubectl get namespace danube 2>/dev/null && echo "Danube namespace exists" || echo "No danube namespace"

# Check Kind (if using local cluster)
which kind && kind version
```

## Architecture

A Danube Kubernetes deployment uses two Helm charts:

| Chart | What It Deploys |
|-------|----------------|
| **danube-envoy** | Envoy gRPC proxy that routes client requests to the correct broker |
| **danube-core** | Danube broker StatefulSet (3 pods) + Prometheus |

The proxy is installed first because brokers need its address for the `connectUrl` (the external address clients use to connect).

**Traffic flow**: Client → Envoy Proxy → Broker (topic owner)

## Steps

### Step 1: Create the Test-Run Directory

```bash
TEST_RUN="runs/test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_RUN"/{data,logs}
echo "Test run directory: $TEST_RUN"
```

### Step 2: Create a Kubernetes Cluster (skip if you have one)

#### Using Kind (local)

```bash
kind create cluster --name danube-test
kubectl cluster-info --context kind-danube-test
```

**Expected**: Kind cluster created, kubectl context set.

#### Using an Existing Cluster

```bash
# Verify access
kubectl cluster-info
kubectl get nodes
```

### Step 3: Add the Danube Helm Repository

```bash
helm repo add danube https://danube-messaging.github.io/danube_helm
helm repo update
```

**Expected**: `"danube" has been added to your repositories`

Verify available charts:
```bash
helm search repo danube
```

### Step 4: Create the Danube Namespace

```bash
kubectl create namespace danube
```

### Step 5: Install the Envoy Proxy

```bash
helm install danube-envoy danube/danube-envoy -n danube
```

Wait for the proxy pod to be ready:
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=danube-envoy -n danube --timeout=120s
```

### Step 6: Discover the Proxy Address

```bash
PROXY_PORT=$(kubectl get svc danube-envoy -n danube \
  -o jsonpath='{.spec.ports[?(@.name=="grpc")].nodePort}')
NODE_IP=$(kubectl get nodes \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "Proxy address: ${NODE_IP}:${PROXY_PORT}"

# Save for later use
echo "${NODE_IP}:${PROXY_PORT}" > "$TEST_RUN/proxy_address.txt"
```

> **For managed K8s (EKS, GKE, AKS)**: Change the service type to `LoadBalancer` in the danube-envoy Helm values and use the external IP instead of NodePort.

### Step 7: Prepare Broker Configuration

```bash
# Copy the default config
cp configs/default.yml "$TEST_RUN/danube_broker.yml"

# For specific scenarios, apply overlays from configs/flavors/SKILL.md
# (e.g., Rebalance flavor for broker-scaling tests)
```

> **Note**: For Kubernetes, seed_nodes are handled by the Helm chart via StatefulSet DNS names. You typically don't need to set them manually in the config.

### Step 8: Create the ConfigMap

```bash
kubectl create configmap danube-broker-config \
  --from-file=danube_broker.yml="$TEST_RUN/danube_broker.yml" \
  -n danube
```

### Step 9: Install Danube Core

```bash
helm install danube-core danube/danube-core -n danube \
  --set broker.externalAccess.connectUrl="${NODE_IP}:${PROXY_PORT}"
```

Wait for all pods to be ready:
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=danube-core -n danube --timeout=300s
```

Monitor pod startup:
```bash
kubectl get pods -n danube -w
```

**Expected**:
```
NAME                                      READY   STATUS    AGE
danube-core-broker-0                      1/1     Running   2m
danube-core-broker-1                      1/1     Running   2m
danube-core-broker-2                      1/1     Running   2m
danube-core-prometheus-xxxxxxxxx          1/1     Running   3m
danube-envoy-xxxxxxxxx                    1/1     Running   5m
```

### Step 10: Verify Deployment

```bash
# Check broker registration
kubectl logs danube-core-broker-0 -n danube | grep "broker registered"

# Port-forward admin API for cluster status
kubectl port-forward danube-core-broker-0 50051:50051 -n danube &
PF_PID=$!
sleep 2

# Check cluster status
danube-admin cluster status
danube-admin brokers list

kill $PF_PID
```

### Step 11: Verify Cluster Health

```bash
# Port-forward admin API (if not already running)
kubectl port-forward danube-core-broker-0 50051:50051 -n danube &
PF_PID=$!
sleep 2

# Raft cluster state
danube-admin cluster status

# List all brokers and their status
danube-admin brokers list

# Identify the cluster leader
danube-admin brokers leader

# Check load distribution
danube-admin brokers balance

kill $PF_PID
```

**Expected**: All brokers show status `active`, a leader is elected, and load is balanced.

### Step 12: Check Pod Logs

```bash
# Check each broker's logs
for i in 0 1 2; do
  echo "=== Broker $i ==="
  kubectl logs danube-core-broker-$i -n danube --tail 30
done

# Check for errors across all brokers
for i in 0 1 2; do
  kubectl logs danube-core-broker-$i -n danube 2>&1 | grep -i "error\|panic\|fatal"
done
```

**Expected**: No errors or panics. Logs show successful Raft leader election and cluster formation.

## Inspecting the Cluster

### Admin Access (via port-forward)

```bash
kubectl port-forward danube-core-broker-0 50051:50051 -n danube &

# Cluster operations
danube-admin cluster status
danube-admin brokers list
danube-admin brokers balance
```

### Prometheus Access

```bash
kubectl port-forward svc/danube-core-prometheus 9090:9090 -n danube &
# Open http://localhost:9090 in browser
```

### Pod Logs

```bash
# Specific broker
kubectl logs danube-core-broker-0 -n danube --tail 50

# Follow logs
kubectl logs -f danube-core-broker-0 -n danube

# All brokers
for i in 0 1 2; do
  echo "=== Broker $i ==="
  kubectl logs danube-core-broker-$i -n danube --tail 10
done
```

## Verification

- [ ] All pods running: `kubectl get pods -n danube` shows 5 pods Running/Ready
- [ ] Envoy proxy has an address: NodePort or LoadBalancer IP
- [ ] `danube-admin cluster status` shows leader and voters (via port-forward)
- [ ] `danube-admin brokers list` shows all brokers as `active`
- [ ] `danube-admin brokers balance` shows balanced load
- [ ] Pod logs show no errors: `kubectl logs danube-core-broker-0 -n danube | grep -i error`
- [ ] Prometheus accessible via port-forward

## Cleanup

```bash
# Remove Helm releases
helm uninstall danube-core -n danube
helm uninstall danube-envoy -n danube

# Delete namespace (removes all resources including PVCs)
kubectl delete namespace danube

# Delete Kind cluster (if created for this test)
kind delete cluster --name danube-test

# Kill any port-forward processes
pkill -f "kubectl port-forward"

# Clean up test-run directory
# rm -rf "$TEST_RUN"
```

## Troubleshooting

- **Pods stuck in Pending**: Check if PersistentVolumeClaims are bound: `kubectl get pvc -n danube`. Kind clusters need a default StorageClass (usually provided automatically).

- **Pods in CrashLoopBackOff**: Check pod logs: `kubectl logs danube-core-broker-0 -n danube`. Common causes: invalid config, wrong connectUrl, image pull errors.

- **Envoy proxy not routing**: Verify the connectUrl matches the proxy service address. Check envoy logs: `kubectl logs -l app.kubernetes.io/name=danube-envoy -n danube`.

- **Can't connect from host**: For Kind, ensure port mappings are configured or use port-forward. For managed K8s, check security groups and firewall rules.

- **Helm chart not found**: Run `helm repo update` and verify: `helm search repo danube`.

- **Image pull errors**: Check if you can pull the image: `docker pull ghcr.io/danube-messaging/danube-broker:latest`. Ensure your cluster has access to GitHub Container Registry.
