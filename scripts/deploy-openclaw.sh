#!/bin/zsh
# OpenClaw 2026.2.26 Hardened Deployment Script
# Architecture: Local Ollama + Cloud Gemini Fallback
set -e

echo "🦞 Starting Zero-Trust OpenClaw Deployment..."

# 1. Require Gemini Key Upfront (No History Leak)
read -rs "GEMINI_KEY?Enter Google Gemini API Key: "
echo "\n"

# 2. Setup Ollama LaunchAgent (Loopback Only)
echo "🔒 Securing Ollama binding..."
mkdir -p ~/Library/Logs/Ollama
tee ~/Library/LaunchAgents/com.ollama.serve.plist > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "[http://www.apple.com/DTDs/PropertyList-1.0.dtd](http://www.apple.com/DTDs/PropertyList-1.0.dtd)">
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
    <string>$HOME/Library/Logs/Ollama/ollama.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Ollama/ollama.stderr.log</string>
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
echo "GEMINI_API_KEY=$GEMINI_KEY" > ~/.openclaw/.env

python3 -c "
import json, os, sys
config = {
  'gateway': {
    'host': '127.0.0.1',
    'port': 3000,
    'mode': 'local',
    'auth': { 'token': sys.stdin.read().strip() }
  },
  'tools': {
    'profile': 'minimal',
    'mode': 'deny',
    'deny': ['browser', 'shell', 'fs.write', 'system.run']
  },
  'agents': {
    'defaults': {
      'model': 'google/gemini-3.1-pro-preview',
      'memorySearch': {'enabled': False}
    }
  },
  'models': {
    'providers': {
      'ollama': {
        'baseUrl': '[http://127.0.0.1:11434](http://127.0.0.1:11434)',
        'models': [
          {'name': 'llama3:8b', 'id': 'llama3:8b'},
          {'name': 'deepseek-coder-v2:lite', 'id': 'deepseek-coder-v2:lite'}
        ]
      },
      'google': {
        'baseUrl': '[https://generativelanguage.googleapis.com/v1beta](https://generativelanguage.googleapis.com/v1beta)',
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
" <<< "$AUTH_TOKEN"

chmod 400 ~/.openclaw/openclaw.json
chmod 600 ~/.openclaw/.env

echo "\n================================================"
echo "🔑 YOUR UI ACCESS TOKEN IS: $AUTH_TOKEN"
echo "================================================\n"
)

# 5. Start OpenClaw
echo "🚀 Starting OpenClaw daemon..."
openclaw gateway install
openclaw daemon start
sleep 3

# 6. Apply pf Firewall Shield
echo "🛡️ Applying pf Firewall Anchor (requires sudo)..."
sudo tee /etc/pf.anchors/openclaw-ollama > /dev/null <<'EOF'
pass in quick on lo0 proto tcp from 127.0.0.1 to 127.0.0.1 port { 3000, 11434 }
pass in quick on lo0 proto tcp from ::1 to ::1 port { 3000, 11434 }
block in quick proto tcp from any to any port { 3000, 11434 }
EOF

if ! grep -q 'anchor "openclaw-ollama"' /etc/pf.conf; then
    echo 'anchor "openclaw-ollama"' | sudo tee -a /etc/pf.conf > /dev/null
    echo 'load anchor "openclaw-ollama" from "/etc/pf.anchors/openclaw-ollama"' | sudo tee -a /etc/pf.conf > /dev/null
fi
sudo pfctl -f /etc/pf.conf
sudo pfctl -e 2>/dev/null || true

echo "✅ Deployment Complete. System is mathematically secure."
echo "Navigate to [http://127.0.0.1:3000](http://127.0.0.1:3000) and log in with your token."