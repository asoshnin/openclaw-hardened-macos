#!/bin/bash
# ==============================================================================
# OpenClaw Secure Token Generator & Rotator (v4.0 - Zero-Trust Edition)
# ==============================================================================
# Description: Generates or rotates a 256-bit token for OpenClaw. If the config
# is missing, it scaffolds a strict 2026.2.26 schema. Complies with the
# "Unlock-Modify-Lock" Zero-Trust lifecycle.
# ==============================================================================

set -e

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
        echo "GEMINI_API_KEY=$GEMINI_KEY" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"

        # Generate full schema scaffold
        cat <<EOF > "$CONFIG_FILE"
{
  "gateway": {
    "host": "127.0.0.1",
    "port": 3000,
    "mode": "local",
    "auth": { "token": "$AUTH_TOKEN_NEW" }
  },
  "tools": {
    "profile": "minimal",
    "mode": "deny",
    "deny": ["browser", "shell", "fs.write", "system.run"]
  },
  "agents": {
    "defaults": {
      "model": "google/gemini-3.1-pro-preview",
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
EOF
    else
        echo "🔄 Existing configuration detected. Rotating token safely..."
        # 1. Unlock
        chmod 600 "$CONFIG_FILE"
        # 2. Modify (jq reads directly from the protected memory space)
        jq '.gateway.auth.token = env.AUTH_TOKEN_NEW' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        mv -f "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi

    # 3. Re-Lock (Configuration Immutability)
    chmod 400 "$CONFIG_FILE"
    
    echo -e "\n================================================================="
    echo "✅ SUCCESS: Configuration locked (400) & Token Rotated."
    echo "🔑 YOUR NEW UI ACCESS TOKEN IS: $AUTH_TOKEN_NEW"
    echo "=================================================================\n"
    
    echo "⚠️  NOTE: Run 'openclaw daemon restart' to apply the new token."
)