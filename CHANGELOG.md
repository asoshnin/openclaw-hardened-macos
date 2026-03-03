# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-03-03

### Security

- **RED TEAM Audit & Remediation:** Full adversarial audit conducted against official OpenClaw `v2026.2.26` documentation. 42 findings identified (8 CRITICAL, 12 HIGH, 11 MEDIUM, 7 LOW, 4 INFO) and reviewed by 3 independent RED TEAM panels. All findings remediated. Full report: `docs/audits/2026-03-03_RED_TEAM_REPORT.md`.

### Fixed

- `openclaw.json` permission corrected from `chmod 400` → `chmod 600` per official docs (FINDING-003, FINDING-018)
- Auth token now stored exclusively in `.env` via `${OPENCLAW_GATEWAY_TOKEN}` env-var substitution; all stdout token echoes removed (FINDING-010, FINDING-011)
- `agents.defaults.model` corrected to object form `{"primary": "google/gemini-3.1-pro-preview"}` (FINDING-002)
- `gateway.bind loopback` replaces undocumented `gateway.mode local` across all scripts and docs (FINDING-006)
- `discovery.mdns.mode: "off"` added to all config templates to correctly disable Bonjour (FINDING-015, FINDING-022)
- `pf` syntax pre-validation added before `pfctl -f` to prevent silent firewall disable (FINDING-014)
- TOCTOU false control eliminated; SHA-256 file re-hash added at deploy time (FINDING-031)
- `$HOME` in LaunchAgent plist replaced with hardcoded absolute path (FINDING-029)
- Docker added as mandatory prerequisite with verification step in `post-install-verify.sh` (FINDING-023)
- JSON config content validation added to `post-install-verify.sh` (FINDING-033)
- `pf` anchor check strengthened to verify both `pass` and `block` rules (FINDING-032)
- Path A (`/deploy` Matrix command) documented as Planned Future Feature — not yet implemented (FINDING-038)
- CI/CD update pipeline attack surface documented in `THREAT-MODEL.md` as Threat 5 (FINDING-025, FINDING-040)
- Unauthenticated Ollama API documented as accepted risk in `THREAT-MODEL.md` (FINDING-041)
- App Nap power-management risk documented in `THREAT-MODEL.md` (FINDING-042)
- MELON framework annotated as research/future concept not in official v2026.2.26 docs (FINDING-017)
- Stale model name `Kimi K2.5` corrected to `gemini-3.1-pro-preview` in `KNOWLEDGE_BASE.md` (FINDING-008)
- Markdown hyperlink bug in `REPO_URL` bash variable corrected in both workflow scripts (FINDING-030)
- Release notes extraction updated from `grep '"body":'` to `jq -r '.body'` (FINDING-039)
- `xattr -d com.apple.quarantine` step added to deployment instructions (FINDING-028)
- `examples/com.openclaw.pipeline-trigger.plist` added for daily pipeline trigger (FINDING-027)
- README.md updated to remove deprecated `chmod 400` and `Unlock-Modify-Lock` references

## [2.0.0] - 2026-03-03

### Added

- **CI/CD ChatOps Pipeline:** Introduced `UPDATE_WORKFLOW.md` detailing a multi-agent, Zero-Trust asynchronous state machine for safe documentation updates.
- **Orchestration Scripts:** Added `pipeline-trigger.sh` for host-level update polling and Matrix webhook dispatching, and `deploy-staged-update.sh` for secure desktop-level authorization.
- **TLS Reverse Proxy:** Integrated `caddy` into the remote access architecture to provide automatic Tailscale TLS certificates, ensuring compliance with iOS App Transport Security (ATS).
- **Native Matrix API:** Upgraded the pipeline orchestrator to use native Matrix Client-Server API calls (`PUT /_matrix/client/v3/rooms/...`) instead of generic webhooks.

### Changed

- **Cloud Model Baseline:** Updated the default cloud model across all documentation and scripts from `kimi-k2.5` to `gemini-3.1-pro-preview`.
- **Vibe Coder UX:** Completely rewrote Section 15.4 of the manual to explain the Matrix/Tailscale/Caddy architecture in plain, accessible English without compromising security mathematics.
- **FAQ & Plist:** Synchronized `FAQ.md` and `launchd-agent-example.plist` to reflect the new Caddy TLS architecture and correct logging paths.

### Security

- **Supply Chain Pinning:** Explicitly pinned OpenClaw global npm installations to `openclaw@2026.2.26` to mitigate `@latest` tag poisoning risks.
- **Agent Sandboxing:** Enforced strict physical resource boundaries on AI Agents (`capDrop: ["ALL"]`, `readOnlyRoot: true`, `memory: 512m`, `network: "none"`) to prevent prompt-injection fork bombs during the drafting phase.
- **TOCTOU Mitigation:** Enforced octal `700` permissions on the `~/.openclaw/staging/` directory to prevent local tampering while awaiting human deployment approval.
- **Registration Lock:** Enforced `enable_registration: false` in the Matrix Synapse configuration to prevent rogue account creation on the Tailscale mesh.

### Fixed

- **Fast-Track Script:** Fixed a critical execution gap in `deploy-openclaw.sh` by adding the missing Node.js and OpenClaw runtime installation steps.
- **Workspace Bug:** Automated the `sed` patching of the `@openclaw/matrix` pnpm workspace syntax bug during plugin installation.

## [1.0.0] - 2026-02-15

### Added

- Initial release of the OpenClaw Zero-Trust Deployment Standard for macOS Apple Silicon.
- 4-Layer Security Architecture (Application bindings, Secrets segregation, Firewall layer, Config immutability).
- Automated deployment script (`deploy-openclaw.sh`).
- Hardware-specific `pf` firewall loopback anchor rules.
- Secure 256-bit token generation via `umask 077` subshells (`token-generator.sh`).
