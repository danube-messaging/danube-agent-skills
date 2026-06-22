---
name: schema-lifecycle
description: "Test Danube's schema registry: registration, validation, compatibility modes, version selection, and schema evolution across producers and consumers."
---

# Scenario: Schema Lifecycle

## Objective

Test the full schema lifecycle in Danube — from registration through validation, compatibility enforcement, version selection, and multi-version evolution. Verifies that the schema registry correctly enforces data contracts.

## When to Use

- User wants to test "schema", "schema registry", "validation", "compatibility"
- User wants to verify schema evolution (adding/removing fields)
- User wants to test compatibility modes (backward, forward, full, none)
- User wants to test producer version pinning or minimum version selection
- User wants to verify schema enforcement end-to-end (producer → broker → consumer)

## Compatible Infrastructure

| Setup Method | Standalone | Cluster | Notes |
|-------------|:----------:|:-------:|-------|
| Local Binary | ✅ | ✅ | `danube-cli` schema commands + `danube-admin` needed |
| Local Source | ✅ | ✅ | Same |
| Docker Compose | ✅ | ✅ | Use exposed ports |
| Kubernetes | — | ✅ | Use port-forwarded addresses |

All tests work on standalone. Schema registry is broker-local, no cluster needed.

## AI Decision Flow

### 1. Which schema aspect to test?

Present these options to the user **exactly as listed**:

1. **Registration & Validation**: Register a JSON/Avro schema, create a topic, produce with the schema subject, and verify messages carry schema metadata. Tests that schema registration, lookup, and producer-side schema attachment work correctly.

2. **Compatibility Modes**: Test schema evolution under backward, forward, full, or none compatibility. Register multiple schema versions, verify compatible changes succeed and incompatible changes are rejected by the registry.

3. **Version Selection**: Pin producers to specific schema versions or set a minimum version. Verify each producer uses the correct version and that invalid version requests fail. Requires a client library.

4. **Topic Schema Config**: Verify that the first producer on a topic locks its schema subject. A second producer with a different schema subject is rejected, while producers without a schema or with the same subject succeed.

Each aspect maps to the corresponding `Step 2x` in Execution Steps below.

### 2. Schema type?

| User says | Type |
|-----------|------|
| "json", "json schema" | **JSON Schema** (default) |
| "avro" | **Avro Schema** |
| "string", "text" | **String Schema** |
| "bytes", "binary" | **Bytes Schema** |
| *(unclear)* | Default: **JSON Schema** |

### 3. Tool or Client Language?

| User says | Choice |
|-----------|--------|
| "cli", "command line" | **danube-cli** — works for registration, schema commands, and basic produce/consume |
| "python", "rust", "go", "java" | **Client library** — needed for version pinning and programmatic schema access |
| *(unclear)* | Default: **danube-cli** for registration/compatibility, **Python** for version selection |

## Execution Steps

### Step 1: Register a Schema

#### Using danube-cli

```bash
# Register JSON Schema v1
danube-cli schema register user-events \
  --schema-type json_schema \
  --schema '{"type":"object","properties":{"user_id":{"type":"string"},"event":{"type":"string"},"timestamp":{"type":"integer"}},"required":["user_id","event","timestamp"]}'

# Register Avro Schema v1
danube-cli schema register user-events-avro \
  --schema-type avro \
  --schema '{"type":"record","name":"UserEvent","fields":[{"name":"user_id","type":"string"},{"name":"event","type":"string"},{"name":"timestamp","type":"long"}]}'

# Verify registration
danube-cli schema get user-events
danube-cli schema versions user-events
```

### Step 2a: Registration + Validation (if selected)

1. Register a JSON schema
2. Create topic with the schema subject
3. Producer with matching schema subject sends valid payload → succeeds
4. Producer without schema subject → succeeds (schema is optional per-producer)
5. Producer with different schema subject → fails (topic locked to first schema)

```bash
# Create topic
danube-admin topics create /default/schema-test

# Produce with schema (valid)
danube-cli produce -s http://localhost:6650 -t /default/schema-test \
  --schema-subject user-events \
  -m '{"user_id":"u1","event":"login","timestamp":1234567890}'

# Produce without schema (also works)
danube-cli produce -s http://localhost:6650 -t /default/schema-test \
  -m "plain text message"
```

#### Validation with client library

