# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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