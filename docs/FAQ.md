# Frequently Asked Questions (FAQ)

## Security & Architecture

**Q: Why isn't Apple's Gatekeeper enough to protect my OpenClaw installation?**
* Apple's Gatekeeper protects against malicious binaries.
* However, it does not act as an internal network firewall.

**Q: Why do I need to configure the macOS `pf` firewall if I already bound my services to `127.0.0.1`?**
* The `pf` firewall provides a defense-in-depth layer. 
* If a misconfiguration or software update causes a service to bind to all interfaces, the firewall blocks external access.

**Q: What is Prompt Injection and why is it a risk for local LLMs?**
* If OpenClaw is instructed to summarize a webpage, and that webpage contains hidden text stating malicious instructions, the assistant may blindly comply.
* To mitigate this, you must implement Advanced Cognitive Inoculation Prompts (ACIP) and restrict skill execution.

## Privacy & Cloud Models

**Q: How can I safely use cloud models like `kimi-k2.5`?**
* When `kimi-k2.5` (cloud) is the active model, your prompts and code are transmitted directly by the OpenClaw gateway to Moonshot AI servers.
* Do not send passwords, API keys, authentication tokens, proprietary source code, or PII to cloud models.
* For sensitive work, use a local, fully offline model like `deepseek-coder-v2:lite`.

## Remote Access

**Q: How can I safely access my OpenClaw setup remotely from my phone?**
* Exposing an OpenClaw webhook directly to the public internet via port forwarding is a critical risk.
* Instead, combine an overlay network with End-to-End Encryption (E2EE).
* Create a secure, WireGuard-backed Mesh VPN using Tailscale. * Deploy a local Matrix homeserver bound only to your Tailscale IP.

## Troubleshooting

**Q: What should I do if my Ollama service fails to start?**
* Check if port 11434 is already in use by running `lsof -i :11434` to find the process.
* Verify the LaunchAgent plist has `127.0.0.1:11434` (no `http://` scheme) to rule out an `OLLAMA_HOST` misconfiguration.
* Ensure you have >= 20 GB free by checking `df -h ~`.

**Q: OpenClaw fails to start, what should I check?**
* Check if port 3000 is already in use by running `lsof -i :3000`.
* Validate your configuration JSON for syntax errors using `python3 -m json.tool ~/.openclaw/openclaw.json`.
