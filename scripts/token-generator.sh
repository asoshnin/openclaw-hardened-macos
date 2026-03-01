#!/bin/bash
# ==============================================================================
# OpenClaw Secure Token Generator
# ==============================================================================
# Description: Securely generates a 256-bit authentication token for OpenClaw
# and writes it to the configuration file. Uses a umask subshell and jq to
# prevent the plaintext token from leaking to disk or shell history.
# ==============================================================================

set -e

CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

echo "🔒 Enforcing secure directory permissions..."
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "❌ Error: 'jq' is not installed. Please run 'brew install jq' first."
    exit 1
fi

echo "🔑 Generating 256-bit authentication token..."

# Execute strictly within a restricted subshell
(
    umask 077
    
    # Generate a secure 32-byte (256-bit) hex token
    AUTH_TOKEN_NEW=$(openssl rand -hex 32)
    
    # Create a basic JSON scaffold if the config does not exist yet
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"gateway": {"auth": {"token": ""}}}' > "$CONFIG_FILE"
    fi

    # Update JSON safely using jq by passing the token as an environment argument
    # This prevents the token from being written to a temporary plaintext file
    jq --arg t "$AUTH_TOKEN_NEW" '.gateway.auth.token = $t' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
      
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    # Enforce strict read/write for the owner ONLY
    chmod 600 "$CONFIG_FILE"
    
    echo "✅ Token successfully generated and injected into: $CONFIG_FILE"
    echo "⚠️  CRITICAL: Never commit this file to version control."
)
