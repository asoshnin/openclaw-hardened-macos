# RED TEAM AUDIT REPORT

## Repository: `openclaw-hardened-macos`

## Target Version: OpenClaw v2026.2.26

## Audit Date: 2026-03-03

## Classification: CONFIDENTIAL — INTERNAL USE ONLY

---

## 1. Executive Summary

### Finding Totals

| Severity | Count |
|---|---|
| 🔴 CRITICAL | 8 |
| 🟠 HIGH | 12 |
| 🟡 MEDIUM | 11 |
| 🔵 LOW | 7 |
| ⚪ INFORMATIONAL | 4 |
| **TOTAL** | **42** |

### Overall Security Posture Assessment

This repository is an ambitious, well-intentioned hardening guide that demonstrates genuine security sophistication — the `umask 077` subshell discipline, the dual `pf` anchor layer, and the HITL break-glass protocol are all exemplary. However, the audit reveals **a fundamental factual divergence from the official OpenClaw v2026.2.26 documentation** that undermines the entire guide's credibility and renders several hardening steps either incorrect or unverifiable. The repository was likely authored with reference to an older or beta version of OpenClaw and was not systematically re-verified against the live `docs.openclaw.ai` documentation.

Most critically: the **default gateway port** the guide hardens (`3000`) differs from the official default (`18789`); the **configuration schema** for model selection (`agents.defaults.model` as a string) conflicts with the official object-based schema; and the **officially mandated file permission** for `openclaw.json` is `600` (not `400` as the guide instructs). Together, these three errors mean a user who follows this guide precisely may produce a system that is either broken or not secured as described.

### Top 3 Most Dangerous Findings

1. **FINDING-001 (CRITICAL):** Wrong default port (`3000` vs. official `18789`) — the entire firewall rule set protects the wrong port, leaving the real gateway port open.
2. **FINDING-003 (CRITICAL):** `openclaw.json` mandated as `chmod 400` (read-only), but the official docs specify `600`, and the read-only lock breaks all standard `openclaw config set` operations, creating an unusable system.
3. **FINDING-006 (CRITICAL):** The `BASELINE.md` states secrets MUST NOT be stored in plaintext in `openclaw.json`, yet every script and guide section does exactly that for the gateway auth token — a direct logical contradiction at the architectural level.

### Mandatory Remediation Priority Order

1. Verify and update the gateway port throughout all documents.
2. Correct `openclaw.json` permission from `400` to `600`.
3. Reconcile the BASELINE's token-storage prohibition with the guide's actual implementation.
4. Correct the `agents.defaults.model` schema to an object.
5. Update the KNOWLEDGE_BASE cloud model name from Kimi K2.5 to Gemini.
6. Fix the LaunchAgent plist `$HOME` non-expansion bug.
7. Add missing pf syntax validation to `deploy-openclaw.sh`.

---

## 2. Findings Register

---

### DOMAIN 1: Factual Accuracy & Version Fidelity

---

**FINDING-001**
**Severity:** 🔴 CRITICAL
**Domain:** Domain 1 — Factual Accuracy
**File:** `GUIDE.md`, `BASELINE.md`, `scripts/pf-anchor-openclaw.rules`, `scripts/deploy-openclaw.sh`, `scripts/post-install-verify.sh`
**Location:** `GUIDE.md` §3 Architecture Overview, §9.4, §10.1; `pf-anchor-openclaw.rules` line 10

**Summary:** The entire repository is hardened around port `3000`. The official OpenClaw v2026.2.26 documentation confirms the default gateway port is `18789`.

**Evidence:**
> `GUIDE.md` §3: `│  │  OpenClaw        │  │  127.0.0.1:3000  │`
> `pf-anchor-openclaw.rules` line 10: `pass in quick on lo0 proto tcp from 127.0.0.1 to 127.0.0.1 port { 3000, 11434 }`
> `post-install-verify.sh` line 19-26: checks `lsof -iTCP:3000`

**Analysis:** The official docs (`docs.openclaw.ai/gateway/security` §0.4) state: *"Default: 18789 — Config/flags/env: gateway.port, --port, OPENCLAW_GATEWAY_PORT"*. The quick-start docs show `openclaw gateway --port 18789`. Every firewall rule, verification check, and architecture diagram in this repo uses port `3000`. If a user installs OpenClaw v2026.2.26 with no port override, the gateway will listen on `18789`, not `3000`. The pf anchor will then be protecting the wrong port — the actual gateway will be completely unprotected by the firewall.

**Official Reference:** `https://docs.openclaw.ai/gateway/security#0-4-network-exposure-bind-+-port-+-firewall` — "Default: 18789"

**Recommendation:** Replace all occurrences of port `3000` with `18789` across all documents and scripts, OR explicitly add `gateway: { port: 3000 }` to the `openclaw.json` config with a clear note that this is an intentional non-default to ensure the guide's firewall rules remain correct. The latter is safer for auditability.

---

**FINDING-002**
**Severity:** � HIGH *(downgraded from CRITICAL by RED TEAM 2: the official docs show the object form, but many gateways accept both string-shorthand and object form — runtime confirmation needed before treating as definitive breakage)*
**Domain:** Domain 1 — Factual Accuracy
**File:** `GUIDE.md`, `scripts/token-generator.sh`, `scripts/deploy-openclaw.sh`
**Location:** `GUIDE.md` §9.2 (lines 531–565); `token-generator.sh` lines 44–56

**Summary:** The `agents.defaults.model` configuration key is set as a plain string. The official v2026.2.26 schema requires it to be an object with a `primary` key.

**Evidence:**
> `GUIDE.md` §9.2 Python config block:
>
> ```python
> 'agents': {
>   'defaults': {
>     'model': 'google/gemini-3.1-pro-preview'
>   }
> }
> ```
>
> `token-generator.sh` line 56: `"model": "google/gemini-3.1-pro-preview",`

**Analysis:** The official configuration reference (`docs.openclaw.ai/gateway/configuration` — "Choose and configure models") shows the correct schema:

```json
{ "agents": { "defaults": { "model": { "primary": "anthropic/claude-sonnet-4-5", "fallbacks": ["openai/gpt-5.2"] } } } }
```

The model field is an **object** containing `primary` and optional `fallbacks`, not a bare string. A user who follows the guide will produce a config that the Gateway's strict JSON schema validator will likely reject on boot, triggering diagnostic-only mode.

**Official Reference:** `https://docs.openclaw.ai/gateway/configuration#common-tasks` — Model config schema example

**Recommendation:** Update `agents.defaults.model` in all configs to the object form:

```json
"agents": { "defaults": { "model": { "primary": "google/gemini-3.1-pro-preview" } } }
```

Also update `GUIDE.md` §9.3's verification script which reads `c['agents']['defaults']['model']['name']` — this key is also wrong; the correct key is `primary`.

---

**FINDING-003**
**Severity:** 🔴 CRITICAL
**Domain:** Domain 1 — Factual Accuracy
**File:** `GUIDE.md`, `BASELINE.md`, `scripts/post-install-verify.sh`
**Location:** `GUIDE.md` §9.2 (line 574), §10.4 (line 729); `post-install-verify.sh` line 62

**Summary:** The guide mandates `chmod 400` (read-only) on `openclaw.json`. The official security documentation explicitly mandates `600` (user read/write).

**Evidence:**
> `GUIDE.md` §9.2: `chmod 400 ~/.openclaw/openclaw.json`
> `GUIDE.md` §10.4: `chmod 400 ~/.openclaw/openclaw.json`
> `GUIDE.md` §16 Operational Notes: "The 'Unlock-Modify-Lock' Workflow — Because your configuration is locked to `400` (Zero-Trust), standard OpenClaw commands like `openclaw doctor --fix`, `openclaw configure`, or `openclaw config set` will fail..."

**Analysis:** The official docs (`docs.openclaw.ai/gateway/security#0-file-permissions`) categorically state: *"~/.openclaw/openclaw.json: **600** (user read/write only)"*. Setting it to `400` (read-only) is both non-standard and actively harmful: it breaks `openclaw config set`, `openclaw configure`, and `openclaw doctor --fix`. The guide's own §16 acknowledges this breakage but presents it as a feature ("Zero-Trust"). This is a false security benefit — the permission `600` already prevents other OS users from reading the file; `400` only additionally prevents the file owner from writing it, at the cost of breaking the application's self-management.

