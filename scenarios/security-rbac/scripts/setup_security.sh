#!/usr/bin/env bash
# =============================================================================
# Security Setup — Generate certs, configure broker with auth, create admin token
#
# Usage:
#   ./scripts/setup_security.sh <BROKER_BINARY> <CONFIG_DIR> <CERT_DIR>
#
# Example:
#   ./scripts/setup_security.sh ./bin/v0.15.0/danube-broker $TEST_RUN $TEST_RUN/cert
#
# This script:
#   1. Generates TLS certificates (CA, server, client)
#   2. Creates a secure broker config with TLS + JWT auth
#   3. Creates the bootstrap super-admin token
#   4. Outputs the ADMIN_TOKEN for use in subsequent commands
# =============================================================================
set -euo pipefail

BROKER_BIN="${1:?Usage: setup_security.sh <BROKER_BINARY> <CONFIG_DIR> <CERT_DIR>}"
CONFIG_DIR="${2:?Usage: setup_security.sh <BROKER_BINARY> <CONFIG_DIR> <CERT_DIR>}"
CERT_DIR="${3:?Usage: setup_security.sh <BROKER_BINARY> <CONFIG_DIR> <CERT_DIR>}"

ADMIN_BIN="$(dirname "$BROKER_BIN")/danube-admin"
SECRET_KEY="test-secret-key-$(date +%s)"

echo "=== Security Setup ==="
echo "  Config dir: $CONFIG_DIR"
echo "  Cert dir:   $CERT_DIR"

# Step 1: Generate certificates
echo ""
echo "[1/4] Generating TLS certificates..."
mkdir -p "$CERT_DIR"

# Generate CA
openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/ca-key.pem" \
  -out "$CERT_DIR/ca-cert.pem" -days 365 -nodes \
  -subj "/CN=Danube Test CA" 2>/dev/null

# Generate server cert signed by CA
openssl req -newkey rsa:2048 -keyout "$CERT_DIR/server-key.pem" \
  -out "$CERT_DIR/server-csr.pem" -nodes \
  -subj "/CN=localhost" 2>/dev/null

cat > "$CERT_DIR/server-ext.cnf" <<EOF
subjectAltName=DNS:localhost,IP:127.0.0.1
EOF

openssl x509 -req -in "$CERT_DIR/server-csr.pem" \
  -CA "$CERT_DIR/ca-cert.pem" -CAkey "$CERT_DIR/ca-key.pem" \
  -CAcreateserial -out "$CERT_DIR/server-cert.pem" -days 365 \
  -extfile "$CERT_DIR/server-ext.cnf" 2>/dev/null

# Generate client cert signed by CA
openssl req -newkey rsa:2048 -keyout "$CERT_DIR/client-key.pem" \
  -out "$CERT_DIR/client-csr.pem" -nodes \
  -subj "/CN=test-client" 2>/dev/null

openssl x509 -req -in "$CERT_DIR/client-csr.pem" \
  -CA "$CERT_DIR/ca-cert.pem" -CAkey "$CERT_DIR/ca-key.pem" \
  -CAcreateserial -out "$CERT_DIR/client-cert.pem" -days 365 2>/dev/null

# Cleanup CSR files
rm -f "$CERT_DIR"/*.csr.pem "$CERT_DIR"/*.cnf "$CERT_DIR"/*.srl

echo "  ✅ Generated: ca-cert.pem, server-cert.pem, server-key.pem, client-cert.pem, client-key.pem"

# Step 2: Create secure broker config
echo ""
echo "[2/4] Creating secure broker config..."
cat > "$CONFIG_DIR/danube_broker_secure.yml" <<EOF
auth:
  mode: tls
  tls:
    cert_file: "${CERT_DIR}/server-cert.pem"
    key_file: "${CERT_DIR}/server-key.pem"
    ca_file: "${CERT_DIR}/ca-cert.pem"
  jwt:
    secret_key: "${SECRET_KEY}"
    issuer: "danube-auth"
    expiration_time: 3600
  super_admins:
    - "admin"
EOF

echo "  ✅ Config written to: $CONFIG_DIR/danube_broker_secure.yml"

# Step 3: Create bootstrap admin token
echo ""
echo "[3/4] Creating super-admin token..."
ADMIN_TOKEN=$("$ADMIN_BIN" security tokens create \
  --subject admin --secret-key "$SECRET_KEY")
echo "  ✅ Admin token created."

# Step 4: Save token and secret for later use
echo ""
echo "[4/4] Saving credentials..."
cat > "$CONFIG_DIR/security_credentials.env" <<EOF
# Security credentials — source this file to use
export DANUBE_SECRET_KEY="${SECRET_KEY}"
export DANUBE_ADMIN_TOKEN="${ADMIN_TOKEN}"
export DANUBE_CA_CERT="${CERT_DIR}/ca-cert.pem"
EOF

echo "  ✅ Credentials saved to: $CONFIG_DIR/security_credentials.env"

echo ""
echo "========================================="
echo "  Security setup complete"
echo "========================================="
echo ""
echo "  Secret key:  $SECRET_KEY"
echo "  Admin token: ${ADMIN_TOKEN:0:40}..."
echo ""
echo "  To use:"
echo "    source $CONFIG_DIR/security_credentials.env"
echo "    danube-broker --config-file $CONFIG_DIR/danube_broker_secure.yml"
echo ""
