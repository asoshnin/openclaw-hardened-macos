# **Foundational Security and Architecture Baseline: OpenClaw v2026.2.26**

## **1\. Overview and Operational Philosophy**

This document establishes the definitive, machine-and-human-readable technical specification for OpenClaw orchestrator nodes operating within an enterprise infrastructure.

* The fundamental operational philosophy MUST be "Zero-Trust by Default."  
* The execution environment MUST strictly target macOS Apple Silicon (M1/M2/M3/M4) hardware to leverage unified memory subsystems for low-latency Large Language Model (LLM) inference.  
* All deployments MUST adhere to the architectural paradigms established in the OpenClaw v2026.2.26 release, which explicitly mandates thread-bound agents, comprehensive external secrets management, and WebSocket-first transport layer optimizations.  
* Traditional perimeter-based security models are categorically obsolete for autonomous AI agents; therefore, defense-in-depth MUST be enforced strictly across the Application, Authentication, Firewall, and Filesystem layers.

## **2\. Gateway Control Plane & Host Hardening**

The OpenClaw Gateway acts as the central API orchestrator and MUST operate under strict host-level isolation.

* The Gateway daemon MUST be managed natively by the macOS `launchd` service manager as a persistent user service.  
* The application MUST explicitly bind its network listeners exclusively to the local loopback interfaces (`127.0.0.1` for IPv4 and `::1` for IPv6).  
* The system MUST implement an OpenBSD `pf` firewall anchor.  
* This firewall anchor MUST contain strict rules to block all non-loopback inbound traffic attempting to reach the OpenClaw Gateway (port `3000`) and the local Ollama inference server (port `11434`).  
* Configuration files, specifically `openclaw.json`, MUST be locked to octal permission `400` (read-only for the owner) to ensure absolute immutability from both accidental commands and malicious scripts.

## **3\. Agent Runtime & Docker Sandboxing Constraints**

To mitigate the catastrophic blast radius of a compromised agent and prevent local Denial of Service (DoS) attacks via memory starvation on Apple Silicon's Unified Memory Architecture (UMA), the Agent Runtime MUST be physically decoupled and aggressively constrained.

* All dynamic tool execution and untrusted data parsing MUST be routed into a network-isolated, ephemeral Docker container.  
* The execution environment MUST mandate cryptographic digest pinning for the container image to prevent supply chain poisoning. The REQUIRED image specification format is `openclaw-sandbox:bookworm-slim@sha256:<hash>`. Mutable tags like `latest` SHALL NOT be used.  
* The sandbox configuration MUST enforce a `network: "none"` policy, physically depriving the container of an outbound network stack and neutralizing data exfiltration vectors.  
* The host environment MUST be mounted into the container workspace utilizing a `workspaceAccess: "ro"` (read-only) directive, preventing the agent from mutating local source code.  
* The container MUST be instantiated with `capDrop: ["ALL"]`, stripping the runtime of all Linux kernel privileges.  
* The sandbox MUST enforce strict resource boundaries (`cpus`, `memory`, `pidsLimit`) to prevent rogue agents from executing fork bombs or triggering out-of-memory kernel panics on the host.

### **Machine-Readable Sandbox Policy Schema**

```json
{
  "sandbox": {
    "enabled": true,
    "image": "openclaw-sandbox:bookworm-slim@sha256:8e5a7bc12d09...",
    "network": "none",
    "workspaceAccess": "ro",
    "capDrop": ["ALL"],
    "readOnlyRoot": true,
    "resources": {
      "memory": "512m",
      "cpus": "1.0",
      "pidsLimit": 64
    }
  },
  "tools": {
    "redactOutput": true,
    "mode": "deny",
    "deny": ["browser", "shell", "fs.write", "system.run"]
  }
}

```

```
graph TD
    subgraph macOS_Host["macOS Apple Silicon (Unified Memory)"]
        direction TB
        GC[OpenClaw Gateway<br/>port 3000] -->|launchd daemon| DockerSocket[Docker Engine]
        Ollama[Ollama LLM Engine<br/>port 11434]
        GC -.->|Loopback API| Ollama
    end

    subgraph Sandbox["Ephemeral Docker Sandbox"]
        direction TB
        AgentTools[Agent Tools / Execution]
        Workspace[Read-Only Workspace Mount]
        Constraints[Resource Limits: 512MB RAM, 1 CPU]
        AgentTools --> Workspace
        AgentTools -.-> Constraints
    end

    DockerSocket -->|UID 1000| AgentTools

    %% Security Boundaries
    AgentTools -.x|Egress: NONE| Internet((External Network))
    Workspace -.x|fs.write: DENY| LocalDisk[(macOS Filesystem)]
    
    classDef secure fill:#e6f3ff,stroke:#0066cc,stroke-width:2px;
    classDef danger fill:#ffe6e6,stroke:#cc0000,stroke-width:2px,stroke-dasharray: 5 5;
    class GC,Ollama secure;
    class Sandbox danger;

```