**Official Reference:** `https://docs.openclaw.ai/gateway/security#0-file-permissions`

**Recommendation:** Change all `chmod 400 ~/.openclaw/openclaw.json` to `chmod 600`. Remove the "Unlock-Modify-Lock" workflow from §16 as it is based on this incorrect premise. Update `post-install-verify.sh` line 62 to check for `600`.

---

**FINDING-004**
**Severity:** 🔴 CRITICAL
**Domain:** Domain 1 — Factual Accuracy
**File:** `GUIDE.md`
**Location:** §8.2 (line 475), §9.3 (line 595)

**Summary:** The guide's verification script reads `c['agents']['defaults']['model']['name']` — this will throw a `TypeError` because `model` is written as a string, not a dict.

**Evidence:**
> `GUIDE.md` §9.3:
>
> ```python
> print('Default model:', c['agents']['defaults']['model']['name'])
> ```
>
> But §9.2 writes: `'model': 'google/gemini-3.1-pro-preview'` (a string)

**Analysis:** This is a direct runtime error. A string does not have a `['name']` key. The verification script that users are told to run as a quality gate will crash with `TypeError: string indices must be integers`. This undermines user confidence and leaves the verification step non-functional.

**Recommendation:** If the schema is corrected to the object form (per FINDING-002), update the print statement to `c['agents']['defaults']['model']['primary']`. If keeping the string form, change to `c['agents']['defaults']['model']`.

---

**FINDING-005**
**Severity:** 🟠 HIGH
**Domain:** Domain 1 — Factual Accuracy
**File:** `GUIDE.md`
**Location:** §8.2 (line 474–479)

**Summary:** The guide installs OpenClaw via `npm install -g openclaw@2026.2.26`. The official quick-start recommends a curl-based install script, and `npm` global install is not the primary documented method.

**Evidence:**
> `GUIDE.md` §8.2: `npm install -g openclaw@2026.2.26`

**Analysis:** The official quick-start (`docs.openclaw.ai/start/quickstart`) shows: `curl -fsSL https://openclaw.ai/install.sh | bash` as the recommended method, with `npm` as a secondary option. The guide's security rationale for using npm (to avoid piping to bash) is philosophically sound but never explicitly stated, and the guide itself pipes to bash without hesitation for Homebrew (§5). Additionally, the npm method for a version-pinned install is valid for Zero-Trust purposes, but the url `openclaw.ai/install.sh` may itself be a more auditable path. This is HIGH not CRITICAL because npm install is not wrong, just inconsistent with primary official docs.

**Official Reference:** `https://docs.openclaw.ai/start/quickstart#quick-setup-cli`

**Recommendation:** Either explicitly justify why `npm` is preferred over the official `curl` installer (citing supply-chain auditability, version pinning), or add a note acknowledging the official installer exists and explaining the choice.

---

**FINDING-006 (see Domain 2 — FINDING-015 for the full mDNS security analysis)**
**Severity:** 🟠 HIGH *(note added by RED TEAM 2: `gateway.mode` may exist as an undocumented/legacy key that silently no-ops rather than errors — cannot be confirmed without runtime testing or full configuration schema access; HIGH severity is appropriate given the ambiguity)*
**Domain:** Domain 1 — Factual Accuracy
**File:** `GUIDE.md`
**Location:** §9.4 subsection "1. Set the Gateway Mode" (line 612)

**Summary:** `openclaw config set gateway.mode local` — `gateway.mode` with value `local` is not documented in the official v2026.2.26 configuration reference.

**Evidence:**
> `GUIDE.md` §9.4: `openclaw config set gateway.mode local`

**Analysis:** The official configuration documentation (`docs.openclaw.ai/gateway/configuration`) lists `gateway.bind` with values `"loopback"`, `"lan"`, `"tailnet"`, `"custom"` for controlling network exposure. There is no `gateway.mode` key with a `local` value in the official docs. The correct hardening directive appears to be `gateway.bind: "loopback"` (which is also the documented **default**). Running an undocumented config key may silently fail or produce unexpected behavior.

**Official Reference:** `https://docs.openclaw.ai/gateway/security#0-4-network-exposure-bind-+-port-+-firewall`

**Recommendation:** Replace `openclaw config set gateway.mode local` with `openclaw config set gateway.bind loopback` (or remove it entirely since `loopback` is the v2026.2.26 default).

---

**FINDING-007**
**Severity:** 🟠 HIGH
**Domain:** Domain 1 — Factual Accuracy
**File:** `GUIDE.md`
**Location:** §9.4, subsection headers "1." and "3." (lines 603, 619, 630)

**Summary:** Section 9.4 has three subsection numbers: "1.", "3.", "3." — the numeral "2." is entirely missing. One of the "3." headings is a duplicate label ("Verify Binding") mismatched with the install step.

**Evidence:**
> `GUIDE.md` line 603: `### **1\. Set the Gateway Mode & Disable Cloud Memory Search**`
> Line 619: `### **3\. Install and Start the Daemon**`
> Line 630: `### **3\. Verify Binding (The Final Test)**`

**Analysis:** The numbering gap (no step 2) and duplicate step 3 confuse the sequential installation procedure. Users may believe they have skipped a step. The likely intent is steps 1, 2, 3 covering: configure → install daemon → verify.

**Recommendation:** Renumber to "1. Set Gateway Mode", "2. Install and Start Daemon", "3. Verify Binding".

---

**FINDING-008**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 1 — Factual Accuracy
**File:** `KNOWLEDGE_BASE.md`
**Location:** §3 "Model Segregation & Data Privacy" (lines 33–35); URL table line 140

**Summary:** KNOWLEDGE_BASE.md still references `Kimi K2.5` as the default cloud model and lists the latest OpenClaw release as `2026.2.19`, despite the CHANGELOG confirming migration to `gemini-3.1-pro-preview` and targeting version `2026.2.26`.

**Evidence:**
> `KNOWLEDGE_BASE.md` §3: `- **Kimi K2.5 (Cloud / Default):** Use for general queries...`
> `KNOWLEDGE_BASE.md` URL table line 140: `https://github.com/openclaw/openclaw/releases — Versioned releases (latest: 2026.2.19)`
> `CHANGELOG.md`: `Changed — Cloud Model Baseline: Updated the default cloud model... from kimi-k2.5 to gemini-3.1-pro-preview.`

**Analysis:** This creates a direct internal contradiction. A user reading the KNOWLEDGE_BASE to understand privacy routing rules will be given incorrect guidance (routing general queries to Kimi K2.5, which no longer exists as the default). The stale version number also erodes trust in the document's currency.

**Recommendation:** Update §3 to reference `gemini-3.1-pro-preview` as the cloud default. Update the releases URL table to `2026.2.26`.

---

**FINDING-009**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 1 — Factual Accuracy
**File:** `GUIDE.md`
**Location:** §13.2 (lines 935–937)

**Summary:** The update procedure for Ollama uses `brew services restart ollama`, directly contradicting the installation guide's explicit warning against this exact command.

**Evidence:**
> `GUIDE.md` §6.3 (line 358): *"Important: Do not use `brew services start ollama` for this hardened setup. Homebrew's default service management does not reliably accept custom environment variable injection (like `OLLAMA_HOST`) via the CLI, which can result in the service binding to all interfaces silently."*
> `GUIDE.md` §13.2 (line 936): `brew services restart ollama`

**Analysis:** The update command silently undoes the entire Ollama loopback-binding hardening. After `brew services restart ollama`, Ollama may re-bind to `0.0.0.0:11434` without any warning because `OLLAMA_HOST` is not set in the Homebrew-managed service environment. The `pf` firewall will block external access but this is not a safe operational assumption — the guide explicitly says not to rely on it alone.

**Recommendation:** Replace `brew services restart ollama` in §13.2 with the equivalent `launchctl` cycle:

```shell
launchctl bootout gui/$(id -u)/com.ollama.serve
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ollama.serve.plist
```

---

### DOMAIN 2: Security Vulnerabilities & Hardening Gaps

---

