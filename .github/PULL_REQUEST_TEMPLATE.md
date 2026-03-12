## What does this PR do?
<!-- Brief description of the change -->

## Agent Information (if adding/modifying an agent)
- **Agent Name**:
- **Category**:
- **Specialty**:

## Checklist

### Structure
- [ ] Follows the agent template structure from CONTRIBUTING.md
- [ ] Includes YAML frontmatter with `name`, `description`, `color`
- [ ] Has concrete code/template examples (for new agents)
- [ ] Tested in real scenarios
- [ ] Proofread and formatted correctly

### Security
- [ ] Agent file does **NOT** contain instructions to read, write, or access
      filesystem paths, dotfiles, or user directories
- [ ] Agent file does **NOT** reference environment variables, API keys,
      tokens, passwords, or credentials (except as clearly labelled placeholders)
- [ ] Agent file does **NOT** instruct the AI to make network requests,
      fetch URLs, or transmit data externally
- [ ] Agent file does **NOT** contain instructions to ignore, override,
      bypass, or modify system prompts, safety guidelines, or prior context
- [ ] Agent file does **NOT** contain base64-encoded content, hidden unicode
      characters, zero-width spaces, or obfuscated text
- [ ] All code examples are clearly labelled as illustrative and do not
      perform destructive operations (no `rm -rf`, `chmod 777`, `eval`, etc.)
- [ ] Agent file does **NOT** contain `<script>`, `<iframe>`, `<object>`,
      `<embed>` tags, inline event handlers, or `data:` URIs
- [ ] I have reviewed this file and confirm it contains only agent personality,
      workflow, and deliverable definitions — nothing executable

<!-- Note: The automated lint-agents CI check will also verify these rules. -->
