# OpenClaw Hardened Installation Standard (macOS Apple Silicon)

The defense-in-depth standard for deploying OpenClaw and Ollama safely on macOS.

Most OpenClaw installation guides optimize for **speed** (10 minutes to install). This guide optimizes for **security** (30 minutes to install).

Following standard tutorials often leaves your local AI infrastructure vulnerable: services bound to `0.0.0.0`, unauthenticated APIs, and no internal firewalling. This repository provides a professional-grade, red-team-audited deployment manual.

## The 4-Layer Security Architecture

Apple's Gatekeeper protects against malicious binaries, but it does **not** act as an internal network firewall. This deployment implements a true defense-in-depth architecture:

1.  **Application Layer:** Strict service bindings to `127.0.0.1` and `::1` only.
2.  **Authentication Layer:** 256-bit secure token generation via `umask 077` subshells to prevent credential leakage.
3.  **Firewall Layer:** Native macOS `pf` firewall anchors to strictly block unauthorized local access from other processes or users.
4.  **Filesystem Layer:** Restrictive POSIX permissions (`chmod 700/600`) on config directories and sensitive memory files.

## Documentation & Manuals

### 1. Hardened Installation Guide
The complete, step-by-step installation manual for setting up the environment.
👉 **[Read the Full Hardened Guide (GUIDE.md)](GUIDE.md)**

### 2. Security Operations Knowledge Base
A curated intelligence database containing Tiered URL trust levels, Red Team findings on Indirect Prompt Injection (IPI), and incident response protocols.
👉 **[Read the Knowledge Base (KNOWLEDGE_BASE.md)](KNOWLEDGE_BASE.md)**

## OpenClaw SecOps Assistant

You can deploy a specialized AI agent to assist in managing, auditing, and troubleshooting your deployment. This assistant is designed to operate under a Zero-Trust mandate.

👉 **[Assistant Setup & Metaprompt (ASSISTANT_METAPROMPT.md)](ASSISTANT_METAPROMPT.md)**

*Note: This metaprompt is optimized for Gemini GEMS and similar RAG-capable platforms. It leverages this repository's manuals as its primary source of truth.*

## Automation Scripts

⚠️ **SECURITY WARNING: Never execute scripts without prior manual inspection. Review all code in the `/scripts/` directory before running it in a terminal.**

If you are already familiar with the architecture, you can utilize the following:

* **pf-anchor-openclaw.rules:** The copy-paste ready `pf` anchor ruleset.
* **token-generator.sh:** Securely generates your 256-bit auth token using high-entropy sources.
* **post-install-verify.sh:** Automates the auditing of your `lsof` bindings and `pfctl` rules to ensure compliance with the 4-layer architecture.

## Contributing

This is a living standard. We welcome Pull Requests for new macOS versions (e.g., Sequoia), additional architectural hardening, or ports to Linux/Windows environments. See **CONTRIBUTING.md**.