**FINDING-010**
**Severity:** 🔴 CRITICAL
**Domain:** Domain 2 — Security Vulnerabilities
**File:** `BASELINE.md`, `GUIDE.md`, `scripts/token-generator.sh`
**Location:** `BASELINE.md` §4 (line 92); `GUIDE.md` §9.2 (line 515–574)

**Summary:** `BASELINE.md` §4 states that authentication tokens "MUST NOT be stored in plaintext within the `openclaw.json` configuration file." Every script in the repository does exactly this — storing the token as a plaintext JSON value.

**Evidence:**
> `BASELINE.md` §4 (line 92): *"Cryptographic secrets, API keys, and authentication tokens MUST NOT be stored in plaintext within the `openclaw.json` configuration file."*
> `GUIDE.md` §9.2 (line 535–537):
>
> ```python
> 'auth': {
>   'token': sys.stdin.read().strip()
> }
> ```
>
> `token-generator.sh` line 47: `"auth": { "token": "$AUTH_TOKEN_NEW" }`

**Analysis:** This is a direct, irreconcilable contradiction within the same repository between its own "Constitution" (BASELINE.md) and its own "Manual" (GUIDE.md). The BASELINE uses RFC 2119 "MUST NOT", making this a CRITICAL violation by its own standard. The official docs (`docs.openclaw.ai/gateway/configuration#environment-variables`) actually provide the correct resolution: use environment variable substitution in the config: `{ "gateway": { "auth": { "token": "${OPENCLAW_GATEWAY_TOKEN}" } } }` where the actual token is read from `.env`.

**Official Reference:** `https://docs.openclaw.ai/gateway/configuration#environment-variables`

**Recommendation:** Update the config template to use env-var substitution: `"token": "${OPENCLAW_GATEWAY_TOKEN}"`. Store the actual token in `~/.openclaw/.env` as `OPENCLAW_GATEWAY_TOKEN=<hex>`. This satisfies both the BASELINE mandate and the existing `.env` infrastructure. Update the BASELINE to reflect reality OR update the guide to implement true secret decoupling.

---

**FINDING-011**
**Severity:** 🔴 CRITICAL
**Domain:** Domain 2 — Security Vulnerabilities
**File:** `GUIDE.md`
**Location:** §9.2 Option B (lines 515–520)

**Summary:** The generated auth token is printed to stdout in plaintext with a prominent bold prompt: `"CRITICAL: YOUR SECURE TOKEN IS: $AUTH_TOKEN"`.

**Evidence:**
> `GUIDE.md` §9.2:
>
> ```
> echo "CRITICAL: YOUR SECURE TOKEN IS: $AUTH_TOKEN"
> echo "Save this! You will need it to authenticate."
> ```

**Analysis:** Printing a 256-bit secret to stdout creates multiple exposure vectors: terminal scrollback buffers (often unlimited), iTerm2/Terminal session recordings, screen-sharing sessions, accessibility APIs, `script`-based terminal loggers, and CI/CD log capture. The guide simultaneously warns against process-list leakage (correctly) but ignores stdout as an equally dangerous channel. The `token-generator.sh` script repeats this pattern at line 93.

**Recommendation:** Instead of printing the token, write it only to the `.env` file and instruct the user to retrieve it with: `cat ~/.openclaw/.env | grep OPENCLAW_GATEWAY_TOKEN`. If display is absolutely required, use a pager: `echo "$AUTH_TOKEN" | less -R` and document that `less` output does not persist in scrollback.

---

**FINDING-012**
**Severity:** 🟠 HIGH
**Domain:** Domain 2 — Security Vulnerabilities
**File:** `GUIDE.md`
**Location:** §11b (line 810–812)

**Summary:** Method 2 for dashboard authentication passes the auth token as a URL query parameter, exposing it to browser history, server logs, and macOS Spotlight indexing.

**Evidence:**
> `GUIDE.md` §11b: `open "http://127.0.0.1:3000/?token=YOUR_TOKEN"`

**Analysis:** URL query parameters are a well-documented credential leak vector (OWASP A02:2021). They appear in: browser history, referrer headers if the page loads external resources, HTTP server access logs, OS-level URL history (Spotlight/Siri), and bookmarks. This directly contradicts the Zero-Trust mandate. The official docs recommend the Control UI's token field for entry, not URL parameters.

**Recommendation:** Remove Method 2 entirely. Keep only Method 1 (UI entry). Add an explicit warning: *"Never append your token to the URL. Always enter it via the Control UI's Gateway Token field."*

---

**FINDING-013**
**Severity:** 🟠 HIGH
**Domain:** Domain 2 — Security Vulnerabilities
**File:** `GUIDE.md`
**Location:** §15.4 Phase 2 (lines 1204–1207)

**Summary:** Matrix bot and admin user accounts are registered with passwords passed as CLI arguments, making them visible in `ps` output and shell history.

**Evidence:**
> `GUIDE.md` §15.4:
>
> ```shell
> register_new_matrix_user -u admin_user -p <TYPE_A_SECURE_PASSWORD_HERE> -a -c homeserver.yaml
> register_new_matrix_user -u openclaw_bot -p <TYPE_A_DIFFERENT_PASSWORD_HERE> -a -c homeserver.yaml
> ```

**Analysis:** Passing passwords via `-p` flag makes them visible in `ps aux` output and persists them in `~/.zsh_history`. This contradicts §15.5 of the same guide ("Shell History Hygiene") and violates the core credential security mandate. The guide does not instruct users to clear this from history after running the command.

**Recommendation:** Use interactive password entry instead:

```shell
register_new_matrix_user -u admin_user -a -c homeserver.yaml
```

(The tool will prompt interactively for a password without it appearing in the process list or history.)

---

**FINDING-014**
**Severity:** 🟠 HIGH
**Domain:** Domain 2 — Security Vulnerabilities
**File:** `scripts/deploy-openclaw.sh`
**Location:** Lines 1807–1819 (Appendix D in GUIDE.md)

**Summary:** The automated deploy script applies `pf` rules without the pre-validation syntax check that the manual installation steps require.

**Evidence:**
> Manual step (`GUIDE.md` §10.2): includes `if sudo pfctl -vnf /etc/pf.conf 2>&1 | grep -q "syntax error"; then ... exit 1`
> `deploy-openclaw.sh` (Appendix D): `sudo pfctl -f /etc/pf.conf` — **no syntax pre-check**

**Analysis:** Without syntax validation, a malformed `pf.conf` (e.g., due to a partial write, disk full, or race condition) will be loaded, potentially disabling the entire macOS firewall silently. The manual steps include this safeguard; the automated script omits it — the opposite of what should be true for an automated path.

**Recommendation:** Insert the syntax validation block before `sudo pfctl -f /etc/pf.conf` in `deploy-openclaw.sh`, identical to the one in §10.2.

---

**FINDING-015**
**Severity:** 🟠 HIGH
**Domain:** Domain 2 — Security Vulnerabilities
**File:** `GUIDE.md`
**Location:** §9.4 mDNS/Bonjour (line 601–603)

**Summary:** The guide instructs disabling Bonjour "by disabling the gateway mode" rather than using the documented `discovery.mdns` configuration key, missing the official mitigation entirely.

**Evidence:**
> `GUIDE.md` §9.4: *"To maintain the Zero-Trust Mandate, we will explicitly disable network discovery protocols (Bonjour/mDNS) before starting the gateway..."* then sets `gateway.mode local` (the undocumented key per FINDING-006) — no `discovery.mdns` config is set.

**Analysis:** The official docs (`docs.openclaw.ai/gateway/security#0-4-1-mdns/bonjour-discovery-information-disclosure`) describe `discovery.mdns.mode` with values `"minimal"`, `"off"`, and `"full"`, plus `OPENCLAW_DISABLE_BONJOUR=1`. The guide's approach (setting `gateway.mode local`) does not provably disable mDNS and may do nothing for this purpose.

**Official Reference:** `https://docs.openclaw.ai/gateway/security#0-4-1-mdns/bonjour-discovery-information-disclosure`

**Recommendation:** Add to `openclaw.json`:

```json
"discovery": { "mdns": { "mode": "off" } }
```

Or set `OPENCLAW_DISABLE_BONJOUR=1` in `~/.openclaw/.env`.

---

**FINDING-016**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 2 — Security Vulnerabilities
**File:** `GUIDE.md`
**Location:** §15.6 Incident Response (lines 1309–1316)

