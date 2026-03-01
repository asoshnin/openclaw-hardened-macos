# OpenClaw Hardened Installation Standard (macOS Apple Silicon)

> **The defense-in-depth standard for deploying OpenClaw and Ollama safely on macOS.**

Most OpenClaw installation guides optimize for **speed** (10 minutes to install). This guide optimizes for **security** (30 minutes to install).

Following standard tutorials often leaves your local AI infrastructure vulnerable: services bound to `0.0.0.0`, unauthenticated APIs, and no internal firewalling. This repository provides a professional-grade, red-team-audited deployment manual.

## The 4-Layer Security Architecture

Apple's Gatekeeper protects against malicious binaries, but it does **not** act as an internal network firewall. We implement a true defense-in-depth architecture:

1. **Application Layer:** Strict service bindings to `127.0.0.1` and `::1` only.
2. **Authentication Layer:** 256-bit secure token generation via `umask 077` subshells.
3. **Firewall Layer:** Native macOS `pf` firewall anchors to strictly block unauthorized local access.
4. **Filesystem Layer:** Restrictive `chmod 700/600` permissions on config directories and sensitive memory files.

## Quick Start

The complete, step-by-step hardened installation manual is located here:
👉 **[Read the Full Hardened Guide (GUIDE.md)](./GUIDE.md)**

### Automation Scripts

If you are already familiar with the architecture, you can use the provided scripts in the `/scripts/` directory:
* `pf-anchor-openclaw.rules`: The copy-paste ready `pf` anchor ruleset.
* `token-generator.sh`: Securely generates your 256-bit auth token.
* `post-install-verify.sh`: Automates the auditing of your `lsof` bindings and `pfctl` rules.

## Contributing

This is a living standard. We welcome Pull Requests for new macOS versions (e.g., Sequoia), additional architectural hardening, or ports to Linux/Windows environments. See `CONTRIBUTING.md`.

---
*Security is not an afterthought. It is the foundation of local AI.*