## **4\. Credential Management & API Security**

* Cryptographic secrets, API keys, and authentication tokens MUST NOT be stored in plaintext within the `openclaw.json` configuration file, `TOOLS.md` memory files, or the interactive chat interface.  
* Secrets MUST be managed via an external `.env` file provisioned with strict `600` octal permissions.  
* The Gateway's `config.get` Remote Procedure Call (RPC) MUST be configured to enforce placeholder resolution (e.g., returning template strings) rather than leaking plaintext secrets into the runtime context.  
* Secrets SHALL NOT be passed as environment variables (`ENV`) into the Docker sandbox, as these can be easily dumped by arbitrary execution payloads. Secrets MUST only be injected ephemerally into the tool's isolated memory space at the exact moment of execution and scrubbed immediately thereafter.  
* Integrations requiring external Git access MUST utilize scoped Personal Access Tokens (PATs) restricted to the `repo` or `public_repo` scopes. Broad OAuth authentication flows granting full-account access SHALL NOT be used.

## **5\. Cognitive Security & Output DLP**

As autonomous agents ingest external data, they become highly susceptible to Indirect Prompt Injection (IPI) attacks.

* The architecture MUST enforce a mandatory middleware scanning layer utilizing the `indirect-prompt-injection` and `prompt-guard` plugins.  
* This pipeline MUST execute synchronous regex pattern matching against known instruction-overrides prior to processing the payload in the primary LLM.  
* For advanced obfuscation detection, the system SHOULD leverage the MELON (Masked re-Execution and TooL comparisON) defense framework, triggering a security halt if masked parallel executions exhibit identical malicious behaviors.  
* Data Loss Prevention (DLP) MUST be enforced by setting the `tools.redactOutput` configuration to `true` to scrub Personally Identifiable Information (PII) from raw tool results before the transcript is committed to the local `MEMORY.md` or JSONL logs.  
* Recognizing the inherent brittleness of regex against adversarial LLM obfuscation (e.g., base64 encoding or spacing out API keys), the architecture MUST implement a secondary semantic or entropy-based scanning layer to reliably intercept exfiltrated cryptographic material.

## **6\. Official Waiver and Break-Glass Protocol**

Because the default baseline physically prevents the agent from executing arbitrary local shell commands or transmitting data externally, a rigorous Break-Glass Exception workflow is REQUIRED for CI/CD operations or advanced administrative tasks.

* Administrators SHALL NOT permanently alter the baseline `openclaw.json` constraints to accommodate task-specific needs.  
* Elevated capabilities MUST be provisioned using the `dangerouslyAllowContainerNamespaceJoin: true` override.  
* This override MUST be invoked alongside a Human-In-The-Loop (HITL) prompt, forcing the administrator to explicitly sign off on the exact payload the agent intends to execute.  
* To guarantee non-repudiation and prevent audit scrubbing, the HITL approval event, the cryptographic hash of the approved payload, and the administrator's verifiable identity MUST be written to an immutable, append-only logging facility (e.g., macOS unified logging `os_log` via `syslog`) BEFORE the container namespace join is executed.

```
stateDiagram-v2
    [*] --> Agent_Request
    
    state Agent_Request {
        [*] --> Assess_Requirements
        Assess_Requirements --> Capability_Blocked: Requires fs.write or Network
    }
    
    Capability_Blocked --> HITL_Approval_Gate: Request Break-Glass Waiver
    
    state HITL_Approval_Gate {
        direction LR
        Review_Payload --> Approve
        Review_Payload --> Reject
    }
    
    Reject --> Security_Halt: Session Terminated
    Security_Halt --> [*]
    
    Approve --> Immutable_Audit_Logging
    
    state Immutable_Audit_Logging {
        [*] --> Hash_Payload
        Hash_Payload --> Write_Append_Only_Log: os_log / syslog
        Write_Append_Only_Log --> Authorize_Escalation
    }
    
    Authorize_Escalation --> Ephemeral_Escalation
    
    state Ephemeral_Escalation {
        [*] --> Inject_Namespace_Override
        Inject_Namespace_Override --> dangerouslyAllowContainerNamespaceJoin
        dangerouslyAllowContainerNamespaceJoin --> Execute_Isolated_Task
        Execute_Isolated_Task --> Destroy_Container
    }
    
    Destroy_Container --> Restore_Baseline
    Restore_Baseline --> [*]: Return to Zero-Trust
```
