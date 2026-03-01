# Contributing to the OpenClaw Hardened Standard

Thank you for your interest in improving the security of local AI deployments! This repository is designed to be the definitive, defense-in-depth standard for running OpenClaw and Ollama. 

## Our Philosophy: Security Over Convenience
Most tutorials sacrifice operational security to save the user 5 minutes of setup time. **We do not.** When submitting a Pull Request, please ensure your changes adhere to our core philosophy:
1. **Never expose local services:** We do not bind to `0.0.0.0` or `*`.
2. **Never leak secrets:** Tokens and keys must not touch the disk in plaintext outside of heavily restricted (`chmod 600`) configuration files.
3. **Assume compromise:** Every layer (App, Auth, Firewall, Filesystem) assumes the other layers might fail.

## How You Can Help
We actively welcome Pull Requests for the following areas:
* **OS Updates:** Testing and updating the guide for new macOS releases (e.g., Sequoia).
* **Cross-Platform Standards:** Translating these defense-in-depth principles (loopback binding, firewall anchors, subshell secret generation) into equivalent standards for **Linux (iptables/ufw)** or **Windows (Windows Defender Firewall/PowerShell)**.
* **Automation:** Improving the bash scripts for robust error handling across different local environments.

## Submitting a Pull Request
1. Fork the repository.
2. Create a feature branch (`git checkout -b feature/linux-hardening-guide`).
3. Ensure any new scripts use strict operational security (e.g., `set -e`, `umask 077` for secrets).
4. Update the `CHANGELOG.md` with a brief description of your addition.
5. Open a Pull Request detailing the *Threat Model* your change addresses.

## Vulnerability Reporting
If you discover a flaw in this hardening guide that exposes the user to immediate risk (e.g., a bypass in the `pf` ruleset), **do not open a public issue.**

Please email the repository maintainer directly or use GitHub's private vulnerability reporting feature to ensure responsible disclosure before the fix is pushed.
