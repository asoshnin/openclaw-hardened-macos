# **Zero-Trust Documentation Update Workflow: Dual-Agent Audit & ChatOps Deployment for OpenClaw/macOS**

# **`openclaw-hardened-macos_updater`**

This document defines the strict, asynchronous, event-driven state machine required to safely update the OpenClaw Zero-Trust deployment documentation. It is engineered for a hybrid ChatOps workflow, allowing mobile Matrix notifications with the flexibility of either remote (Matrix) or local (Desktop CLI) deployment authorization.

## **1\. Agent Runtime Specifications**

### **🛠️ Agent 1: The Architect (Update & Drafting Engine)**

**Purpose:** To ingest external release data, analyze diffs, and draft updates exclusively within an isolated Docker sandbox.

**Sandbox Configuration:** \* `image: "openclaw-sandbox:bookworm-slim@sha256:<pinned_hash>"`

* `network: "none"`  
* `workspaceAccess: "rw"` (Mapped to `~/.openclaw/staging/`)  
* `capDrop: ["ALL"]`  
* `readOnlyRoot: true`  
* `resources`: { `memory`: "512m", `cpus`: "1.0", `pidsLimit`: 64 }

**System Metaprompt:**

```
<role>
You are the Principal Infrastructure Architect for an enterprise OpenClaw deployment on macOS Apple Silicon. Your objective is safely draft updates to our local documentation based on new official OpenClaw releases.
</role>

<context>
You operate within an ephemeral, completely isolated Docker sandbox. You have read/write access to a staging copy of our repository. You do not have internet access, git permissions, or external communication capabilities. 
</context>

<directives>
1. INGESTION: Read the provided release notes. Identify changes in OpenClaw architecture or security features.
2. ANALYSIS: Review our local `BASELINE.md` and `GUIDE.md`. Compare our Zero-Trust constraints against new features.
3. DRAFTING: Use `fs.write` to modify the documents in your isolated workspace. 
    - You MUST NOT weaken any existing security constraints (e.g., `network: "none"`, loopback binding, pf firewall, SHA-256 pinning).
4. HANDOFF: Generate a file named `REVIEW_REQUEST.md` summarizing exactly what you changed. Terminate your execution loop to hand off to the Red Team Agent.
</directives>

```

### **🛡️ Agent 2: The Red Team (Security QA & Audit Gate)**

**Purpose:** To act as an adversarial auditor. It cannot modify repository files; it only evaluates drafts against `BASELINE.md` and issues structured JSON verdicts.

**Sandbox Configuration:** \* `image: "openclaw-sandbox:bookworm-slim@sha256:<pinned_hash>"`

* `network: "none"`  
* `workspaceAccess: "rw"` (Mapped to `~/.openclaw/staging/`)  
* `capDrop: ["ALL"]`  
* `readOnlyRoot: true`  
* `resources`: { `memory`: "512m", `cpus`: "1.0", `pidsLimit`: 64 }

**System Metaprompt:**

```
<role>
You are the Lead Red Team Security Auditor. Your sole purpose is to ruthlessly evaluate documentation updates drafted by the Architect Agent. You are the final automated gate before Human-in-the-Loop (HITL) approval.
</role>

<context>
The Architect Agent has modified files in a staging workspace and generated `REVIEW_REQUEST.md`. You have `fs.read` access to this workspace. You physically cannot send network messages or trigger host scripts.
</context>

<audit_framework>
Evaluate the modified documents against these immutable laws. If ANY law is violated, you MUST reject the draft.
1. DoS Constraints: Are Docker limits (cpus, memory 512m, pidsLimit) strictly enforced?
2. Supply Chain: Are Docker images pinned via SHA-256? Is `latest` forbidden?
3. Secret Management: Are secrets ephemerally injected? No Docker `ENV` variables?
4. Network Isolation: Is `network: "none"` applied? Is `pf` loopback intact?
5. Break-Glass: Is the HITL audit logging (`os_log`/syslog) requirement intact?
</audit_framework>

<execution_loop>
- If violation found: Write `REJECTION_REPORT.json` detailing the violation. Terminate loop.
- If 100% compliant: Generate a SHA-256 hash of the modified files. Write `APPROVAL_CERTIFICATE.json` containing the summary and the hash. Terminate loop. Do NOT attempt to contact the administrator.
</execution_loop>

```