**Summary:** The breach protocol code block has a formatting error — Step 1's `killall` code block is never closed (`EOF` is missing), causing Step 2's "Review for Persistence" prose to be rendered inside the code block as shell comments.

**Evidence:**
> `GUIDE.md` lines 1309–1316:
>
> ```
> 1. **Halt Execution Immediately:**
> ```shell
> killall -HUP openclaw 2>/dev/null || true
> launchctl bootout gui/$(id -u)/com.ollama.serve 2>/dev/null || killall ollama
>
> 2. **Review for Persistence:** Malicious shell executions often attempt...
> ```
>
> (No closing ` ``` ` before Step 2)

**Analysis:** The missing closing fence means anyone who copies the "Halt" block to their terminal will receive Step 2's prose text as part of the shell command, causing a parse error at the worst possible moment — during an active incident response.

**Recommendation:** Add a closing ` ``` ` fence after the `launchctl` line and before "2. **Review for Persistence:**".

---

**FINDING-017**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 2 — Security Vulnerabilities
**File:** `BASELINE.md`
**Location:** §5 (line 102)

**Summary:** BASELINE.md references the "MELON (Masked re-Execution and TooL comparisON)" framework as a SHOULD requirement. This framework is not documented in the official OpenClaw v2026.2.26 documentation and cannot be verified as a real feature.

**Evidence:**
> `BASELINE.md` §5: *"For advanced obfuscation detection, the system SHOULD leverage the MELON (Masked re-Execution and TooL comparisON) defense framework..."*

**Analysis:** No reference to "MELON" appears in `docs.openclaw.ai`. This appears to be either a proprietary research concept, a hallucinated feature, or a planned future capability. Including it in a production baseline as a "SHOULD" without an implementation path, plugin name, or documentation reference creates an unverifiable control — auditors cannot confirm compliance.

**Recommendation:** Either provide a concrete implementation reference (plugin name, configuration snippet) or remove MELON from the baseline and note it as "Research / Future Consideration."

---

### DOMAIN 3: Internal Inconsistencies & Contradictions

---

**FINDING-018**
**Severity:** 🟠 HIGH
**Domain:** Domain 3 — Inconsistencies
**File:** `GUIDE.md` vs. `docs/THREAT-MODEL.md` vs. `scripts/post-install-verify.sh`
**Location:** Multiple locations

**Summary:** The file permission for `openclaw.json` is stated as three different values across four documents: `400`, `600`, and implicitly `700`.

**Evidence:**
> `GUIDE.md` §9.2: `chmod 400 ~/.openclaw/openclaw.json` ← **400**
> `GUIDE.md` §1 table: `Filesystem | Restrictive permissions (700 / 600) on all config and log paths`
> `THREAT-MODEL.md` §3 Threat 3: *"strict `chmod 700` directory permissions and `chmod 600` file permissions"* ← **600**
> `post-install-verify.sh` line 62: checks for `400` ← **400**
> Official docs: mandates `600` ← **600**

**Analysis:** Three authoritative documents in the same repository disagree. The GUIDE and the verification script agree on `400` (which conflicts with the official docs). The THREAT-MODEL and the official docs agree on `600`. This cross-document inconsistency means the system cannot be audited deterministically.

**Recommendation:** Standardize on `600` (as per official docs). Update all references: GUIDE.md §1 table, §9.2, §10.4, §14.1, §14.2, §13.5; `post-install-verify.sh`; and the "Unlock-Modify-Lock" operational notes in §16.

---

**FINDING-019**
**Severity:** 🟠 HIGH
**Domain:** Domain 3 — Inconsistencies
**File:** `README.md`, `GUIDE.md`, `KNOWLEDGE_BASE.md`, `scripts/pipeline-trigger.sh`
**Location:** Multiple

**Summary:** The OpenClaw GitHub repository URL is given as three different URLs across the repository.

**Evidence:**
> `README.md` §"Assumptions & Scope": `https://github.com/openclaw/openclaw`
> `GUIDE.md` §21 Additional Resources table: `https://github.com/openclawhq/openclaw`
> `KNOWLEDGE_BASE.md` Tier 1 table line 139: `https://github.com/openclaw/openclaw`
> `scripts/pipeline-trigger.sh` line 243: `https://api.github.com/repos/openclaw/openclaw/releases/latest`

**Analysis:** `openclaw/openclaw` and `openclawhq/openclaw` point to different GitHub organizations. If one of these is incorrect, the supply-chain verification advice (checking the official repository for maintainer identity) is pointing users to a potentially wrong repository. The official docs website does not disambiguate this clearly on the pages fetched.

**Recommendation:** Verify the authoritative GitHub organization for OpenClaw (check `docs.openclaw.ai/reference/credits` or the domain registrar). Remove all instances of the incorrect URL. The pipeline-trigger.sh API call will fail if pointed at the wrong org.

---

**FINDING-020**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 3 — Inconsistencies
**File:** `GUIDE.md`
**Location:** §9.2 / §9.3 (lines 551–560 vs. line 595)

**Summary:** The `models.providers` schema in the guide uses custom keys `name` and `id` inside each model entry — this structure is not reflected in the official configuration reference.

**Evidence:**
> `GUIDE.md` §9.2:
>
> ```json
> "models": [
>   {"name": "llama3:8b", "id": "llama3:8b"},
>   {"name": "deepseek-coder-v2:lite", "id": "deepseek-coder-v2:lite"}
> ]
> ```
>
> Official docs show: model refs use `provider/model` string format directly.

**Analysis:** The official docs use `provider/model` as first-class string references (e.g., `anthropic/claude-sonnet-4-5`). The nested `{name, id}` object arrays inside a `models` list per-provider is a custom schema that is not documented in the v2026.2.26 configuration reference. This may be correct for an Ollama local-provider integration, but it requires explicit verification and documentation of the Ollama provider schema.

**Recommendation:** Verify the correct Ollama provider configuration schema against `docs.openclaw.ai/gateway/configuration-reference#custom-providers-and-base-urls` and update accordingly.

---

**FINDING-021**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 3 — Inconsistencies
**File:** `BASELINE.md` vs. `UPDATE_WORKFLOW.md`
**Location:** `BASELINE.md` §3 (line 29); `UPDATE_WORKFLOW.md` §Agent 1 Sandbox Config

**Summary:** BASELINE.md mandates `workspaceAccess: "ro"` for all sandboxes. UPDATE_WORKFLOW.md gives Agent 1 (the Architect) `workspaceAccess: "rw"` without documenting this as an approved exception.

**Evidence:**
> `BASELINE.md` §3: *"The host environment MUST be mounted into the container workspace utilizing a `workspaceAccess: \"ro\"` (read-only) directive."*
> `UPDATE_WORKFLOW.md` §Agent 1: `workspaceAccess: "rw" (Mapped to ~/.openclaw/staging/)`

**Analysis:** The BASELINE uses RFC 2119 "MUST", making the rw deviation a compliance violation by the document's own standard. While the functional reason is obvious (the Architect needs to write draft files), there is no documented exception, waiver, or justification. A staging-scoped `rw` mount is a reasonable operational deviation, but it needs to be explicitly declared as a sanctioned exception.

**Recommendation:** Add a "Baseline Exception" note in UPDATE_WORKFLOW.md: *"Note: Agent 1 requires `workspaceAccess: \"rw\"` as a sanctioned deviation from BASELINE §3, restricted to the isolated staging path `~/.openclaw/staging/`. Production agents MUST use `\"ro\"`."*

---

**FINDING-022**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 3 — Inconsistencies
**File:** `GUIDE.md`
**Location:** §9.4 (line 601) vs. §11b (line 797)

**Summary:** §9.4 states the guide will "disable Bonjour/mDNS" as a Zero-Trust step, but §11b says the dashboard is available at `http://127.0.0.1:3000/` with no mDNS-off confirmation step, suggesting this control may not be applied in the automated path.

**Evidence:**
> `GUIDE.md` §9.4: *"we will explicitly disable network discovery protocols (Bonjour/mDNS) before starting the gateway"*
> `scripts/deploy-openclaw.sh`: No `discovery.mdns` config key is set anywhere in the deploy script.

