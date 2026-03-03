#!/bin/bash
# ==============================================================================
# OpenClaw Secure Token Generator & Rotator (v5.0 - Remediated Edition)
# ==============================================================================
# Description: Generates or rotates a 256-bit token for OpenClaw. Stores the
# token exclusively in ~/.openclaw/.env (OPENCLAW_GATEWAY_TOKEN) per BASELINE
# §4 mandate — tokens MUST NOT be stored in plaintext in openclaw.json.
#
# Remediation: RED TEAM audit 2026-03-03 (FINDING-010, F-011, F-002, F-003)
# ==============================================================================

set -euo pipefail

CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
ENV_FILE="$CONFIG_DIR/.env"

if ! command -v jq &> /dev/null; then
    echo "❌ Error: 'jq' is not installed. Please run 'brew install jq' first."
    exit 1
fi

echo "🔒 Enforcing secure directory permissions..."
mkdir -m 700 -p "$CONFIG_DIR"

echo "🔑 Generating 256-bit authentication token..."

(
    umask 077
    AUTH_TOKEN_NEW=$(openssl rand -hex 32)
    export AUTH_TOKEN_NEW

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "⚠️  No existing configuration found. Generating strict 2026.2.26 schema..."

        # Securely capture Gemini Key
        read -rs "GEMINI_KEY?Enter Google Gemini API Key: "
        echo ""

        # Store ALL secrets in .env — NOT in openclaw.json (BASELINE §4)
        printf "GEMINI_API_KEY=%s\nOPENCLAW_GATEWAY_TOKEN=%s\n" "$GEMINI_KEY" "$AUTH_TOKEN_NEW" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"

        # Generate full schema scaffold — token is env-var reference only
        cat <<'JSONEOF' > "$CONFIG_FILE"
{
  "gateway": {
    "host": "127.0.0.1",
    "port": 3000,
    "bind": "loopback",
    "auth": { "token": "${OPENCLAW_GATEWAY_TOKEN}" }
  },
  "discovery": {
    "mdns": { "mode": "off" }
  },
  "tools": {
    "profile": "minimal",
    "mode": "deny",
    "deny": ["browser", "shell", "fs.write", "system.run"]
  },
  "agents": {
    "defaults": {
      "model": { "primary": "google/gemini-3.1-pro-preview" },
      "memorySearch": {"enabled": false}
    }
  },
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "http://127.0.0.1:11434",
        "models": [
          {"name": "llama3:8b", "id": "llama3:8b"},
          {"name": "deepseek-coder-v2:lite", "id": "deepseek-coder-v2:lite"}
        ]
      },
      "google": {
        "baseUrl": "https://generativelanguage.googleapis.com/v1beta",
        "models": [
          {"name": "gemini-3.1-pro-preview", "id": "gemini-3.1-pro-preview"}
        ]
      }
    }
  }
}
JSONEOF
    else
        echo "🔄 Existing configuration detected. Rotating token safely..."
        # Token lives in .env — update it there (jq not needed for token rotation)
        if grep -q "OPENCLAW_GATEWAY_TOKEN=" "$ENV_FILE" 2>/dev/null; then
            sed -i '' "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=$AUTH_TOKEN_NEW/" "$ENV_FILE"
        else
            echo "OPENCLAW_GATEWAY_TOKEN=$AUTH_TOKEN_NEW" >> "$ENV_FILE"
        fi
        chmod 600 "$ENV_FILE"
    fi

    # Set correct permission: 600 (user read/write) per official docs
    chmod 600 "$CONFIG_FILE"

    echo ""
    echo "================================================================="
    echo "✅ SUCCESS: Token rotated and written to $ENV_FILE"
    echo "   Retrieve with: grep OPENCLAW_GATEWAY_TOKEN \"$ENV_FILE\""
    echo "================================================================="
    echo ""
    echo "⚠️  NOTE: Run 'openclaw daemon restart' to apply the new token."
)