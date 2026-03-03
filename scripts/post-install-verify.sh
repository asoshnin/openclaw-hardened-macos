#!/bin/bash
# ==============================================================================
# OpenClaw Hardening Verification Script (v5.0 - Remediated Edition)
# ==============================================================================
# Description: Automates deterministic auditing of service bindings, pf
# firewall rules, filesystem permissions, and config content.
#
# Remediation: RED TEAM audit 2026-03-03 (F-003, F-032, F-033, RT2 note)
# Changes: chmod check 400→600, stronger pf anchor check, JSON content
# validation added, set -euo pipefail added for reliable error handling.
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0

pass() { echo -e "${GREEN}✅ PASSED:${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}❌ FAILED:${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}⚠️  WARNING:${NC} $1"; }

echo -e "${YELLOW}Starting OpenClaw Hardening Verification...${NC}\n"

# 1. Verify Service Bindings (Application Layer)
# NOTE: Port 3000 is an intentional non-default (official default: 18789).
# If gateway.port is changed in openclaw.json, update the port checks below.
echo -e "🔎 ${YELLOW}Checking Service Bindings (LISTEN state only)...${NC}"

OPENCLAW_LISTEN=$(lsof -iTCP:3000 -sTCP:LISTEN -Pn 2>/dev/null || true)
if echo "$OPENCLAW_LISTEN" | grep -q "\*:3000"; then
    fail "OpenClaw is listening on all interfaces (*:3000). It must be restricted to localhost."
elif echo "$OPENCLAW_LISTEN" | grep -E -q "(127\.0\.0\.1|::1):3000"; then
    pass "OpenClaw is safely bound to localhost."
else
    warn "OpenClaw is not currently listening on port 3000. Is it running?"
fi

OLLAMA_LISTEN=$(lsof -iTCP:11434 -sTCP:LISTEN -Pn 2>/dev/null || true)
if echo "$OLLAMA_LISTEN" | grep -q "\*:11434"; then
    fail "Ollama is listening on all interfaces (*:11434). It must be restricted to localhost."
elif echo "$OLLAMA_LISTEN" | grep -E -q "(127\.0\.0\.1|::1):11434"; then
    pass "Ollama is safely bound to localhost."
else
    warn "Ollama is not currently listening on port 11434. Is it running?"
fi

# 2. Verify pf Firewall (Network Layer)
echo -e "\n🔎 ${YELLOW}Checking pf Firewall Status...${NC}"

if sudo pfctl -s info 2>/dev/null | grep -q "Status: Enabled"; then
    pass "macOS pf firewall is ENABLED."
else
    fail "macOS pf firewall is DISABLED. Run 'sudo pfctl -E'."
fi

# F-032: Strengthen anchor check — verify both pass and block rules are present
ANCHOR_OUT=$(sudo pfctl -a openclaw-ollama -s rules 2>/dev/null || true)
if echo "$ANCHOR_OUT" | grep -q "pass in quick on lo0" && echo "$ANCHOR_OUT" | grep -q "block in quick"; then
    pass "OpenClaw pf anchor rules are loaded (pass + block rules confirmed)."
else
    fail "OpenClaw pf anchor is incomplete or not loaded. Expected 'pass in quick on lo0' and 'block in quick'."
fi

# 3. Verify Filesystem Permissions (Filesystem Layer)
echo -e "\n🔎 ${YELLOW}Checking Filesystem Permissions...${NC}"
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
ENV_FILE="$CONFIG_DIR/.env"

if [ -d "$CONFIG_DIR" ]; then
    DIR_PERMS=$(stat -f "%A" "$CONFIG_DIR")
    if [ "$DIR_PERMS" == "700" ]; then
        pass "Directory $CONFIG_DIR has strict 700 permissions."
    else
        fail "Directory $CONFIG_DIR has unsafe permissions ($DIR_PERMS). Expected 700."
    fi
else
    warn "Directory $CONFIG_DIR does not exist."
fi

if [ -f "$CONFIG_FILE" ]; then
    FILE_PERMS=$(stat -f "%A" "$CONFIG_FILE")
    # F-003: Official docs mandate 600 (user read/write), not 400
    if [ "$FILE_PERMS" == "600" ]; then
        pass "File openclaw.json has correct 600 permissions (user read/write, per official docs)."
    else
        fail "File openclaw.json has unexpected permissions ($FILE_PERMS). Expected 600 (per docs.openclaw.ai/gateway/security)."
    fi
else
    warn "File $CONFIG_FILE does not exist."
fi

if [ -f "$ENV_FILE" ]; then
    ENV_PERMS=$(stat -f "%A" "$ENV_FILE")
    if [ "$ENV_PERMS" == "600" ]; then
        pass "File .env has strict 600 permissions."
    else
        fail "File .env has unsafe permissions ($ENV_PERMS). Expected 600."
    fi
else
    fail "File .env is missing. Cloud API keys and gateway token may not be properly segregated."
fi

# 4. Docker prerequisite check (F-023: required for BASELINE §3 agent sandboxing)
echo -e "\n🔎 ${YELLOW}Checking Docker (required for agent sandboxing)...${NC}"
if docker info &>/dev/null 2>&1; then
    pass "Docker is running (required for BASELINE §3 agent sandboxing)."
else
    fail "Docker is not running or not installed. Agent sandboxing (BASELINE §3) requires Docker. Run: brew install --cask docker"
fi

# 5. F-033: Validate openclaw.json content (not just permissions)
echo -e "\n🔎 ${YELLOW}Validating openclaw.json content...${NC}"
if [ -f "$CONFIG_FILE" ]; then
    python3 - <<'PYEOF'
import json, os, sys
try:
    c = json.load(open(os.path.expanduser('~/.openclaw/openclaw.json')))
    errors = []
    if c.get('gateway', {}).get('host') not in ('127.0.0.1', '::1'):
        errors.append("gateway.host is not 127.0.0.1 or ::1")
    if 'shell' not in c.get('tools', {}).get('deny', []):
        errors.append("'shell' is not in tools.deny")
    if 'fs.write' not in c.get('tools', {}).get('deny', []):
        errors.append("'fs.write' is not in tools.deny")
    mdns_mode = c.get('discovery', {}).get('mdns', {}).get('mode', 'not set')
    if mdns_mode != 'off':
        errors.append(f"discovery.mdns.mode is '{mdns_mode}' — should be 'off'")
    if errors:
        for e in errors:
            print(f"\033[0;31m❌ FAILED:\033[0m Config content: {e}")
        sys.exit(1)
    else:
        print("\033[0;32m✅ PASSED:\033[0m Config content validated (gateway binding, tools.deny, mDNS).")
except Exception as ex:
    print(f"\033[0;31m❌ FAILED:\033[0m Could not parse openclaw.json: {ex}")
    sys.exit(1)
PYEOF
else
    warn "Skipping config content check — openclaw.json not found."
fi

# Summary
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}Verification Complete.${NC}"
echo -e "✅ Passed: $PASS  |  ❌ Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}⚠️  Fix all FAILED checks before considering this deployment secure.${NC}"
    exit 1
fi