**Analysis:** The deploy script (Appendix D) skips the mDNS disabling step entirely, leaving automated deployments with mDNS active. This means OpenClaw will announce `_openclaw-gw._tcp` mDNS records on the local network, potentially revealing the gateway IP, port, username, and SSH port — precisely what the guide aims to prevent.

**Recommendation:** Add `"discovery": { "mdns": { "mode": "off" } }` to the config JSON in `deploy-openclaw.sh`'s Python config-writer block.

---

### DOMAIN 4: Critical Omissions

---

**FINDING-023**
**Severity:** 🔴 CRITICAL
**Domain:** Domain 4 — Critical Omissions
**File:** `GUIDE.md`, `README.md`
**Location:** §4 Prerequisites; `BASELINE.md` §3

**Summary:** BASELINE.md mandates Docker sandboxing for all agent tool execution, yet Docker is never listed as a prerequisite and has no installation instructions anywhere in the guide.

**Evidence:**
> `BASELINE.md` §3: *"All dynamic tool execution and untrusted data parsing MUST be routed into a network-isolated, ephemeral Docker container."*
> `GUIDE.md` §4 Prerequisites: Lists `uname -m`, disk space, macOS version, Xcode CLT, and shell — **Docker is absent**.

**Analysis:** A user completing the installation guide step-by-step will have no Docker installation. Every BASELINE §3 control (container pinning, `network: "none"`, `capDrop: ["ALL"]`, `pidsLimit`) depends on Docker being present. Without it, the single most important sandboxing layer of the architecture simply does not exist on the deployed system.

**Recommendation:** Add Docker as Prerequisite §4.6, with installation instructions (`brew install --cask docker`) and a post-install check (`docker info`). Add a verification step in `post-install-verify.sh` confirming Docker is running.

---

**FINDING-024**
**Severity:** � HIGH *(downgraded from CRITICAL by RED TEAM 2: this is a significant missing security control — ACIP defense is never applied — but the system still runs; functional breakage requires CRITICAL; missing security control is HIGH)*
**Domain:** Domain 4 — Critical Omissions
**File:** `GUIDE.md`
**Location:** §15.1 (line 1102)

**Summary:** §15.1 directs users to configure their SOUL.md system prompt file, but provides zero instructions on how to create it, where OpenClaw expects to find it, or how OpenClaw is configured to load it.

**Evidence:**
> `GUIDE.md` §15.1: *"Open your OpenClaw system prompt configuration (typically `~/.openclaw/SOUL.md`) and append the following inoculation block..."*
> No preceding `touch` command, no `openclaw config set` directive linking `SOUL.md` to an agent, no official documentation reference.

**Analysis:** `SOUL.md` is the primary defense against prompt injection per this guide. If users cannot create and link it correctly, the ACIP (Advanced Cognitive Inoculation Prompts) defense described as critical in §15.1 is simply never applied. The official docs do not confirm `SOUL.md` as a v2026.2.26 system prompt mechanism — this may itself be an undocumented/legacy path.

**Recommendation:** Add instructions to create the file, set its permissions (`chmod 600`), and configure the agent to use it. If `SOUL.md` is not a v2026.2.26 feature, replace with the correct system-prompt configuration method from the official docs.

---

**FINDING-025**
**Severity:** 🟠 HIGH
**Domain:** Domain 4 — Critical Omissions
**File:** `docs/THREAT-MODEL.md`
**Location:** §2, §3

**Summary:** The threat model has no entry for the CI/CD pipeline attack surface introduced in v2.0 (`UPDATE_WORKFLOW.md`). A compromised GitHub release page is a direct supply-chain injection vector into the update pipeline.

**Evidence:**
> `docs/THREAT-MODEL.md`: Covers network access, SSRF, credential theft, prompt injection — written before v2.0 CI/CD pipeline existed.
> `UPDATE_WORKFLOW.md` was introduced in v2.0 (`CHANGELOG.md`) but has no corresponding threat model entry.

**Analysis:** `pipeline-trigger.sh` fetches live release data from `api.github.com`. If the OpenClaw GitHub account is compromised, an attacker can publish a malicious release with a poisoned `body` JSON field. This gets written to `LATEST_RELEASE_NOTES.md` and fed to the sandboxed Architect Agent. Even with `network: "none"` inside the sandbox, the malicious content is already inside the trust boundary.

**Recommendation:** Add Threat 5 to THREAT-MODEL.md: "Supply Chain via CI/CD Update Pipeline" with mitigations covering: GPG signing of releases, hash verification of release body content, and HITL review of the diff before the Architect Agent processes it.

---

**FINDING-026**
**Severity:** 🟠 HIGH
**Domain:** Domain 4 — Critical Omissions
**File:** `GUIDE.md`
**Location:** §18 (lines 1398–1404)

**Summary:** FileVault (full-disk encryption) is categorized as "out of scope" but is a mandatory prerequisite for filesystem permission controls to have any practical effect.

**Evidence:**
> `GUIDE.md` §18: *"Disk Encryption: Ensure your entire macOS volume is encrypted using FileVault..."* — listed under "Advanced Security Considerations (Out of Scope)"

**Analysis:** Without FileVault, an adversary with physical access or who boots into macOS Recovery Mode can read `~/.openclaw/openclaw.json` (containing the plaintext auth token) and `~/.openclaw/.env` (containing `GEMINI_API_KEY`) — completely bypassing all POSIX permission controls. The official docs state: *"Use full-disk encryption on the gateway host."* This is not optional.

**Official Reference:** `https://docs.openclaw.ai/gateway/security#0-7-secrets-on-disk-what's-sensitive`

**Recommendation:** Promote FileVault to §4 Prerequisites with a verification step: `fdesetup status` must return `FileVault is On.` Any system where FileVault is off should be blocked from proceeding.

---

**FINDING-027**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 4 — Critical Omissions
**File:** `UPDATE_WORKFLOW.md`
**Location:** §2 Phase 1 (line 87)

**Summary:** The workflow states a macOS `launchd` timer runs the pipeline daily, but no LaunchAgent plist for this timer is provided in the repository.

**Evidence:**
> `UPDATE_WORKFLOW.md`: *"A macOS `launchd` timer executes the orchestrator script daily."*
> `examples/` directory: Contains only `launchd-agent-example.plist` (for Ollama, not the pipeline trigger).
> No `com.openclaw.pipeline-trigger.plist` exists anywhere in the repo.

**Analysis:** Without the plist, Phase 1 — the automated polling trigger — never executes. The entire multi-agent update pipeline is documented but un-deployable without manual setup, which the guide discourages.

**Recommendation:** Add `examples/com.openclaw.pipeline-trigger.plist` with a `StartCalendarInterval` entry for daily execution pointing to `pipeline-trigger.sh`.

---

**FINDING-028**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 4 — Critical Omissions
**File:** `GUIDE.md`
**Location:** §8.2

**Summary:** Scripts downloaded from the internet may be quarantined by macOS Gatekeeper (`com.apple.quarantine` xattr). No removal instruction is provided, meaning scripts may silently fail to execute on first run.

**Evidence:**
> `README.md`: `chmod +x deploy-openclaw.sh && ./deploy-openclaw.sh` — no quarantine removal step.

**Analysis:** macOS applies `com.apple.quarantine` to files downloaded via browser or `git clone`. A user who downloads the repo as a ZIP or clones it will find scripts blocked by Gatekeeper on first execution. The guide handles this for Homebrew (§5) but not for its own scripts.

**Recommendation:** Add after `chmod +x scripts/deploy-openclaw.sh`: `xattr -d com.apple.quarantine scripts/deploy-openclaw.sh 2>/dev/null || true` with an explanatory note.

---

### DOMAIN 5: Code & Script Quality

---

**FINDING-029**
**Severity:** 🔴 CRITICAL
**Domain:** Domain 5 — Script Quality
**File:** `GUIDE.md` §6.3, `examples/launchd-agent-example.plist`
**Location:** `GUIDE.md` lines 383–385

**Summary:** The Ollama LaunchAgent plist uses `$HOME` in XML string values. `launchd` does NOT perform shell variable expansion — `$HOME` is used literally as the path, causing log files to be written to a non-existent directory.

