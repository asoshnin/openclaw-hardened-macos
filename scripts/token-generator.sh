#!/bin/bash
# ==============================================================================
# OpenClaw Secure Token Generator
# ==============================================================================
# Description: Securely generates a 256-bit authentication token for OpenClaw
# and writes it to the configuration file. Uses atomic directory creation and 
# a umask subshell to prevent the plaintext token from leaking.
# ==============================================================================

set -e

CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "❌ Error: 'jq' is not installed. Please run 'brew install jq' first."
    exit 1
fi

echo "🔒 Enforcing secure directory permissions..."
# RED TEAM FIX: Atomic creation with 700 permissions to prevent TOCTOU race condition
mkdir -m 700 -p "$CONFIG_DIR"

echo "🔑 Generating 256-bit authentication token..."

# Execute strictly within a restricted subshell
(
    # Ensure any files created in this subshell are strictly 600
    umask 077
    
    # Generate a secure 32-byte (256-bit) hex token
    AUTH_TOKEN_NEW=$(openssl rand -hex 32)
    
    # Create a basic JSON scaffold if the config does not exist yet
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"gateway": {"auth": {"token": ""}}}' > "$CONFIG_FILE"
    fi

    # Update JSON safely using jq by passing the token as an environment argument
    jq --arg t "$AUTH_TOKEN_NEW" '.gateway.auth.token = $t' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
      
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    echo "✅ Token successfully generated and injected into: $CONFIG_FILE"
    echo "⚠️  CRITICAL: Never commit this file to version control."
)
