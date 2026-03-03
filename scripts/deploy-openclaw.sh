#!/bin/zsh
# OpenClaw 2026.2.26 Hardened Deployment Script
# Architecture: Local Ollama + Cloud Gemini Fallback
# Remediated: RED TEAM audit 2026-03-03
set -euo pipefail

echo "🦞 Starting Zero-Trust OpenClaw Deployment..."

# 1. Require Gemini Key Upfront (No History Leak)
read -rs "GEMINI_KEY?Enter Google Gemini API Key: "
echo "\n"

# 2. Setup Ollama LaunchAgent (Loopback Only)
echo "🔒 Securing Ollama binding..."
mkdir -p ~/Library/Logs/Ollama

# Resolve actual home directory for plist (launchd does not expand $HOME in XML)
REAL_HOME=$(eval echo ~)

tee ~/Library/LaunchAgents/com.ollama.serve.plist > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama.serve</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>127.0.0.1:11434</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${REAL_HOME}/Library/Logs/Ollama/ollama.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${REAL_HOME}/Library/Logs/Ollama/ollama.stderr.log</string>
</dict>
</plist>
EOF

launchctl bootout gui/$(id -u)/com.ollama.serve 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ollama.serve.plist
sleep 3

# 3. Pull Models
echo "🧠 Pulling local models (this may take a while)..."
/opt/homebrew/bin/ollama pull llama3:8b
/opt/homebrew/bin/ollama pull deepseek-coder-v2:lite

# 4. Generate Hardened OpenClaw Config
echo "⚙️ Writing OpenClaw configuration..."
(
umask 077
mkdir -p ~/.openclaw
AUTH_TOKEN=$(openssl rand -hex 32)

# Store token in .env — NOT in openclaw.json (per BASELINE §4 mandate)
echo "GEMINI_API_KEY=$GEMINI_KEY" > ~/.openclaw/.env
echo "OPENCLAW_GATEWAY_TOKEN=$AUTH_TOKEN" >> ~/.openclaw/.env
chmod 600 ~/.openclaw/.env

python3 -c "
import json, os
config = {
  'gateway': {
    'host': '127.0.0.1',
    'port': 3000,  # Intentional non-default (official default: 18789). Must match pf rules.
    'bind': 'loopback',
    'auth': { 'token': '\${OPENCLAW_GATEWAY_TOKEN}' }  # Resolved from .env at runtime
  },
  'discovery': {
    'mdns': { 'mode': 'off' }  # Disable mDNS/Bonjour network discovery (Zero-Trust)
  },
  'tools': {
    'profile': 'minimal',
    'mode': 'deny',
    'deny': ['browser', 'shell', 'fs.write', 'system.run']
  },
  'agents': {
    'defaults': {
      'model': { 'primary': 'google/gemini-3.1-pro-preview' },
      'memorySearch': {'enabled': False}
    }
  },
  'models': {
    'providers': {
      'ollama': {
        'baseUrl': 'http://127.0.0.1:11434',
        'models': [
          {'name': 'llama3:8b', 'id': 'llama3:8b'},
          {'name': 'deepseek-coder-v2:lite', 'id': 'deepseek-coder-v2:lite'}
        ]
      },
      'google': {
        'baseUrl': 'https://generativelanguage.googleapis.com/v1beta',
        'models': [
          {'name': 'gemini-3.1-pro-preview', 'id': 'gemini-3.1-pro-preview'}
        ]
      }
    }
  }
}
path = os.path.expanduser('~/.openclaw/openclaw.json')
with open(path, 'w') as f:
  json.dump(config, f, indent=2)
"

# Set correct permission: 600 (user read/write) per official docs
chmod 600 ~/.openclaw/openclaw.json

# Token is stored in .env — retrieve it there, do NOT print to stdout
echo ""
echo "✅ Token written to ~/.openclaw/.env"
echo "   Retrieve with: grep OPENCLAW_GATEWAY_TOKEN ~/.openclaw/.env"
echo ""
)

# 5. Start OpenClaw
echo "🚀 Starting OpenClaw daemon..."
openclaw gateway install
openclaw daemon start
sleep 3

# 6. Apply pf Firewall Shield
echo "🛡️ Applying pf Firewall Anchor (requires sudo)..."
sudo tee /etc/pf.anchors/openclaw-ollama > /dev/null <<'EOF'
# OpenClaw Zero-Trust pf anchor
# Port 3000: intentional non-default (official default: 18789). If you change gateway.port, update these rules.
pass in quick on lo0 proto tcp from 127.0.0.1 to 127.0.0.1 port { 3000, 11434 }
pass in quick on lo0 proto tcp from ::1 to ::1 port { 3000, 11434 }
block in quick proto tcp from any to any port { 3000, 11434 }
EOF

if ! grep -q 'anchor "openclaw-ollama"' /etc/pf.conf; then
    echo 'anchor "openclaw-ollama"' | sudo tee -a /etc/pf.conf > /dev/null
    echo 'load anchor "openclaw-ollama" from "/etc/pf.anchors/openclaw-ollama"' | sudo tee -a /etc/pf.conf > /dev/null
fi

# Validate pf syntax BEFORE loading (F-014: prevent silent firewall disable on malformed conf)
if sudo pfctl -vnf /etc/pf.conf 2>&1 | grep -q "syntax error"; then
    echo "❌ CRITICAL: pf.conf syntax error detected. Aborting to prevent firewall disruption."
    exit 1
fi

sudo pfctl -f /etc/pf.conf
sudo pfctl -e 2>/dev/null || true

echo "✅ Deployment Complete."
echo "Navigate to http://127.0.0.1:3000 and enter your token (see ~/.openclaw/.env)."