**Evidence:**
> `GUIDE.md` §6.3:
>
> ```xml
> <key>StandardOutPath</key>
> <string>$HOME/Library/Logs/Ollama/ollama.stdout.log</string>
> ```

**Analysis:** This is a well-known macOS launchd gotcha. `$HOME` is not expanded by launchd XML parsing. The logging paths will resolve to the literal string `$HOME/Library/...`. Ollama will fail to write logs, and the user will have no operational visibility into whether the daemon is running correctly. The correct approach is to use tilde `~`, which launchd DOES expand.

**Recommendation:** Replace `$HOME` with a hardcoded absolute path (safest — universally guaranteed to resolve correctly across all plist key types):

```xml
<string>/Users/YOUR_USERNAME/Library/Logs/Ollama/ollama.stdout.log</string>
```

Alternatively, tilde `~` works in `StandardOutPath` and `StandardErrorPath` specifically, but is not universally expanded across all plist keys, so hardcoding is the more portable practice. *(Note added by RED TEAM 2.)* Verify after loading: `launchctl dumpstate | grep -A2 com.ollama.serve`.

---

**FINDING-030**
**Severity:** 🟠 HIGH
**Domain:** Domain 5 — Script Quality
**File:** `UPDATE_WORKFLOW.md` Appendix A (`deploy-staged-update.sh`)
**Location:** Lines 133, 197

**Summary:** The `REPO_URL` variable is set to a markdown hyperlink literal rather than a plain URL, making the `git push` command non-functional.

**Evidence:**
> `UPDATE_WORKFLOW.md` Appendix A line 133:
>
> ```bash
> REPO_URL="[github.com/asoshnin/openclaw-hardened-macos.git](https://github.com/asoshnin/openclaw-hardened-macos.git)"
> ```
>
> Line 197: `git ... push "https://${REPO_URL}" "$BRANCH_NAME"`

**Analysis:** The markdown link syntax `[text](url)` is interpolated literally into the `git push` remote URL, producing an invalid URL. The push command will fail with a remote parse error. `pipeline-trigger.sh` line 236 has the identical issue.

**Recommendation:** Change to: `REPO_URL="github.com/asoshnin/openclaw-hardened-macos.git"`. Fix both `deploy-staged-update.sh` and `pipeline-trigger.sh`.

---

**FINDING-031**
**Severity:** 🟠 HIGH
**Domain:** Domain 5 — Script Quality
**File:** `UPDATE_WORKFLOW.md`
**Location:** Update workflow Agent 2 `execution_loop` (lines 75–78); `deploy-staged-update.sh` lines 159–167

**Summary:** The TOCTOU mitigation is incomplete. The Red Team agent hashes the draft files, but the deploy script only compares hash strings — never re-computing the hash from the actual files at deploy time.

**Evidence:**
> `deploy-staged-update.sh` lines 159–167:
>
> ```bash
> APPROVED_HASH=$(grep -o '"hash": *"[^"]*"' "$CERT_FILE" | cut -d'"' -f4)
> if [ "$USER_HASH" != "$APPROVED_HASH" ]; then exit 1; fi
> ```
>
> There is no `sha256sum` re-computation of the staging directory files.

**Analysis:** The script verifies that the user-supplied hash matches the stored cert hash only. It does NOT verify that the current files in `$STAGING_DIR` still produce that hash. An attacker who modifies the staged Markdown files but leaves `APPROVAL_CERTIFICATE.json` unchanged will bypass this check entirely. This means the entire TOCTOU protection is a false control.

**Recommendation:** Add a file re-hash step before committing:

```bash
CURRENT_HASH=$(find "$STAGING_DIR" -type f -name '*.md' | sort | xargs sha256sum | sha256sum | awk '{print $1}')
if [ "$CURRENT_HASH" != "$APPROVED_HASH" ]; then
  echo "❌ TOCTOU ALERT: Staging content changed since Red Team approval."
  exit 1
fi
```

---

**FINDING-032**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 5 — Script Quality
**File:** `scripts/post-install-verify.sh`
**Location:** Lines 37–41

**Summary:** The pf anchor verification uses `grep -q "127.0.0.1"` — too permissive; any line containing that IP (including comments) triggers a false PASS.

**Evidence:**
> `post-install-verify.sh` lines 37–41:
>
> ```bash
> if sudo pfctl -a openclaw-ollama -s rules 2>/dev/null | grep -q "127.0.0.1"; then
>     echo "PASSED: OpenClaw pf anchor rules are loaded and populated."
> ```

**Recommendation:** Strengthen the check:

```bash
ANCHOR_OUT=$(sudo pfctl -a openclaw-ollama -s rules 2>/dev/null)
if echo "$ANCHOR_OUT" | grep -q "pass in quick on lo0" && echo "$ANCHOR_OUT" | grep -q "block in quick"; then
```

---

**FINDING-033**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 5 — Script Quality
**File:** `scripts/post-install-verify.sh`
**Location:** Lines 60–68

**Summary:** `post-install-verify.sh` verifies file permissions but never validates the JSON content of `openclaw.json` — most critically, whether `gateway.host` is `127.0.0.1` and the tools deny list is intact.

**Analysis:** A user could have a correctly-permissioned `openclaw.json` that contains `"host": "0.0.0.0"` or an empty tools deny list. The script would report a clean audit. The most security-relevant fields are never checked.

**Recommendation:** Add a Python content validation block:

```bash
python3 -c "
import json, os
c = json.load(open(os.path.expanduser('~/.openclaw/openclaw.json')))
assert c.get('gateway', {}).get('host') == '127.0.0.1', 'gateway.host is not 127.0.0.1'
assert 'shell' in c.get('tools', {}).get('deny', []), 'shell is not in tools.deny'
print('✅ Config content validated.')
"
```

---

### DOMAIN 6: Document Integrity & Clarity

---

**FINDING-034**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 6 — Document Integrity
**File:** `GUIDE.md`
**Location:** §4.2 (lines 257–261)

**Summary:** Disk space requirements use LaTeX mathematical notation (`$$\approx 20$$ GB`) which renders as literal dollar signs and LaTeX syntax in standard GitHub Markdown.

**Evidence:**
> `GUIDE.md` §4.2: `` **Minimum required: $$\approx 20$$ GB free.** ``

**Analysis:** GitHub Flavored Markdown does not natively render LaTeX math. These lines display as `$$\approx 20$$ GB` verbatim — a formatting error that affects readability of a critical prerequisite section.

**Recommendation:** Replace all LaTeX math with plain text: `~20 GB`, `~4.7 GB`, `≥ 20 GB`.

---

**FINDING-035**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 6 — Document Integrity
**File:** `KNOWLEDGE_BASE.md`
**Location:** §"Part IV: Integration with Main Manual" (line 347)

**Summary:** The document contains an internal artifact reference `(file:47)` which is meaningless to external readers and exposes the document's drafting workflow.

**Evidence:**
> `KNOWLEDGE_BASE.md` line 347: *"This appendix complements **"OpenClaw on macOS M1 — Complete Manual"** (file:47)..."*

**Recommendation:** Replace `(file:47)` with a markdown link: `(see [GUIDE.md](../GUIDE.md))`.

---

**FINDING-036**
**Severity:** 🔵 LOW
**Domain:** Domain 6 — Document Integrity
**File:** `GUIDE.md`
**Location:** §15.4 section heading (line 1132)

**Summary:** An enterprise security document uses internet slang ("vibecoder friendly edition") in a section heading.

**Evidence:**
> `GUIDE.md` §15.4: `## **15.4 Secure Remote Access Architecture (Matrix + Tailscale): vibecoder friendly edition**`

**Recommendation:** Rename to: `## **15.4 Secure Remote Access Architecture (Matrix + Tailscale)**`

---

**FINDING-037**
**Severity:** 🔵 LOW
**Domain:** Domain 6 — Document Integrity
**File:** `GUIDE.md`
**Location:** §22 Version History (lines 1547–1551)

**Summary:** Two changelog entries share the same date for versions `1.1` and `2.0`, and both describe the same "Red team remediation" work — one appears to be a duplicate.

**Evidence:**
> `GUIDE.md` §22:
> `| 2.0 | 2026-03-01 | Red team remediation: Fixed pf anchor... |`
> `| 1.1 | 2026-03-01 | Red team remediation: Fixed pf anchor integration... |`

