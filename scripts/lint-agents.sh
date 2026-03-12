#!/usr/bin/env bash
# =============================================================================
# lint-agents.sh — Security & structural linter for Agency agent files
# =============================================================================
# Called by .github/workflows/lint-agents.yml on PRs that touch agent files.
# Usage: ./scripts/lint-agents.sh file1.md file2.md ...
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed
#
# Design principles:
#   - Patterns OUTSIDE code blocks → ERROR (blocks merge)
#   - Patterns INSIDE code blocks → WARN (legitimate examples)
#   - Prompt injection patterns → ERROR everywhere (never legitimate)
#   - Hidden/obfuscated content → ERROR everywhere (never legitimate)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0
FILES_CHECKED=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
error() {
  echo -e "  ${RED}ERROR${NC}   $1: $2"
  ERRORS=$((ERRORS + 1))
}

warn() {
  echo -e "  ${YELLOW}WARN${NC}    $1: $2"
  WARNINGS=$((WARNINGS + 1))
}

pass() {
  echo -e "  ${GREEN}PASS${NC}    $1: $2"
}

header() {
  echo ""
  echo -e "${BLUE}━━━ Checking: $1${NC}"
}

# ---------------------------------------------------------------------------
# Extract content OUTSIDE fenced code blocks (``` ... ```)
# Returns only prose/instruction lines with original line numbers preserved.
# This is the core mechanism for reducing false positives — patterns found
# in code examples are expected; patterns in prose instructions are not.
# ---------------------------------------------------------------------------
extract_prose() {
  local file="$1"
  awk '
    /^```/ { in_code = !in_code; next }
    !in_code { print NR ":" $0 }
  ' "$file"
}

# Extract content INSIDE fenced code blocks only
extract_code_blocks() {
  local file="$1"
  awk '
    /^```/ { in_code = !in_code; next }
    in_code { print NR ":" $0 }
  ' "$file"
}

# ---------------------------------------------------------------------------
# 1. STRUCTURAL VALIDATION
#    Ensures agent files follow the expected template format.
#    Accepts both the recommended template and the alternative structure
#    used by paid-media, sales, product, and other divisions.
# ---------------------------------------------------------------------------
check_structure() {
  local file="$1"

  # --- YAML frontmatter ---
  if head -1 "$file" | grep -q '^---'; then
    local frontmatter
    frontmatter=$(sed -n '/^---$/,/^---$/p' "$file")

    if echo "$frontmatter" | grep -qi 'name:'; then
      pass "$file" "Has 'name' in frontmatter"
    else
      error "$file" "Missing 'name' in YAML frontmatter"
    fi

    if echo "$frontmatter" | grep -qi 'description:'; then
      pass "$file" "Has 'description' in frontmatter"
    else
      error "$file" "Missing 'description' in YAML frontmatter"
    fi
  else
    error "$file" "Missing YAML frontmatter (file must start with ---)"
  fi

  # --- Required sections (accepts alternative names) ---
  # Each entry: "PrimaryName|AlternativeName1|AlternativeName2"
  # An agent passes if ANY alternative matches.
  local section_groups=(
    "Identity|Role Definition|Your Identity"
    "Core Mission|Core Capabilities|Core Competencies|Specialized Skills"
    "Critical Rules|Decision Framework|Operating Principles|Methodology"
    "Workflow|Process|Methodology|Approach"
    "Success Metrics|Metrics|Performance|KPI"
  )

  for group in "${section_groups[@]}"; do
    local found=false
    local primary="${group%%|*}"

    # Split on | and check each alternative
    IFS='|' read -ra alternatives <<< "$group"
    for alt in "${alternatives[@]}"; do
      if grep -qi "# .*${alt}" "$file" || grep -qi "## .*${alt}" "$file"; then
        found=true
        break
      fi
    done

    if $found; then
      pass "$file" "Has '${primary}' section (or equivalent)"
    else
      warn "$file" "Missing recommended section: '${primary}' (or equivalent)"
    fi
  done
}