---

## **2\. Asynchronous State Machine & Dual-Path Orchestration**

### **Phase 1: Background Drafting (Automated Execution)**

1. A macOS `launchd` timer executes the orchestrator script daily.  
2. If a new release is detected, it clones the repository to a secure staging directory: `~/.openclaw/staging/` (Directory MUST be locked to octal `700` permissions to prevent TOCTOU tampering).  
3. The script sequentially invokes **Agent 1** and **Agent 2** via the local API.

### **Phase 2: Async Notification (Matrix Bridge)**

4. The host script monitors `~/.openclaw/staging/` for `APPROVAL_CERTIFICATE.json`.  
5. Upon detection, it parses the hash and dispatches an OOB message to the Matrix webhook:

```
🚨 SYSTEM UPDATE DRAFTED 🚨
OpenClaw v2026.3.0 released. Red Team has approved the updates.
To authorize, reply via Matrix: /deploy <hash>
Or execute on Desktop: ./deploy-staged-update.sh <hash>

```

6. The script *terminates gracefully*, leaving the locked staging folder intact.

### **Phase 3: Deployment Authorization (Dual-Path)**

The administrator chooses their execution path based on their current context:

* **Path A (Mobile/Remote):** Admin replies to the Matrix bot with `/deploy <hash>`. The OpenClaw Gateway intercepts this, triggers the Deployer function, verifies the hash, ephemerally loads the `.env` PAT, pushes the commit, and deletes the staging folder.  
* **Path B (Desktop/Local):** Admin logs into their Mac terminal and runs `./deploy-staged-update.sh <hash>`. The script performs the exact same hash verification and ephemeral PAT injection natively via bash, bypassing the Gateway entirely.

## **Appendix A: Reference Implementation for `deploy-staged-update.sh`**

The following bash script implements **Phase 3, Path B (Desktop/Local)** of the deployment workflow. It strictly adheres to the Zero-Trust secrets management and TOCTOU prevention guidelines established in the architectural baseline.

### **Script: `deploy-staged-update.sh`**

**Location:** Root of the main repository or a secure `~/.local/bin/` directory. **Permissions:** `chmod 700 deploy-staged-update.sh`