**Recommendation:** Reconcile with `CHANGELOG.md`. Remove the `1.1` entry or correct the date and description to reflect a genuinely distinct release.

---

### DOMAIN 7: Workflow & Operational Robustness

---

**FINDING-038**
**Severity:** 🟠 HIGH
**Domain:** Domain 7 — Workflow Robustness
**File:** `UPDATE_WORKFLOW.md`
**Location:** §2 Phase 3, Path A (line 110)

**Summary:** Path A (mobile/remote deployment) requires the OpenClaw Gateway to intercept a Matrix `/deploy <hash>` command and trigger a "Deployer function" — but no such skill, extension, or configuration is provided or documented anywhere in the repository.

**Evidence:**
> `UPDATE_WORKFLOW.md` Phase 3 Path A: *"Admin replies to the Matrix bot with `/deploy <hash>`. The OpenClaw Gateway intercepts this, triggers the Deployer function..."*
> No `deploy` skill, no `extensions/deploy/` directory, no configuration example exists in the repository.

**Analysis:** Path A is documented as a complete deployment mechanism but has zero implementation. Users who rely on mobile deployment will find it non-functional, reducing the stated dual-path resilience to a single path.

**Recommendation:** Either: (a) provide the OpenClaw skill/extension that implements the `/deploy` command handler; or (b) mark Path A as "Planned Future Feature (Not Yet Implemented)."

---

**FINDING-039**
**Severity:** 🟠 HIGH
**Domain:** Domain 7 — Workflow Robustness
**File:** `scripts/pipeline-trigger.sh`
**Location:** Line 265

**Summary:** Release notes are extracted from the GitHub API response using `grep '"body":'` — producing a raw JSON-encoded string, not Markdown — and fed to the Architect Agent.

**Evidence:**
> `pipeline-trigger.sh` line 265:
>
> ```bash
> echo "$LATEST_RELEASE_DATA" | grep '"body":' > "$STAGING_DIR/LATEST_RELEASE_NOTES.md"
> ```

**Analysis:** The extracted line will be the raw JSON: `"body": "## What's new\n- Feature A"` — with literal `\n` escape sequences, not real line breaks. The Architect Agent receives garbled input.

**Recommendation:** Use `jq -r '.body'` instead:

```bash
echo "$LATEST_RELEASE_DATA" | jq -r '.body' > "$STAGING_DIR/LATEST_RELEASE_NOTES.md"
```

---

### DOMAIN 8: Threat Model Completeness

---

**FINDING-040**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 8 — Threat Model
**File:** `docs/THREAT-MODEL.md`
**Location:** §2, §3

**Summary:** The threat model has no entry for the CI/CD pipeline attack surface introduced in v2.0. (See related FINDING-025 in Domain 4.)

**Recommendation:** Add Threat 5: "Supply Chain via CI/CD Update Pipeline." Mitigations: GPG release signing, content hashing before agent ingestion, HITL diff review.

---

**FINDING-041**
**Severity:** 🟡 MEDIUM
**Domain:** Domain 8 — Threat Model
**File:** `docs/THREAT-MODEL.md`
**Location:** §2 Threat 2

**Summary:** The threat model does not address the Ollama API having no authentication on port `11434`. Any local process running as the same macOS user can query Ollama directly without any credential.

**Evidence:**
> `THREAT-MODEL.md` §2 Threat 2 only covers OpenClaw's authenticated API.
> `KNOWLEDGE_BASE.md` line 91: *"Ollama binds to `0.0.0.0` by default with no authentication. 175,000+ instances were found publicly exposed"* — but this is absent from the formal threat model.

**Analysis:** The pf anchor blocks external access, but any same-user local process can call `http://127.0.0.1:11434/api/generate` freely. This is a local SSRF / insider threat vector. The threat model's accepted risks do not acknowledge it.

**Recommendation:** Add Threat 6: "Unauthenticated Ollama API." Accept the risk given local-only binding (document it explicitly). Consider recommending a reverse proxy with basic auth in front of Ollama for high-sensitivity deployments.

---

**FINDING-042**
**Severity:** 🔵 LOW
**Domain:** Domain 8 — Threat Model
**File:** `docs/THREAT-MODEL.md`
**Location:** §3 Out of Scope / Accepted Risks

**Summary:** The threat model's accepted risks do not include macOS App Nap silently terminating the OpenClaw daemon, leaving users unaware that their security gateway is offline.

**Evidence:**
> `GUIDE.md` §11c explicitly discusses macOS App Nap killing the daemon.
> `THREAT-MODEL.md` §3: Does not list App Nap as an accepted risk.

**Recommendation:** Add to §3: *"App Nap / Power Management: macOS may suspend the LaunchAgent during long idle periods. Use `caffeinate` for long-running jobs (see GUIDE §11c). Accepted operational risk for single-user local deployments."*

---

## 3. Consistency Matrix

| Issue | File A | Claim A | File B | Claim B | Correct Answer |
|---|---|---|---|---|---|
| `openclaw.json` permission | `GUIDE.md` §9.2, §10.4 | `chmod 400` | `THREAT-MODEL.md` §3, Official Docs | `chmod 600` | **`600`** (official docs) |
| `openclaw.json` permission | `post-install-verify.sh` L62 | Checks for `400` | Official docs | Mandates `600` | **`600`** |
| Default gateway port | `GUIDE.md`, all scripts | Port `3000` | Official docs `docs.openclaw.ai/gateway/security` | Default `18789` | **`18789`** (unless explicitly overridden) |
| Cloud model name | `KNOWLEDGE_BASE.md` §3 | `Kimi K2.5` | `GUIDE.md`, `CHANGELOG.md`, all scripts | `gemini-3.1-pro-preview` | **`gemini-3.1-pro-preview`** |
| Latest release version | `KNOWLEDGE_BASE.md` URL table | `2026.2.19` | All other docs | `2026.2.26` | **`2026.2.26`** |
| `agents.defaults.model` type | `GUIDE.md` §9.2, all scripts | String | Official docs config reference | Object `{primary: "..."}` | **Object form** |
| GitHub org | `GUIDE.md` §21 | `openclawhq/openclaw` | `README.md`, `KNOWLEDGE_BASE.md`, `pipeline-trigger.sh` | `openclaw/openclaw` | **Unverified — requires manual check** |
| `gateway.mode` key | `GUIDE.md` §9.4 | `gateway.mode = local` | Official docs | `gateway.bind = "loopback"` | **`gateway.bind: "loopback"`** |
| Sandbox `workspaceAccess` | `BASELINE.md` §3 | MUST be `"ro"` | `UPDATE_WORKFLOW.md` Agent 1 | `"rw"` | **Documented exception required** |
| Ollama restart command | `GUIDE.md` §6.3 | Do NOT use `brew services` | `GUIDE.md` §13.2 | `brew services restart ollama` | **Use `launchctl` cycle** |

---

## 4. Remediation Roadmap

### 🔴 Immediate (Block Release)

*Exploitable vulnerabilities or critical functional breakage.*

| # | Finding | Action |
|---|---|---|
| 1 | FINDING-001 | Replace port `3000` with `18789` everywhere, or explicitly override to `3000` in config |
| 2 | FINDING-003 | Change `chmod 400 openclaw.json` → `chmod 600`; remove Unlock-Modify-Lock |
| 3 | FINDING-010 | Fix BASELINE vs. GUIDE token-storage contradiction; implement env-var substitution |
| 4 | FINDING-011 | Stop printing auth token to stdout |
| 5 | FINDING-002 | Fix `agents.defaults.model` to object form `{primary: "..."}` |
| 6 | FINDING-004 | Fix `model['name']` → `model['primary']` in §9.3 verification script |
| 7 | FINDING-023 | Add Docker as prerequisite §4.6 with install + verify steps |
| 8 | FINDING-029 | Fix `$HOME` non-expansion in LaunchAgent plist — use `~` |

### 🟠 Short-Term (Next Sprint)

*Significant errors, security regressions, inconsistencies.*

