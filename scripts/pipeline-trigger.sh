#!/usr/bin/env bash
#
# OpenClaw CI/CD Orchestrator (Phases 1 & 2)
# Polls for updates, orchestrates sandboxed agents, and dispatches Matrix ChatOps notifications.
#
set -euo pipefail

# --- Configuration Variables ---
STAGING_DIR="$HOME/.openclaw/staging"
ENV_FILE="$HOME/.openclaw/.env"
CERT_FILE="$STAGING_DIR/APPROVAL_CERTIFICATE.json"
REPO_URL="[https://github.com/asoshnin/openclaw-hardened-macos.git](https://github.com/asoshnin/openclaw-hardened-macos.git)"
STATE_FILE="$HOME/.openclaw/.latest_processed_release"

echo "🔄 Initializing Zero-Trust Update Pipeline..."

# 1. Fetch Latest OpenClaw Release
echo "📡 Polling OpenClaw GitHub repository..."
LATEST_RELEASE_DATA=$(curl -sL [https://api.github.com/repos/openclaw/openclaw/releases/latest](https://api.github.com/repos/openclaw/openclaw/releases/latest))
LATEST_VERSION=$(echo "$LATEST_RELEASE_DATA" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo "❌ Error: Could not fetch latest release data."
    exit 1
fi

# 2. Check State (Idempotency)
if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" == "$LATEST_VERSION" ]; then
    echo "✅ Version $LATEST_VERSION has already been processed. Exiting cleanly."
    exit 0
fi
echo "🚨 New OpenClaw release detected: $LATEST_VERSION"

# 3. Secure Staging Environment Initialization (TOCTOU Prevention)
echo "🔒 Creating secure staging environment..."
rm -rf "$STAGING_DIR"
mkdir -m 700 "$STAGING_DIR"
git clone -q "$REPO_URL" "$STAGING_DIR"

# Write release notes to staging for Agent 1 to read
echo "$LATEST_RELEASE_DATA" | grep '"body":' > "$STAGING_DIR/LATEST_RELEASE_NOTES.md"

# 4. Invoke Agent 1: The Architect
echo "🏗️ Invoking Architect Agent in isolated sandbox..."
# Note: Syntax assumes standard OpenClaw v2026.2.26 CLI multi-agent invocation structure
openclaw run --agent "architect" --workspace "$STAGING_DIR" --timeout 300

# 5. Invoke Agent 2: The Red Team
echo "🛡️ Invoking Red Team Agent in isolated sandbox..."
openclaw run --agent "red_team" --workspace "$STAGING_DIR" --timeout 300

# 6. Evaluate Red Team Audit Results
if [ ! -f "$CERT_FILE" ]; then
    echo "❌ SECURITY HALT: Red Team rejected the draft or failed to complete."
    # Optional: Dispatch failure to Matrix here
    rm -rf "$STAGING_DIR"
    exit 1
fi

echo "✅ Red Team Audit Passed. Extracting deployment hash..."
APPROVED_HASH=$(grep -o '"hash": *"[^"]*"' "$CERT_FILE" | cut -d'"' -f4)

# 7. Phase 2: Matrix Async Notification
# Ephemerally load the native Matrix credentials from the locked .env file
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: .env file missing."
    exit 1
fi

MATRIX_URL=$(grep '^MATRIX_HOMESERVER_URL=' "$ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]' || true)
MATRIX_TOKEN=$(grep '^MATRIX_ACCESS_TOKEN=' "$ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]' || true)
MATRIX_ROOM=$(grep '^MATRIX_ADMIN_ROOM_ID=' "$ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]' || true)

if [ -n "$MATRIX_URL" ] && [ -n "$MATRIX_TOKEN" ] && [ -n "$MATRIX_ROOM" ]; then
    echo "📱 Dispatching native Matrix ChatOps notification..."
    NOTIFICATION_BODY="🚨 SYSTEM UPDATE DRAFTED 🚨\nOpenClaw $LATEST_VERSION released. Red Team has approved the documentation updates.\nTo authorize, reply via Matrix: /deploy $APPROVED_HASH\nOr execute on Desktop: ./deploy-staged-update.sh $APPROVED_HASH"
    
    # Generate a unique transaction ID for the Matrix API
    TXN_ID=$(date +%s%N)
    
    curl -sX PUT "${MATRIX_URL}/_matrix/client/v3/rooms/${MATRIX_ROOM}/send/m.room.message/${TXN_ID}" \
         -H "Authorization: Bearer ${MATRIX_TOKEN}" \
         -H "Content-Type: application/json" \
         -d "{\"msgtype\": \"m.text\", \"body\": \"$NOTIFICATION_BODY\"}" > /dev/null
    
    # Flush secrets from memory
    unset MATRIX_URL MATRIX_TOKEN MATRIX_ROOM
else
    echo "⚠️ Warning: Matrix credentials (URL, TOKEN, or ROOM_ID) missing in .env. Skipping mobile notification."
fi

# 8. Finalize State
echo "$LATEST_VERSION" > "$STATE_FILE"
echo "⏸️ Pipeline paused. Awaiting human deployment authorization (Phase 3)."
exit 0