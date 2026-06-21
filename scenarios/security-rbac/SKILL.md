---
name: security-rbac
description: "End-to-end security setup — TLS certificates, broker auth configuration, JWT token management, RBAC roles and bindings, and verification that unauthorized access is rejected with PermissionDenied."
---

# Scenario: Security & RBAC

## Objective

Test the complete Danube security setup — from TLS certificate generation and broker configuration to JWT token creation, RBAC role/binding management, and verification that unauthorized operations are properly rejected.

## When to Use

- User wants to test "security", "TLS", "authentication", "RBAC", "roles", "permissions"
- User wants to set up a secure Danube cluster
- User wants to verify token-based authentication works
- User wants to test authorization enforcement (PermissionDenied)

## Compatible Infrastructure

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | ✅ | — | Simplest for testing security features |
| Local Source | ✅ | — | Same |

Security tests work best on **standalone** — a single broker is sufficient to validate TLS, tokens, roles, and bindings. The security model is the same across standalone and cluster.

## AI Decision Flow

### 1. Which security aspect to test?

| User says | Test Flow |
|-----------|-----------|
| "tls", "certificates", "encryption" | **TLS Setup** — generate certs, configure broker, verify TLS connectivity |
| "token", "jwt", "authentication" | **Token Management** — create admin token, service account tokens, validate tokens |
| "rbac", "roles", "permissions", "bindings" | **RBAC Enforcement** — create roles, bind to principals, verify authorized/unauthorized access |
| "permission denied", "unauthorized", "block" | **Access Denial** — verify unauthorized operations fail with PermissionDenied |
| *(unclear)* | Default: **RBAC Enforcement** |

### 2. Tool or Client Language?

| User says | Choice |
|-----------|--------|
| "python", "rust", "go", "java" | **Client library** — needed to test authenticated produce/consume |
| *(unclear)* | Default: **Python** |

**Note:** Token and role management uses `danube-admin` CLI. Client libraries are needed to test authenticated produce/consume and PermissionDenied errors.

## Predefined Scripts

This scenario ships with helper scripts in `scenarios/security-rbac/scripts/`:

- **`setup_security.sh`** — Generates TLS certificates, creates secure broker config, creates the bootstrap admin token, saves credentials. Usage:
  ```bash
  ./scenarios/security-rbac/scripts/setup_security.sh <BROKER_BINARY> <CONFIG_DIR> <CERT_DIR>
  # Example:
  ./scenarios/security-rbac/scripts/setup_security.sh ./bin/v0.15.0/danube-broker $TEST_RUN $TEST_RUN/cert
  # After running, source credentials:
  source $TEST_RUN/security_credentials.env
  ```

- **`create_rbac.sh`** — Creates standard roles (producer/consumer/operator), service account tokens, and namespace bindings. Usage:
  ```bash
  ./scenarios/security-rbac/scripts/create_rbac.sh <SECRET_KEY> [ADMIN_ENDPOINT]
  # Example:
  ./scenarios/security-rbac/scripts/create_rbac.sh "$DANUBE_SECRET_KEY" http://127.0.0.1:50051
  ```

## Execution Steps

### Step 1: Generate Certificates and Configure Broker

**Use the predefined script** (recommended):
```bash
./scenarios/security-rbac/scripts/setup_security.sh \
  ./bin/v0.15.0/danube-broker $TEST_RUN $TEST_RUN/cert
source $TEST_RUN/security_credentials.env
```

This script:
1. Generates TLS certificates (CA, server, client) in `$TEST_RUN/cert/`
2. Creates `$TEST_RUN/danube_broker_secure.yml` with TLS + JWT auth
3. Creates the bootstrap admin token
4. Saves credentials to `$TEST_RUN/security_credentials.env` (exports `DANUBE_SECRET_KEY`, `DANUBE_ADMIN_TOKEN`, `DANUBE_CA_CERT`)

Or manually — generate certificates and configure the broker:

```bash
# From the Danube repo (https://github.com/danube-messaging/danube)
cd cert/
bash gen_certs.sh
```

This produces:
```text
cert/
  ca-cert.pem        # Certificate Authority
  ca-key.pem
  server-cert.pem    # Broker identity
  server-key.pem
  client-cert.pem    # Client mTLS identity (optional)
  client-key.pem
```

### Step 2: Configure Broker with Auth (if manual)

Create a secure broker config by modifying `$TEST_RUN/danube_broker.yml`:

```yaml
auth:
  mode: tls
  tls:
    cert_file: "./cert/server-cert.pem"
    key_file: "./cert/server-key.pem"
    ca_file: "./cert/ca-cert.pem"
  jwt:
    secret_key: "test-secret-key-for-e2e"
    issuer: "danube-auth"
    expiration_time: 3600
  super_admins:
    - "admin"
```

Start the broker with the secure config.

### Step 3a: TLS Setup (if selected)

