#!/bin/bash
# ==============================================================================
# OpenClaw Hardening Verification Script (v4.0 - Zero-Trust Edition)
# ==============================================================================
# Description: Automates the deterministic auditing of service bindings, 
# pf firewall rules, and strict POSIX permissions (Configuration Immutability).
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting OpenClaw Hardening Verification...${NC}\n"

# 1. Verify Service Bindings (Application Layer)
echo -e "🔎 ${YELLOW}Checking Service Bindings (LISTEN state only)...${NC}"

OPENCLAW_LISTEN=$(lsof -iTCP:3000 -sTCP:LISTEN -Pn 2>/dev/null)
if echo "$OPENCLAW_LISTEN" | grep -q "\*:3000"; then
    echo -e "${RED}❌ FAILED:${NC} OpenClaw is listening on all interfaces (*:3000). It must be restricted to localhost."
elif echo "$OPENCLAW_LISTEN" | grep -E -q "(127\.0\.0\.1|::1):3000"; then
    echo -e "${GREEN}✅ PASSED:${NC} OpenClaw is safely bound to localhost."
else
    echo -e "${YELLOW}⚠️  WARNING:${NC} OpenClaw is not currently listening on port 3000. Is it running?"
fi

# 2. Verify pf Firewall (Network Layer)
echo -e "\n🔎 ${YELLOW}Checking pf Firewall Status...${NC}"

if sudo pfctl -s info 2>/dev/null | grep -q "Status: Enabled"; then
    echo -e "${GREEN}✅ PASSED:${NC} macOS pf firewall is ENABLED."
else
    echo -e "${RED}❌ FAILED:${NC} macOS pf firewall is DISABLED. Run 'sudo pfctl -E'."
fi

if sudo pfctl -a openclaw-ollama -s rules 2>/dev/null | grep -q "127.0.0.1"; then
    echo -e "${GREEN}✅ PASSED:${NC} OpenClaw pf anchor rules are loaded and populated."
else
    echo -e "${RED}❌ FAILED:${NC} OpenClaw pf anchor is empty or not loaded."
fi

# 3. Verify Filesystem Permissions (Filesystem Layer)
echo -e "\n🔎 ${YELLOW}Checking Filesystem Permissions...${NC}"
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
ENV_FILE="$CONFIG_DIR/.env"

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
    if [ "$FILE_PERMS" == "400" ]; then
        echo -e "${GREEN}✅ PASSED:${NC} File openclaw.json has strict 400 (read-only) permissions."
    else
        echo -e "${RED}❌ FAILED:${NC} File openclaw.json has unsafe permissions ($FILE_PERMS). Expected 400."
    fi
else
    echo -e "${YELLOW}⚠️  WARNING:${NC} File $CONFIG_FILE does not exist."
fi

if [ -f "$ENV_FILE" ]; then
    ENV_PERMS=$(stat -f "%A" "$ENV_FILE")
    if [ "$ENV_PERMS" == "600" ]; then
        echo -e "${GREEN}✅ PASSED:${NC} File .env has strict 600 permissions."
    else
        echo -e "${RED}❌ FAILED:${NC} File .env has unsafe permissions ($ENV_PERMS). Expected 600."
    fi
else
    echo -e "${RED}❌ FAILED:${NC} File .env is missing. Cloud API keys may not be properly segregated."
fi

echo -e "\n${YELLOW}Verification Complete.${NC}"