# ---------------------------------------------------------------------------
# 2. PROMPT INJECTION & EXFILTRATION DETECTION
#    Scans for patterns that could weaponise an agent file.
#
#    Strategy:
#    - Filesystem/credential/network patterns OUTSIDE code blocks → ERROR
#    - Same patterns INSIDE code blocks → WARN (likely illustrative)
#    - Prompt injection patterns → ERROR everywhere (never legitimate)
#    - Hidden unicode / obfuscation → ERROR everywhere
# ---------------------------------------------------------------------------
check_security() {
  local file="$1"
  local prose code_blocks
  prose=$(extract_prose "$file")
  code_blocks=$(extract_code_blocks "$file")

  # --- Filesystem access patterns ---
  local fs_patterns=(
    '~/\.'                         # Hidden dotfiles (~/.ssh, ~/.env, etc.)
    '/etc/passwd'
    '/etc/shadow'
    '\.ssh/'
    '\.aws/'
    '\.gnupg/'
    '\.npmrc'
    '\.netrc'
    'id_rsa'
    'id_ed25519'
    '/home/.*/'
    'credentials\.json'
    'token\.json'
  )

  for pattern in "${fs_patterns[@]}"; do
    # Check prose (outside code blocks) → ERROR
    local prose_matches
    prose_matches=$(echo "$prose" | grep -P "$pattern" 2>/dev/null | head -3) || true
    if [[ -n "$prose_matches" ]]; then
      error "$file" "Filesystem access pattern in prose: '${pattern}'\n           ${prose_matches}"
    fi

    # Check code blocks → WARN (likely illustrative)
    local code_matches
    code_matches=$(echo "$code_blocks" | grep -P "$pattern" 2>/dev/null | head -3) || true
    if [[ -n "$code_matches" ]]; then
      warn "$file" "Filesystem access pattern in code example: '${pattern}' (verify it's illustrative)"
    fi
  done

  # --- .env file pattern (common in both prose docs and code — needs context) ---
  # Only flag if it looks like an instruction to READ a .env, not just mentioning .env files
  local env_file_prose
  env_file_prose=$(echo "$prose" | grep -P '(read|cat|source|load|open|access|include).*\.env' 2>/dev/null | head -3) || true
  if [[ -n "$env_file_prose" ]]; then
    error "$file" "Instruction to access .env file detected in prose\n           ${env_file_prose}"
  fi

  # --- Environment variable / credential access ---
  local env_patterns=(
    'process\.env\.'
    'os\.environ'
    'getenv\('
  )

  # These are code-level access patterns — ERROR in prose, WARN in code blocks
  for pattern in "${env_patterns[@]}"; do
    local prose_matches
    prose_matches=$(echo "$prose" | grep -P "$pattern" 2>/dev/null | head -3) || true
    if [[ -n "$prose_matches" ]]; then
      error "$file" "Credential access pattern in prose: '${pattern}'\n           ${prose_matches}"
    fi
  done

  # --- Credential name patterns ---
  # These are names that could appear legitimately in documentation about services.
  # ERROR only if they appear in prose as instructions (not documenting a dependency).
  # WARN if in code blocks. Skip if clearly a placeholder or service documentation.
  local cred_patterns=(
    'OPENAI_API_KEY'
    'ANTHROPIC_API_KEY'
    'AWS_SECRET'
    'STRIPE_SECRET'
  )

  for pattern in "${cred_patterns[@]}"; do
    local prose_matches
    prose_matches=$(echo "$prose" | grep -P "$pattern" 2>/dev/null \
      | grep -vi '(example\|placeholder\|your[_-]\|dummy\|sample\|replace\|credential.*environment\|environment variable\|free tier\|required\|setup\|configuration)' \
      | head -3) || true
    if [[ -n "$prose_matches" ]]; then
      error "$file" "Credential reference in prose: '${pattern}'\n           ${prose_matches}"
    fi
  done

  # --- Credential patterns that are almost always safe in code (secrets., GITHUB_TOKEN) ---
  # GitHub Actions ${{ secrets.X }} is a template reference, not a credential value.
  # Only flag if found OUTSIDE code blocks AND not in a CI/CD context.
  local gh_secrets_prose
  gh_secrets_prose=$(echo "$prose" | grep -P 'secrets\.' 2>/dev/null \
    | grep -vi '(CI/CD\|pipeline\|workflow\|github.actions\|yaml\|yml\|management\|rotation\|vault)' \
    | head -3) || true
  if [[ -n "$gh_secrets_prose" ]]; then
    warn "$file" "secrets. reference in prose (verify context)\n           ${gh_secrets_prose}"
  fi

  # --- Generic API_KEY / TOKEN patterns (high false-positive rate) ---
  # Only flag in prose if it looks like an instruction to use/read a key,
  # not just mentioning that a key exists or documenting a service dependency.
  local generic_key_prose
  generic_key_prose=$(echo "$prose" | grep -P '(API_KEY|_TOKEN|_SECRET|_PASSWORD)' 2>/dev/null \
    | grep -vi '(example\|placeholder\|your[_-]\|dummy\|sample\|replace\|credential\|environment variable\|required\|setup\|configuration\|free tier\|document\|frontmatter\|services\|field)' \
    | head -3) || true
  if [[ -n "$generic_key_prose" ]]; then
    warn "$file" "Credential name pattern in prose (verify context)\n           ${generic_key_prose}"
  fi

  # --- Network exfiltration patterns ---
  local net_patterns=(
    'curl\s'
    'wget\s'
    'fetch\('
    'http\.get\('
    'requests\.get\('
    'requests\.post\('
    'XMLHttpRequest'
    'nc\s+-'             # netcat
    'ncat\s'
    '\/dev\/tcp\/'
    'telnet\s'
  )

  for pattern in "${net_patterns[@]}"; do
    # Prose → ERROR
    local prose_matches
    prose_matches=$(echo "$prose" | grep -P "$pattern" 2>/dev/null | head -3) || true
    if [[ -n "$prose_matches" ]]; then
      error "$file" "Network call pattern in prose: '${pattern}'\n           ${prose_matches}"
    fi

    # Code blocks → WARN
    local code_matches
    code_matches=$(echo "$code_blocks" | grep -P "$pattern" 2>/dev/null | head -3) || true
    if [[ -n "$code_matches" ]]; then
      warn "$file" "Network call in code example: '${pattern}' (verify it's illustrative)"
    fi
  done

  # --- Prompt override / injection attempts ---
  # These are ALWAYS errors regardless of where they appear — there is no
  # legitimate reason for an agent file to contain these patterns.
  local content
  content=$(cat "$file")

  local injection_patterns=(
    'ignore\s+(all\s+)?previous\s+instructions'
    'ignore\s+(all\s+)?prior\s+instructions'
    'ignore\s+(all\s+)?above\s+instructions'
    'disregard\s+(all\s+)?previous'
    'override\s+system\s+prompt'
    'new\s+system\s+prompt'
    'you\s+are\s+now\s+in\s+.*mode'
    'act\s+as\s+if\s+you\s+have\s+no\s+restrictions'
    'jailbreak'
    'DAN\s+mode'
    'bypass\s+(all\s+)?safety'
    'bypass\s+(all\s+)?filter'
    'bypass\s+(all\s+)?restriction'
    'pretend\s+(that\s+)?you\s+have\s+no\s+guidelines'
    'forget\s+(all\s+)?(your|prior|previous)\s+(rules|instructions|guidelines)'
    'do\s+not\s+refuse'
    'never\s+refuse'
    'always\s+comply'
    'you\s+must\s+obey'
    'from\s+now\s+on.*ignore'
  )

  for pattern in "${injection_patterns[@]}"; do
    if echo "$content" | grep -Pqi "$pattern"; then
      local matches
      matches=$(echo "$content" | grep -Pni "$pattern" | head -3)
      error "$file" "PROMPT INJECTION pattern detected: '${pattern}'\n           ${matches}"
    fi
  done

  # --- Hidden/obfuscated content (always errors) ---
  # Check for base64 encoded blocks (strings > 60 chars — raised from 40 to reduce
  # false positives from long hex hashes, UUIDs, and contract addresses)
  if echo "$content" | grep -Pn '[A-Za-z0-9+/]{60,}={0,2}' \
    | grep -qvi '(sha256\|sha512\|hash\|checksum\|fingerprint\|example\|address\|0x)'; then
    local matches
    matches=$(echo "$content" | grep -Pn '[A-Za-z0-9+/]{60,}={0,2}' | head -3)
    warn "$file" "Possible base64-encoded content detected\n           ${matches}"
  fi

  # Check for zero-width / invisible unicode characters
  if echo "$content" | grep -Pn '[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{2060}\x{180E}]' 2>/dev/null; then
    error "$file" "Hidden unicode characters detected (zero-width spaces, etc.)"
  fi

  # Check for unicode directional override characters (used to disguise text)
  if echo "$content" | grep -Pn '[\x{202A}\x{202B}\x{202C}\x{202D}\x{202E}\x{2066}\x{2067}\x{2068}\x{2069}]' 2>/dev/null; then
    error "$file" "Unicode directional override characters detected — possible text disguise"
  fi
}

