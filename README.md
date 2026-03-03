# OpenClaw Zero-Trust Deployment Standard (macOS Apple Silicon)

The defense-in-depth standard for deploying OpenClaw and Ollama safely on macOS. 

Most OpenClaw installation guides optimize for **speed** (10 minutes to install). This guide optimizes for **security** (30 minutes to install). 

Following standard tutorials often leaves your local AI infrastructure vulnerable: services bound to `0.0.0.0`, unauthenticated APIs, plaintext cloud credentials, and no internal firewalling. This repository provides a professional-grade, Red-Team-audited deployment manual specifically tailored for OpenClaw `2026.2.26` and Apple Silicon.

## The 4-Layer Security Architecture

Apple's Gatekeeper protects against malicious binaries, but it does **not** act as an internal network firewall. This deployment implements a true Zero-Trust architecture featuring a hybrid local (Ollama) and cloud (Google Gemini) fallback system:

1.  **Application Layer:** Strict service bindings to `127.0.0.1` and `::1` only, managed securely via macOS `LaunchAgents`.
2.  **Authentication & Secrets:** 256-bit secure token generation via `umask 077` subshells, and strict `.env` segregation to keep cloud API keys out of main configuration files.
3.  **Firewall Layer:** Native macOS `pf` firewall anchors to strictly block unauthorized local access from other processes or users on the same machine.
4.  **Configuration Immutability:** Restrictive POSIX permissions (`chmod 400/600`) on config directories to prevent configuration drift or unauthorized tampering.

## Documentation & Manuals

This repository is structured around a strict governance hierarchy. Start with the Baseline to understand the architecture, use the Guide to deploy it, and consult the Knowledge Base for daily operations.

### 1. Foundational Security Baseline (The "Constitution")
The declarative, machine-readable specification written with strict RFC 2119 compliance. It defines the immutable boundaries of the system, Docker sandboxing limits (`network: "none"`, resource constraints), and the official Break-Glass protocol for the agent.
👉 **[Read the Security Baseline (BASELINE.md)](BASELINE.md)**

### 2. Hardened Installation Guide (The "Manual")
The complete, step-by-step installation manual for setting up the environment. It covers the "Unlock-Modify-Lock" workflow required to manage a hardened OpenClaw instance on Apple Silicon.
👉 **[Read the Full Hardened Guide (GUIDE.md)](GUIDE.md)**

### 3. Security Operations Knowledge Base (The "Ops & RAG DB")
A curated intelligence database containing Tiered URL trust levels, Red Team findings on Indirect Prompt Injection (IPI), and incident response protocols. *Note: Kept strictly separated from the Baseline to prevent cognitive poisoning during LLM RAG ingestion.*
👉 **[Read the Knowledge Base (KNOWLEDGE_BASE.md)](KNOWLEDGE_BASE.md)**

### 4. Automated Update Workflow (The "CI/CD Pipeline")
Details the strict, asynchronous, multi-agent ChatOps state machine used to automatically draft, audit, and deploy Zero-Trust updates to this repository natively via Matrix or local CLI.
👉 **[Read the Update Workflow (UPDATE_WORKFLOW.md)](UPDATE_WORKFLOW.md)**

## OpenClaw SecOps Assistant

You can deploy a specialized AI agent to assist in managing, auditing, and troubleshooting your deployment. This assistant is designed to operate under a Zero-Trust mandate.

👉 **[Assistant Setup & Metaprompt (ASSISTANT_METAPROMPT.md)](ASSISTANT_METAPROMPT.md)**

*Note: This metaprompt is optimized for Gemini GEMS and similar RAG-capable platforms. It leverages this repository's manuals as its primary source of truth.*

## 🚀 Fast-Track Deployment Script

⚠️ **SECURITY WARNING: Never execute scripts without prior manual inspection. Review all code in the `/scripts/` directory before running it.**

For advanced users who already understand the Zero-Trust architecture outlined in the guide, we provide a single-pass, fully automated deployment script. It handles the LaunchAgents, model pulls (`llama3:8b`, `deepseek-coder-v2:lite`), JSON configuration schema, `.env` generation, and `pf` firewall rules automatically.

**To run the deployment:**
```bash
cd scripts/
chmod +x deploy-openclaw.sh
./deploy-openclaw.sh