# Claude Code Integration

The Agency was built for Claude Code. No conversion needed — agents work
natively with the existing `.md` + YAML frontmatter format.

## Install

```bash
# Recommended — includes security validation of all agent files
./scripts/install.sh --tool claude-code
```

> **Manual alternative** (skips security validation):
> ```bash
> cp engineering/*.md ~/.claude/agents/
> ```
> If installing manually, review agent files before copying them into your
> config directory. See [SECURITY.md](../../SECURITY.md) for guidance.

## Activate an Agent

In any Claude Code session, reference an agent by name:

```
Activate Frontend Developer and help me build a React component.
```

```
Use the Reality Checker agent to verify this feature is production-ready.
```

## Agent Directory

Agents are organized into divisions. See the [main README](../../README.md) for
the full current roster.