| # | Finding | Action |
|---|---|---|
| 9 | FINDING-006 | Replace `gateway.mode local` with `gateway.bind loopback` |
| 10 | FINDING-009 | Replace `brew services restart ollama` in §13.2 with `launchctl` cycle |
| 11 | FINDING-012 | Remove URL token auto-login (Method 2) from §11b |
| 12 | FINDING-013 | Remove `-p` password flags from Matrix registration commands |
| 13 | FINDING-014 | Add pf syntax validation to `deploy-openclaw.sh` |
| 14 | FINDING-015 | Add `discovery.mdns.mode: "off"` to all config templates |
| 15 | FINDING-016 | Fix unclosed code block fence in §15.6 Incident Response |
| 16 | FINDING-019 | Resolve `openclaw` vs `openclawhq` GitHub org ambiguity |
| 17 | FINDING-025 | Add CI/CD pipeline attack surface to THREAT-MODEL.md |
| 18 | FINDING-026 | Promote FileVault to mandatory prerequisite in §4 |
| 19 | FINDING-030 | Fix markdown hyperlink in `REPO_URL` variable (both workflow scripts) |
| 20 | FINDING-031 | Add SHA-256 file re-computation to deploy script for real TOCTOU protection |
| 21 | FINDING-038 | Implement `/deploy` Matrix skill or mark Path A as unimplemented |

### 🟡 Medium-Term (Next Version)

| # | Finding | Action |
|---|---|---|
| 22 | FINDING-007 | Fix §9.4 section numbering (1, 3, 3 → 1, 2, 3) |
| 23 | FINDING-008 | Update KB §3 model name and release version |
| 24 | FINDING-017 | Remove or implement MELON framework reference |
| 25 | FINDING-018 | Standardize `openclaw.json` permission to `600` everywhere |
| 26 | FINDING-021 | Add formal deviation note for `workspaceAccess: "rw"` in UPDATE_WORKFLOW |
| 27 | FINDING-022 | Add mDNS disable to `deploy-openclaw.sh` |
| 28 | FINDING-024 | Document SOUL.md creation, permissions, and agent linkage |
| 29 | FINDING-027 | Add `com.openclaw.pipeline-trigger.plist` to `examples/` |
| 30 | FINDING-032 | Strengthen pf anchor check in `post-install-verify.sh` |
| 31 | FINDING-033 | Add JSON content validation to `post-install-verify.sh` |
| 32 | FINDING-039 | Fix release notes extraction to use `jq -r '.body'` |
| 33 | FINDING-041 | Add unauthenticated Ollama API to threat model |

### 🔵 Housekeeping

| # | Finding | Action |
|---|---|---|
| 34 | FINDING-005 | Justify npm vs curl installer choice or add official installer note |
| 35 | FINDING-020 | Clarify Ollama provider schema against config reference |
| 36 | FINDING-028 | Add `xattr` quarantine removal for downloaded scripts |
| 37 | FINDING-034 | Replace LaTeX math notation with plain text |
| 38 | FINDING-035 | Remove `(file:47)` internal artifact reference from KB |
| 39 | FINDING-036 | Remove "vibecoder friendly edition" from §15.4 heading |
| 40 | FINDING-037 | Reconcile GUIDE §22 version history with CHANGELOG.md |
| 41 | FINDING-040 | Add CI/CD pipeline attack surface to threat model (overlaps FINDING-025) |
| 42 | FINDING-042 | Add App Nap as accepted risk in THREAT-MODEL.md |

---

## 5. Commendations

The following practices are genuinely excellent and should be preserved and replicated:

| Practice | Location | Why It's Excellent |
|---|---|---|
| `umask 077` subshell for token generation | `GUIDE.md` §9.2, `token-generator.sh` | Ensures temporary files inherit restrictive permissions — correct POSIX hygiene |
| `<<< "$AUTH_TOKEN"` herestring for Python stdin | `GUIDE.md` §9.2 Option B | Avoids `argv`/process list token exposure — non-obvious, correct mitigation |
| Dual-layer firewall (app binding + `pf` anchor) | `GUIDE.md` §10, `pf-anchor-openclaw.rules` | Defense-in-depth: application binding as primary, kernel-level pf as failsafe |
| IPv6 loopback coverage in pf rules | `pf-anchor-openclaw.rules` line 11 | Covering `::1` alongside `127.0.0.1` prevents a common IPv6 bypass vector |
| `jq --arg` for safe token injection | `GUIDE.md` §14.1 | Prevents shell injection of token value into the jq expression |
| Base64 `http.extraHeader` for git auth | `deploy-staged-update.sh` lines 196–197 | Prevents token from appearing in `.git/config` or process monitors |
| `unset` after secret use | `deploy-staged-update.sh` lines 201–202 | Explicitly flushes PAT from bash environment — correct operational hygiene |
| HITL break-glass protocol with audit logging | `BASELINE.md` §6 | Production-grade escalation model with cryptographic hash of approved payload |
| Staging directory locked to `700` | `UPDATE_WORKFLOW.md` §2 Phase 1 | Correct TOCTOU prevention during async pipeline execution |
| Explicit warning against `brew services` | `GUIDE.md` §6.3 | The `ps eww` safety test to expose env injection failure is pedagogically excellent |

---

## 6. Independent Verification & Sign-Off

**RED TEAM 2 Review Date:** 2026-03-03

### Verification Verdict: ✅ CONDITIONAL SIGN-OFF

All core findings independently verified against live `docs.openclaw.ai` v2026.2.26 documentation and direct evidence from repository files. The following amendments were applied:

| Amendment | Finding | Change |
|---|---|---|
| Severity downgrade | FINDING-002 | CRITICAL → HIGH (string vs. object schema: pending runtime confirmation) |
| Severity downgrade | FINDING-024 | CRITICAL → HIGH (missing control, not functional breakage) |
| Caveat added | FINDING-006 | `gateway.mode` may silently no-op rather than error — requires runtime validation |
| Recommendation strengthened | FINDING-029 | Hardcoded absolute path is safer than tilde `~` across all plist key types |

**Additional omissions noted by RED TEAM 2 (not incorporated as formal findings per scope):**

- `post-install-verify.sh` lacks `set -euo pipefail` — a failed `sudo pfctl` call does not abort the script, risking misleading PASS output.
- `CONTRIBUTING.md` was not reviewed in the original report; should be explicitly noted as reviewed-and-clear or out-of-scope.

**Final Assessment:** The three lead CRITICAL findings (FINDING-001: wrong port, FINDING-003: wrong permission, FINDING-010: BASELINE-GUIDE token contradiction) are verified without qualification and backed by verbatim quotes from the official security documentation. The remediation roadmap priority order is sound. **This report is fit for publication and remediation action.**

*Signed — RED TEAM 2, Independent Verification, 2026-03-03*

---

*Original report compiled by RED TEAM 1. All findings grounded against `docs.openclaw.ai` v2026.2.26 official documentation and direct evidence from `openclaw-hardened-macos` repository files. Original audit date: 2026-03-03.*

---

## 7. Final Independent Verification & Sign-Off (RED TEAM 4)

**RED TEAM 4 Review Date:** 2026-03-03

### Verification Verdict: ✅ UNCONDITIONAL SIGN-OFF

All 42 findings from the original report (including CRITICAL, HIGH, MEDIUM, LOW, and INFO severities) have been systematically hunted down and remediated by the engineering and verification teams. The codebase now precisely reflects the strict security hygiene and technical correctness mandated by the official OpenClaw `v2026.2.26` documentation.

**Final Confirmed Fixes (Post-RT3):**

- `README.md` no longer lists the incorrect `chmod 400` POSIX permission.
- The `xattr -d com.apple.quarantine` step has been correctly added to `README.md` for `deploy-openclaw.sh`, resolving a silent failure vector (F-028).
- All token echo commands and stdout leaks have been successfully purged from the codebase.
- All file permissions correctly enforce `chmod 600` for immutability without breaking usability.
- The `gateway.bind loopback`, token env-var substitution, JSON content validation, and `pf` pre-flight checks are all verified operational.

**Final Assessment:** The `openclaw-hardened-macos` repository has attained its stated goal. It is a professionally hardened, Zero-Trust deployment architecture. The threat model is comprehensive, the instructions are unambiguous, and the automated scripts are robust against common failure states (TOCTOU, silent firewalls, malformed plists).

**This version is fully signed off for production deployment.**

*Signed — RED TEAM 4, Final Verification Authority, 2026-03-03*
