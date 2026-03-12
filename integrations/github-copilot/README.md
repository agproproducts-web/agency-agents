# GitHub Copilot Integration

The Agency works with GitHub Copilot out of the box. No conversion needed —
agents use the existing `.md` + YAML frontmatter format.

## Install

```bash
# Recommended — includes security validation of all agent files
./scripts/install.sh --tool copilot
```

> **Manual alternative** (skips security validation):
> ```bash
> cp engineering/*.md ~/.github/agents/
> ```
> If installing manually, review agent files before copying them into your
> config directory. See [SECURITY.md](../../SECURITY.md) for guidance.

## Activate an Agent

In any GitHub Copilot session, reference an agent by name:

```
Activate Frontend Developer and help me build a React component.
```

```
Use the Reality Checker agent to verify this feature is production-ready.
```

## Agent Directory

Agents are organized into divisions. See the [main README](../../README.md) for
the full current roster.
