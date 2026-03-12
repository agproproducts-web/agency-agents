# Security Policy

## Overview

The Agency is a collection of AI agent personality files that are installed
into trusted configuration directories for tools like Claude Code, Cursor,
GitHub Copilot, and others. Because agent files are loaded as instructions
by AI systems, a malicious agent file can function as a **prompt injection
attack** — instructing the AI to exfiltrate data, access credentials, or
bypass safety guidelines.

We take this seriously. Every contributed agent file is reviewed for both
structural quality and security before merge.

## Threat Model

Agent files in this repository are consumed in high-trust contexts:

- **Claude Code** (`~/.claude/agents/`) — full access to filesystem and shell
- **Cursor** (`.cursor/rules/`) — influences code generation and editing
- **GitHub Copilot** (`~/.github/agents/`) — influences code suggestions
- **Aider/Windsurf** — injected into system prompts for coding sessions

A compromised agent file could instruct the AI to:

- Read and exfiltrate credentials, SSH keys, environment variables, or source code
- Execute destructive shell commands
- Override safety guidelines or bypass content restrictions
- Embed hidden instructions using invisible unicode characters or encoded content
- Make network requests to attacker-controlled servers

## Automated Protections

All PRs that modify agent files are automatically checked by our CI linter
(`scripts/lint-agents.sh`), which scans for:

| Category                  | What It Catches                                                  |
| ------------------------- | ---------------------------------------------------------------- |
| Filesystem access         | References to dotfiles, `/etc/`, credentials, SSH keys           |
| Credential harvesting     | Environment variable access, API key patterns, token references  |
| Network exfiltration      | `curl`, `wget`, `fetch()`, netcat, raw TCP                      |
| Prompt injection          | Override/ignore/bypass instructions, jailbreak patterns          |
| Obfuscated content        | Base64 blobs, zero-width unicode, directional overrides          |
| Executable payloads       | `<script>`, `<iframe>`, `data:` URIs, inline event handlers     |
| Destructive commands      | `rm -rf`, `chmod 777`, `eval`, `exec` outside code blocks       |
| File size                 | Agent files over 100KB are rejected; over 50KB are warned        |

The linter **blocks merge** on any error-level finding.

## Content Policy for Agent Files

Agent files **MUST** only contain:

- Agent identity, personality, and communication style
- Core mission and domain expertise descriptions
- Workflow processes and step-by-step methodologies
- Code examples that are clearly labelled as illustrative templates
- Success metrics and quality standards
- References to tools and technologies (descriptions, not invocations)

Agent files **MUST NOT** contain:

- Instructions to access the filesystem, environment, or credentials
- Instructions to make network requests or transmit data
- Instructions to override, ignore, or bypass system prompts or safety guidelines
- Executable code that is not clearly labelled as an example
- Base64-encoded content, data URIs, or obfuscated text
- HTML tags that execute code (`<script>`, `<iframe>`, `<object>`, `<embed>`)
- Hidden or invisible unicode characters

## Reporting a Vulnerability

If you discover a security issue in an existing agent file, a script, or
the CI pipeline, please report it responsibly:

1. **Do NOT open a public issue.**
2. Email **[SECURITY_EMAIL]** with:
   - Description of the vulnerability
   - Which file(s) are affected
   - Steps to reproduce
   - Potential impact
3. You will receive an acknowledgement within **48 hours**.
4. We aim to resolve confirmed issues within **7 days**.

If you discover that a merged agent file contains prompt injection or
exfiltration instructions, please include the file path and the specific
lines of concern.

## For Contributors

Before submitting an agent file:

1. Review the [Content Policy](#content-policy-for-agent-files) above
2. Run the linter locally: `./scripts/lint-agents.sh path/to/your-agent.md`
3. Complete the security checklist in the PR template
4. Ensure all code examples are clearly labelled and non-destructive

## For Users

When installing agents from this repository or any fork:

1. **Review agent files before installing.** Use `cat` or your editor to
   read any `.md` file before copying it into a tool's config directory.
2. **Be cautious with forks and translations.** Community forks may contain
   modifications not present in this repository. Always review.
3. **Review install scripts before running them.** Read `scripts/install.sh`
   and `scripts/convert.sh` before execution.
4. **Report suspicious content.** If an agent file asks the AI to access
   your credentials, make network requests, or ignore safety guidelines,
   report it immediately.

## Supported Versions

| Version | Supported |
| ------- | --------- |
| main    | Yes       |
| Forks   | No — maintained independently |

## Acknowledgements

We credit security researchers who responsibly disclose vulnerabilities,
with their permission, in our release notes.