# ---------------------------------------------------------------------------
# 3. CONTENT POLICY
#    Enforces size limits and checks for suspicious executable content.
# ---------------------------------------------------------------------------
check_content_policy() {
  local file="$1"

  # --- File size check ---
  local size_kb
  size_kb=$(du -k "$file" | cut -f1)

  if [ "$size_kb" -gt 100 ]; then
    error "$file" "File is ${size_kb}KB — agent files should be under 100KB"
  elif [ "$size_kb" -gt 50 ]; then
    warn "$file" "File is ${size_kb}KB — unusually large for an agent file"
  else
    pass "$file" "File size OK (${size_kb}KB)"
  fi

  # --- Check for executable shell commands outside code blocks ---
  local in_code_block=0
  local suspicious_lines=0
  local line_num=0

  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if echo "$line" | grep -q '^```'; then
      if [ "$in_code_block" -eq 0 ]; then
        in_code_block=1
      else
        in_code_block=0
      fi
      continue
    fi

    if [ "$in_code_block" -eq 0 ]; then
      if echo "$line" | grep -Pq '(rm\s+-rf|chmod\s+777|eval\s*\(|exec\s*\(|sudo\s|mkfifo|>\s*/dev/)'; then
        warn "$file" "Line ${line_num}: Suspicious command outside code block: ${line:0:80}"
        suspicious_lines=$((suspicious_lines + 1))
      fi
    fi
  done < "$file"

  if [ "$suspicious_lines" -eq 0 ]; then
    pass "$file" "No suspicious commands outside code blocks"
  fi

  # --- Check for data: URIs (can embed executable content) ---
  if grep -Pn 'data:[a-z]+/[a-z]+;base64,' "$file" > /dev/null 2>&1; then
    error "$file" "Embedded data: URI detected — these can contain executable payloads"
  fi

  # --- Check for HTML injection tags ---
  # Only flag OUTSIDE code blocks (code examples legitimately discuss these)
  local prose
  prose=$(extract_prose "$file")

  if echo "$prose" | grep -Pi '<script[\s>]' > /dev/null 2>&1; then
    error "$file" "<script> tag detected outside code blocks"
  fi
  if echo "$prose" | grep -Pi '<iframe[\s>]' > /dev/null 2>&1; then
    error "$file" "<iframe> tag detected outside code blocks"
  fi
  if echo "$prose" | grep -Pi '<object[\s>]' > /dev/null 2>&1; then
    warn "$file" "<object> tag detected outside code blocks"
  fi
  if echo "$prose" | grep -Pi '<embed[\s>]' > /dev/null 2>&1; then
    warn "$file" "<embed> tag detected outside code blocks"
  fi

  # Inline event handlers — only flag outside code blocks
  if echo "$prose" | grep -Pi 'on(click|error|load|mouseover|focus|blur|submit|change|input)\s*=' > /dev/null 2>&1; then
    warn "$file" "Inline event handler attribute detected outside code blocks"
  fi
}

# =============================================================================
# MAIN
# =============================================================================
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   The Agency — Agent File Security & Structure Linter    ║${NC}"
echo -e "${BLUE}║   v2.0 — Code-block aware, reduced false positives      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $# -eq 0 ]; then
  echo -e "${RED}No files provided.${NC}"
  echo "Usage: $0 file1.md file2.md ..."
  exit 1
fi

for file in "$@"; do
  # Skip empty args (can happen with heredoc multiline output)
  [ -z "$file" ] && continue

  if [ ! -f "$file" ]; then
    error "$file" "File not found"
    continue
  fi

  FILES_CHECKED=$((FILES_CHECKED + 1))
  header "$file"
  check_structure "$file"
  check_security "$file"
  check_content_policy "$file"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Files checked:  ${FILES_CHECKED}"
echo -e "  Errors:         ${RED}${ERRORS}${NC}"
echo -e "  Warnings:       ${YELLOW}${WARNINGS}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}FAILED${NC} — ${ERRORS} error(s) must be resolved before merge."
  exit 1
else
  if [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}PASSED WITH WARNINGS${NC} — Review ${WARNINGS} warning(s) above."
  else
    echo -e "${GREEN}ALL CHECKS PASSED${NC}"
  fi
  exit 0
fi