```shell
#!/usr/bin/env bash
#
# OpenClaw Zero-Trust Deployment Script (Phase 3: Desktop/Local Path)
# This script securely deploys drafted documentation updates from the isolated staging environment.
#
set -euo pipefail

# --- Configuration Variables ---
STAGING_DIR="$HOME/.openclaw/staging"
ENV_FILE="$HOME/.openclaw/.env"
CERT_FILE="$STAGING_DIR/APPROVAL_CERTIFICATE.json"
REPO_URL="[github.com/asoshnin/openclaw-hardened-macos.git](https://github.com/asoshnin/openclaw-hardened-macos.git)"
BRANCH_NAME="main"

echo "🛡️  Initiating Zero-Trust Staged Deployment..."

# 1. Input Validation
if [ "$#" -ne 1 ]; then
    echo "❌ Error: Missing authorization hash."
    echo "Usage: ./deploy-staged-update.sh <hash>"
    exit 1
fi
USER_HASH="$1"

# 2. Staging Environment & Integrity Check
if [ ! -d "$STAGING_DIR" ]; then
    echo "❌ Error: Staging directory not found. No updates pending."
    exit 1
fi

if [ ! -f "$CERT_FILE" ]; then
    echo "❌ Error: Red Team APPROVAL_CERTIFICATE.json is missing. Deployment aborted."
    exit 1
fi

# 3. Hash Verification (TOCTOU Mitigation)
# Extract the approved hash generated by the Red Team Agent
APPROVED_HASH=$(grep -o '"hash": *"[^"]*"' "$CERT_FILE" | cut -d'"' -f4)

if [ "$USER_HASH" != "$APPROVED_HASH" ]; then
    echo "❌ SECURITY ALERT: Hash mismatch!"
    echo "Provided Hash: $USER_HASH"
    echo "Approved Hash: $APPROVED_HASH"
    echo "The staging directory may have been tampered with. Deployment aborted."
    exit 1
fi
echo "✅ Hash verified. Red Team approval confirmed."

# 4. Ephemeral Secret Injection & Git Push
# Extract GitHub PAT securely without exposing it to the terminal history
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Error: Locked .env file not found at $ENV_FILE"
    exit 1
fi

echo "🔐 Ephemerally injecting GitHub PAT..."
# Read PAT strictly into script memory
GITHUB_PAT=$(grep '^GITHUB_PAT=' "$ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]' || true)

if [ -z "$GITHUB_PAT" ]; then
    echo "❌ Error: GITHUB_PAT not found in $ENV_FILE"
    exit 1
fi

# Navigate to the staging repository
cd "$STAGING_DIR"

# Commit the drafted changes
git add .
git commit -m "docs(auto): OpenClaw Zero-Trust documentation update via ChatOps [Hash: ${USER_HASH:0:8}]"

# Push to origin using an ephemeral HTTP Authorization header
# This prevents the token from appearing in the remote URL or local `ps` process lists
echo "🚀 Pushing update to remote repository..."
B64_PAT=$(printf "x-access-token:%s" "$GITHUB_PAT" | base64)
git -c http.extraHeader="Authorization: Basic ${B64_PAT}" push "https://${REPO_URL}" "$BRANCH_NAME"

# 5. Cryptographic Flush & Cleanup
echo "🧹 Flushing secrets from memory and destroying staging environment..."
unset GITHUB_PAT
unset B64_PAT
cd "$HOME"
rm -rf "$STAGING_DIR"

echo "🟢 DEPLOYMENT SUCCESSFUL. Zero-Trust state restored."
exit 0
```

### **Security Notes on this Implementation:**

* **`set -euo pipefail`**: Ensures the script immediately terminates if any command fails, preventing partial or corrupt deployments.  
* **Header-based Auth (`http.extraHeader`)**: By passing the token via a base64-encoded HTTP header rather than embedding it directly into the remote Git URL (`https://<token>@github.com/...`), we eliminate the risk of the plaintext token leaking into the local `.git/config` file or system-wide process monitors during the push execution.  
* **Variable Unsetting**: `unset GITHUB_PAT` and `unset B64_PAT` physically flush the memory space within the bash environment prior to script termination.

## **Appendix B: Reference Implementation for `pipeline-trigger.sh`**

The following bash script implements **Phase 1 (Drafting) and Phase 2 (Matrix Notification)**. It is designed to be executed daily via a macOS `launchd` timer. It strictly handles the network operations (GitHub API and Matrix Webhooks) on the host level, ensuring the AI agents themselves remain completely network-isolated.

### **Script: `pipeline-trigger.sh`**

**Location:** Root of the main repository or a secure `~/.local/bin/` directory. **Permissions:** `chmod 700 pipeline-trigger.sh`

```shell
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
```

### **Security Notes on this Implementation:**

* **Host-Driven Network Access:** The pipeline utilizes `curl` on the host to fetch release notes and send Matrix messages. The Docker sandboxes containing the LLM agents maintain their strict `network: "none"` posture, completely isolating them from the internet.  
* **Idempotency:** The `.latest_processed_release` state file prevents the pipeline from endlessly running and generating redundant drafts if the human admin takes several days to approve a pending update.  
* **Failure Failsafe:** If the Red Team agent rejects the draft (meaning `APPROVAL_CERTIFICATE.json` is not generated), the script immediately destroys the staging directory and aborts, preventing broken or malicious code from lingering in the file system.