#!/bin/bash
# ==============================================================================
# OpenClaw Hardening Verification Script (v3.1)
# ==============================================================================
# Description: Automates the deterministic auditing of service bindings, 
# pf firewall rules, and strict POSIX permissions.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting OpenClaw Hardening Verification...${NC}\n"

# 1. Verify Service Bindings (Application Layer)
echo -e "🔎 ${YELLOW}Checking Service Bindings (LISTEN state only)...${NC}"

# Check OpenClaw (Port 3000)
OPENCLAW_LISTEN=$(lsof -iTCP:3000 -sTCP:LISTEN -Pn 2>/dev/null)
if echo "$OPENCLAW_LISTEN" | grep -q "\*:3000"; then
    echo -e "${RED}❌ FAILED:${NC} OpenClaw is listening on all interfaces (*:3000). It must be restricted to localhost."
elif echo "$OPENCLAW_LISTEN" | grep -E -q "(127\.0\.0\.1|::1):3000"; then
    echo -e "${GREEN}✅ PASSED:${NC} OpenClaw is safely bound to localhost."
else
    echo -e "${YELLOW}⚠️  WARNING:${NC} OpenClaw (port 3000) does not appear to be running."
fi

# Check Ollama (Port 11434)
OLLAMA_LISTEN=$(lsof -iTCP:11434 -sTCP:LISTEN -Pn 2>/dev/null)
if echo "$OLLAMA_LISTEN" | grep -q "\*:11434"; then
    echo -e "${RED}❌ FAILED:${NC} Ollama is listening on all interfaces (*:11434). Update launchd plist."
elif echo "$OLLAMA_LISTEN" | grep -E -q "(127\.0\.0\.1|::1):11434"; then
    echo -e "${GREEN}✅ PASSED:${NC} Ollama is safely bound to localhost."
else
    echo -e "${YELLOW}⚠️  WARNING:${NC} Ollama (port 11434) does not appear to be running."
fi
echo ""

# 2. Verify pf Firewall (Firewall Layer)
echo -e "🔎 ${YELLOW}Checking pf Firewall Status & Anchor Integrity...${NC}"
if sudo pfctl -s info 2>/dev/null | grep -q "Status: Enabled"; then
    echo -e "${GREEN}✅ PASSED:${NC} macOS pf firewall is Enabled."
else
    echo -e "${RED}❌ FAILED:${NC} macOS pf firewall is DISABLED. Run 'sudo pfctl -E'."
fi

# Check if the anchor contains the required loopback rules
if sudo pfctl -a openclaw-ollama -s rules 2>/dev/null | grep -q "127.0.0.1"; then
    echo -e "${GREEN}✅ PASSED:${NC} OpenClaw pf anchor rules are loaded and populated."
else
    echo -e "${RED}❌ FAILED:${NC} OpenClaw pf anchor is empty or not loaded."
fi
echo ""

# 3. Verify Filesystem Permissions (Filesystem Layer)
echo -e "🔎 ${YELLOW}Checking Filesystem Permissions...${NC}"
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

if [ -d "$CONFIG_DIR" ]; then
    DIR_PERMS=$(stat -f "%A" "$CONFIG_DIR")
    if [ "$DIR_PERMS" == "700" ]; then
        echo -e "${GREEN}✅ PASSED:${NC} Directory $CONFIG_DIR has strict 700 permissions."
    else
        echo -e "${RED}❌ FAILED:${NC} Directory $CONFIG_DIR has unsafe permissions ($DIR_PERMS). Expected 700."
    fi
else
    echo -e "${YELLOW}⚠️  WARNING:${NC} Directory $CONFIG_DIR does not exist."
fi

if [ -f "$CONFIG_FILE" ]; then
    FILE_PERMS=$(stat -f "%A" "$CONFIG_FILE")
    if [ "$FILE_PERMS" == "600" ]; then
        echo -e "${GREEN}✅ PASSED:${NC} Config file has strict 600 permissions."
    else
        echo -e "${RED}❌ FAILED:${NC} Config file has unsafe permissions ($FILE_PERMS). Expected 600."
    fi
else
    echo -e "${YELLOW}⚠️  WARNING:${NC} Config file $CONFIG_FILE does not exist."
fi

echo -e "\n${YELLOW}Verification Complete.${NC}"