Generate a script that:
1. Creates a producer with `.with_schema_subject("user-events")`
2. Sends a valid JSON payload → prints message ID (success)
3. Sends multiple valid payloads
4. Consumer receives messages, checks `schema_id` in message metadata

### Step 2b: Compatibility Modes (if selected)

Test schema evolution under different compatibility modes. Ask the user which mode:

| Mode | Rule |
|------|------|
| **BACKWARD** | New schema can read old data (add optional fields OK, remove required fails) |
| **FORWARD** | Old schema can read new data (remove optional fields OK, add required fails) |
| **FULL** | Both backward and forward (strictest) |
| **NONE** | Any change allowed (for rapid iteration) |

#### Backward Compatibility Flow

```bash
# 1. Register v1
danube-cli schema register compat-test \
  --schema-type json_schema \
  --schema '{"type":"object","properties":{"user_id":{"type":"string"},"event":{"type":"string"}},"required":["user_id","event"]}'

# 2. Set compatibility mode
danube-cli schema set-compatibility compat-test --mode backward

# 3. Evolve: add optional field (should succeed)
danube-cli schema register compat-test \
  --schema-type json_schema \
  --schema '{"type":"object","properties":{"user_id":{"type":"string"},"event":{"type":"string"},"metadata":{"type":"string"}},"required":["user_id","event"]}'

# 4. Check: remove required field (should fail)
danube-cli schema check-compatibility compat-test \
  --schema-type json_schema \
  --schema '{"type":"object","properties":{"user_id":{"type":"string"}},"required":["user_id"]}'

# 5. Multi-version evolution — register v3 (add another optional field)
danube-cli schema register compat-test \
  --schema-type json_schema \
  --schema '{"type":"object","properties":{"user_id":{"type":"string"},"event":{"type":"string"},"metadata":{"type":"string"},"phone":{"type":"string"}},"required":["user_id","event"]}'

# 6. Verify all versions
danube-cli schema versions compat-test
```

#### Forward Compatibility Flow

```bash
# Set forward mode
danube-cli schema set-compatibility forward-test --mode forward

# Remove optional field (should succeed)
# Add required field (should fail)
```

#### Full Compatibility Flow

```bash
# Set full mode — only non-breaking changes in both directions
danube-cli schema set-compatibility full-test --mode full
```

#### None Mode Flow

```bash
# Set none mode — allows any change
danube-cli schema set-compatibility none-test --mode none
# Register completely different schema (succeeds)
```

### Step 2c: Version Selection (if selected)

Requires client library. Tests producer version pinning:

1. Register v1 and v2 of a schema
2. Producer A: pin to v1 (`.with_schema_version("subject", 1)`)
3. Producer B: pin to v2 (`.with_schema_version("subject", 2)`)
4. Producer C: minimum v2 (`.with_schema_min_version("subject", 2)`)
5. Producer D: pin to invalid version → fails
6. Verify: each producer uses the correct schema version

### Step 2d: Topic Schema Config (if selected)

Tests that the first producer on a topic locks the schema:

1. Create topic (no schema pre-set)
2. Producer A connects with schema subject "schema-A" → succeeds, topic adopts schema-A
3. Producer B connects with schema subject "schema-B" → fails (topic locked to schema-A)
4. Producer C connects without any schema → succeeds (no schema enforcement for plain producers)
5. Producer D connects with schema subject "schema-A" but different version → succeeds (same subject OK)

## Verification

| Test | Pass Criteria |
|------|--------------|
| **Registration & Validation** | Schema registered, versions listed, producer/consumer work with schema |
| **Backward Compat** | Add optional field succeeds, remove required field fails, multi-version evolution works |
| **Forward Compat** | Remove optional field succeeds, add required field fails |
| **Full Compat** | Only non-breaking changes in both directions |
| **None Mode** | Any schema change accepted |
| **Version Selection** | Producer uses exact version specified, min version resolves correctly, invalid version rejected |
| **Topic Schema Config** | Second producer with different subject rejected, same subject or no subject succeeds |

```bash
# Inspect schema
danube-cli schema get user-events
danube-cli schema versions user-events

# Check compatibility before committing
danube-cli schema check-compatibility user-events \
  --schema-type json_schema \
  --schema '<new_schema_json>'
```

## Cleanup

This scenario only cleans up topics and schemas it created. See `setups/SKILL.md` → **Cleanup** for cluster teardown.

```bash
danube-admin topics delete /default/schema-test
# Schemas persist in the registry — no CLI command to delete them currently
```