1. Generate certificates (Step 1)
2. Configure broker with auth (Step 2)
3. Start broker with secure config
4. Verify TLS connectivity:
```bash
# Create admin token (offline operation, no broker needed)
export ADMIN_TOKEN=$(danube-admin security tokens create \
  --subject admin --secret-key test-secret-key-for-e2e)

# Verify broker responds with the token
DANUBE_ADMIN_TOKEN=$ADMIN_TOKEN danube-admin brokers list
```

### Step 3b: Token Management (if selected)

```bash
# 1. Create super-admin token
export ADMIN_TOKEN=$(danube-admin security tokens create \
  --subject admin --secret-key test-secret-key-for-e2e)

# 2. Create service account tokens
export PRODUCER_TOKEN=$(danube-admin security tokens create \
  --subject payments-producer --secret-key test-secret-key-for-e2e)

export CONSUMER_TOKEN=$(danube-admin security tokens create \
  --subject analytics-consumer --secret-key test-secret-key-for-e2e)

# 3. Validate a token
danube-admin security tokens validate \
  --token $PRODUCER_TOKEN --secret-key test-secret-key-for-e2e
```

### Step 3c: RBAC Enforcement (if selected)

**Use the predefined script** (recommended) — creates roles, tokens, and bindings in one shot:
```bash
./scenarios/security-rbac/scripts/create_rbac.sh "$DANUBE_SECRET_KEY"
```

The script creates:
- **Roles:** `producer` (Produce+Lookup), `consumer` (Consume+Lookup), `operator` (ManageNamespace+ManageTopic+ManageSchema+Lookup)
- **Tokens:** `payments-producer`, `analytics-consumer`, `unauthorized-user`
- **Bindings:** `payments-producer` → producer role on `/default`, `analytics-consumer` → consumer role on `/default`
- `unauthorized-user` has NO binding — used to test PermissionDenied

Or manually:

1. Create tokens (Step 3b)
2. Create roles:
```bash
# Producer role: discover topics and publish
danube-admin security roles create producer \
  --permissions Produce,Lookup

# Consumer role: discover topics and receive
danube-admin security roles create consumer \
  --permissions Consume,Lookup

# Operator role: manage namespaces, topics, schemas
danube-admin security roles create operator \
  --permissions ManageNamespace,ManageTopic,ManageSchema,Lookup
```

3. Create bindings:
```bash
# Bind producer token to a namespace
danube-admin security bindings create bind-payments-producer \
  --principal-type service_account \
  --principal-name payments-producer \
  --roles producer \
  --scope namespace \
  --resource /default

# Bind consumer token to a namespace
danube-admin security bindings create bind-analytics-consumer \
  --principal-type service_account \
  --principal-name analytics-consumer \
  --roles consumer \
  --scope namespace \
  --resource /default
```

4. Test with a client library — generate a script that:
   - Connects with `PRODUCER_TOKEN`, produces to `/default/security-test` → **should succeed**
   - Connects with `CONSUMER_TOKEN`, consumes from `/default/security-test` → **should succeed**
   - Connects with `CONSUMER_TOKEN`, tries to produce → **should fail with PermissionDenied**
   - Connects with `PRODUCER_TOKEN`, tries to consume → **should fail with PermissionDenied**

### Step 3d: Access Denial (if selected)

Focused test on PermissionDenied:

1. Create a token with NO roles bound
2. Attempt to produce → PermissionDenied
3. Attempt to consume → PermissionDenied
4. Create a role bound at namespace `/payments`
5. Attempt to produce to `/default/test` → PermissionDenied (wrong namespace)
6. Attempt to produce to `/payments/test` → should succeed

**Permission reference:**

| Permission | Allows |
|-----------|--------|
| `Lookup` | Topic discovery |
| `Produce` | Publish messages |
| `Consume` | Subscribe and receive |
| `ManageNamespace` | Create/delete namespaces |
| `ManageTopic` | Create/delete topics |
| `ManageSchema` | Register/delete schemas |
| `ManageBroker` | Broker operations |
| `ManageCluster` | Cluster membership changes |

## Verification

| Test | Pass Criteria |
|------|--------------|
| **TLS Setup** | Broker starts with auth config, admin commands work with token |
| **Token Management** | Tokens created, validated, service accounts functional |
| **RBAC Enforcement** | Authorized operations succeed, unauthorized operations fail with PermissionDenied |
| **Access Denial** | Wrong namespace → denied, no role → denied, correct scope → allowed |

```bash
# Key verification commands
danube-admin security roles list
danube-admin security roles get producer --output json
danube-admin security bindings list --scope namespace --resource /default --output json
danube-admin security tokens validate --token $TOKEN --secret-key <key>
```

## Cleanup

This scenario cleans up roles, bindings, and topics. See `setups/SKILL.md` → **Cleanup** for broker teardown.

```bash
danube-admin security bindings delete bind-payments-producer --scope namespace --resource /default
danube-admin security bindings delete bind-analytics-consumer --scope namespace --resource /default
danube-admin security roles delete producer
danube-admin security roles delete consumer
danube-admin security roles delete operator
danube-admin topics delete /default/security-test
```
