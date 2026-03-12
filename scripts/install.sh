#!/usr/bin/env bash
#
# install.sh -- Install The Agency agents into your local agentic tool(s).
#
# Reads converted files from integrations/ and copies them to the appropriate
# config directory for each tool. Run scripts/convert.sh first if integrations/
# is missing or stale.
#
# Usage:
#   ./scripts/install.sh [--tool <name>] [--interactive] [--no-interactive]
#                        [--dry-run] [--force] [--skip-lint] [--help]
#
# Tools:
#   claude-code  -- Copy agents to ~/.claude/agents/
#   copilot      -- Copy agents to ~/.github/agents/
#   antigravity  -- Copy skills to ~/.gemini/antigravity/skills/
#   gemini-cli   -- Install extension to ~/.gemini/extensions/agency-agents/
#   opencode     -- Copy agents to .opencode/agent/ in current directory
#   cursor       -- Copy rules to .cursor/rules/ in current directory
#   aider        -- Copy CONVENTIONS.md to current directory
#   windsurf     -- Copy .windsurfrules to current directory
#   openclaw     -- Copy workspaces to ~/.openclaw/agency-agents/
#   all          -- Install for all detected tools (default)
#
# Flags:
#   --tool <name>     Install only the specified tool
#   --interactive     Show interactive selector (default when run in a terminal)
#   --no-interactive  Skip interactive selector, install all detected tools
#   --dry-run         Show what would be installed without writing anything
#   --force           Overwrite existing files without creating backups
#   --skip-lint       Skip the security lint preflight (not recommended)
#   --help            Show this help
#
# Platform support:
#   Linux, macOS (requires bash 3.2+), Windows Git Bash / WSL

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours -- only when stdout is a real terminal
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_GREEN=$'\033[0;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[0;31m'
  C_CYAN=$'\033[0;36m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RESET=$'\033[0m'
else
  C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi

ok()     { printf "${C_GREEN}[OK]${C_RESET}  %s\n" "$*"; }
warn()   { printf "${C_YELLOW}[!!]${C_RESET}  %s\n" "$*"; }
err()    { printf "${C_RED}[ERR]${C_RESET} %s\n" "$*" >&2; }
header() { printf "\n${C_BOLD}%s${C_RESET}\n" "$*"; }
dim()    { printf "${C_DIM}%s${C_RESET}\n" "$*"; }

# ---------------------------------------------------------------------------
# Box drawing -- pure ASCII, fixed 52-char wide
# ---------------------------------------------------------------------------
BOX_INNER=48

box_top() { printf "  +"; printf '%0.s-' $(seq 1 $BOX_INNER); printf "+\n"; }
box_bot() { box_top; }
box_sep() { printf "  |"; printf '%0.s-' $(seq 1 $BOX_INNER); printf "|\n"; }
box_row() {
  local raw="$1"
  local visible
  visible="$(printf '%s' "$raw" | sed 's/\x1b\[[0-9;]*m//g')"
  local pad=$(( BOX_INNER - 2 - ${#visible} ))
  if (( pad < 0 )); then pad=0; fi
  printf "  | %s%*s |\n" "$raw" "$pad" ''
}
box_blank() { printf "  |%*s|\n" $BOX_INNER ''; }

# ---------------------------------------------------------------------------
# Global flags
# ---------------------------------------------------------------------------
DRY_RUN=false
FORCE=false
SKIP_LINT=false
INSTALLED=0

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INTEGRATIONS="$REPO_ROOT/integrations"
LINTER="$REPO_ROOT/scripts/lint-agents.sh"

ALL_TOOLS=(claude-code copilot antigravity gemini-cli opencode openclaw cursor aider windsurf)

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  sed -n '3,34p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
check_integrations() {
  if [[ ! -d "$INTEGRATIONS" ]]; then
    err "integrations/ not found. Run ./scripts/convert.sh first."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Safe copy helper — backs up existing files before overwriting
# ---------------------------------------------------------------------------
# safe_cp <source> <destination>
#   - In dry-run mode: prints what would happen, writes nothing
#   - With --force: overwrites without backup
#   - Default: creates .backup-YYYYMMDD-HHMMSS of existing file before copy
safe_cp() {
  local src="$1" dest="$2"

  if $DRY_RUN; then
    if [[ -f "$dest" ]]; then
      dim "    [dry-run] Would backup and overwrite: $dest"
    else
      dim "    [dry-run] Would install: $dest"
    fi
    return 0
  fi

  if [[ -f "$dest" ]]; then
    if $FORCE; then
      cp "$src" "$dest"
    else
      local backup="${dest}.backup-$(date +%Y%m%d-%H%M%S)"
      cp "$dest" "$backup"
      cp "$src" "$dest"
      dim "    Backed up existing: $(basename "$dest") -> $(basename "$backup")"
    fi
  else
    cp "$src" "$dest"
  fi
}

# ---------------------------------------------------------------------------
# Safe directory copy — creates dest dir structure and copies with backup
# ---------------------------------------------------------------------------
# safe_cp_dir <source_dir> <dest_dir>
#   Copies all files from source_dir into dest_dir using safe_cp.
safe_cp_dir() {
  local src_dir="$1" dest_dir="$2"

  if ! $DRY_RUN; then
    mkdir -p "$dest_dir"
  fi

  local f
  while IFS= read -r -d '' f; do
    local relative="${f#$src_dir/}"
    local dest_file="$dest_dir/$relative"
    local dest_parent
    dest_parent="$(dirname "$dest_file")"

    if ! $DRY_RUN; then
      mkdir -p "$dest_parent"
    fi

    safe_cp "$f" "$dest_file"
  done < <(find "$src_dir" -type f -print0)
}

# ---------------------------------------------------------------------------
# Lint preflight — validates all agent .md files before installation
# ---------------------------------------------------------------------------
run_lint_preflight() {
  if $SKIP_LINT; then
    warn "Security lint skipped (--skip-lint). Proceeding without validation."
    return 0
  fi

  if [[ ! -x "$LINTER" ]]; then
    if [[ -f "$LINTER" ]]; then
      chmod +x "$LINTER"
    else
      warn "Linter not found at $LINTER — skipping preflight."
      warn "Run from the repo root, or use --skip-lint to suppress this warning."
      return 0
    fi
  fi

  header "Security preflight — scanning agent files"
  printf "\n"

  # Collect all agent .md files that would be installed
  local agent_files=()
  local dir
  for dir in design engineering game-development marketing paid-media sales product \
             project-management testing support spatial-computing specialized; do
    local dirpath="$REPO_ROOT/$dir"
    [[ -d "$dirpath" ]] || continue

    local f first_line
    while IFS= read -r -d '' f; do
      first_line="$(head -1 "$f")"
      [[ "$first_line" == "---" ]] || continue
      agent_files+=("$f")
    done < <(find "$dirpath" -name "*.md" -type f -print0 | sort -z)
  done

  if [[ ${#agent_files[@]} -eq 0 ]]; then
    warn "No agent files found to lint."
    return 0
  fi

  dim "  Scanning ${#agent_files[@]} agent files..."
  printf "\n"

  # Run linter — capture output and exit code
  local lint_output lint_exit=0
  lint_output=$("$LINTER" "${agent_files[@]}" 2>&1) || lint_exit=$?

  if [[ $lint_exit -ne 0 ]]; then
    # Show the full linter output so the user can see what failed
    echo "$lint_output"
    printf "\n"
    err "Security lint FAILED — ${#agent_files[@]} files scanned, errors found."
    err "Fix the errors above before installing, or use --skip-lint to bypass (not recommended)."
    exit 1
  fi

  # Show summary line from linter output (last non-empty line)
  local summary
  summary="$(echo "$lint_output" | grep -E '(PASSED|ALL CHECKS)' | tail -1)"
  if [[ -n "$summary" ]]; then
    printf "  %s\n" "$summary"
  fi

  ok "Security preflight passed — ${#agent_files[@]} files scanned."
  printf "\n"
}

# ---------------------------------------------------------------------------
# PWD confirmation for project-scoped tools
# ---------------------------------------------------------------------------
# Returns 0 if confirmed, 1 if declined
confirm_pwd_install() {
  local tool_name="$1"

  # Skip confirmation in non-interactive or dry-run mode
  if ! [[ -t 0 && -t 1 ]] || $DRY_RUN; then
    return 0
  fi

  printf "\n"
  printf "  ${C_YELLOW}%s${C_RESET} installs to the current directory:\n" "$tool_name"
  printf "  ${C_BOLD}%s${C_RESET}\n" "$PWD"
  printf "\n"
  printf "  Continue? [Y/n] "
  local answer
  read -r answer </dev/tty
  case "$answer" in
    n|N|no|No|NO) warn "$tool_name: skipped (user declined)."; return 1 ;;
    *) return 0 ;;
  esac
}

# Track which project-scoped tools have already been confirmed for this PWD
PWD_CONFIRMED=false

confirm_pwd_once() {
  local tool_name="$1"
  if $PWD_CONFIRMED; then
    return 0
  fi
  if confirm_pwd_install "$tool_name"; then
    PWD_CONFIRMED=true
    return 0
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Tool detection
# ---------------------------------------------------------------------------
detect_claude_code() { [[ -d "${HOME}/.claude" ]]; }
detect_copilot()     { [[ -d "${HOME}/.github/agents" ]] || [[ -d "${HOME}/.github/copilot" ]]; }
detect_antigravity() { [[ -d "${HOME}/.gemini/antigravity/skills" ]]; }
detect_gemini_cli()  { command -v gemini >/dev/null 2>&1 || [[ -d "${HOME}/.gemini/extensions" ]]; }
detect_cursor()      { command -v cursor >/dev/null 2>&1 || [[ -d "${HOME}/.cursor" ]]; }
detect_opencode()    { command -v opencode >/dev/null 2>&1 || [[ -d "${HOME}/.config/opencode" ]]; }
detect_aider()       { command -v aider >/dev/null 2>&1; }
detect_openclaw()    { command -v openclaw >/dev/null 2>&1 || [[ -d "${HOME}/.openclaw" ]]; }
detect_windsurf()    { command -v windsurf >/dev/null 2>&1 || [[ -d "${HOME}/.codeium" ]]; }

is_detected() {
  case "$1" in
    claude-code) detect_claude_code ;;
    copilot)     detect_copilot     ;;
    antigravity) detect_antigravity ;;
    gemini-cli)  detect_gemini_cli  ;;
    opencode)    detect_opencode    ;;
    openclaw)    detect_openclaw    ;;
    cursor)      detect_cursor      ;;
    aider)       detect_aider       ;;
    windsurf)    detect_windsurf    ;;
    *)           return 1 ;;
  esac
}

tool_label() {
  case "$1" in
    claude-code) printf "%-14s  %s" "Claude Code"  "(claude.ai/code)"        ;;
    copilot)     printf "%-14s  %s" "Copilot"      "(~/.github/agents)"      ;;
    antigravity) printf "%-14s  %s" "Antigravity"  "(~/.gemini/antigravity)" ;;
    gemini-cli)  printf "%-14s  %s" "Gemini CLI"   "(gemini extension)"      ;;
    opencode)    printf "%-14s  %s" "OpenCode"     "(opencode.ai)"           ;;
    openclaw)    printf "%-14s  %s" "OpenClaw"     "(~/.openclaw)"           ;;
    cursor)      printf "%-14s  %s" "Cursor"       "(.cursor/rules)"         ;;
    aider)       printf "%-14s  %s" "Aider"        "(CONVENTIONS.md)"        ;;
    windsurf)    printf "%-14s  %s" "Windsurf"     "(.windsurfrules)"        ;;
  esac
}

# ---------------------------------------------------------------------------
# Interactive selector (unchanged from original)
# ---------------------------------------------------------------------------
interactive_select() {
  declare -a selected=()
  declare -a detected_map=()

  local t
  for t in "${ALL_TOOLS[@]}"; do
    if is_detected "$t" 2>/dev/null; then
      selected+=(1); detected_map+=(1)
    else
      selected+=(0); detected_map+=(0)
    fi
  done

  while true; do
    printf "\n"
    box_top
    box_row "${C_BOLD}  The Agency -- Tool Installer${C_RESET}"
    box_bot
    printf "\n"
    printf "  ${C_DIM}System scan:  [*] = detected on this machine${C_RESET}\n"
    printf "\n"

    local i=0
    for t in "${ALL_TOOLS[@]}"; do
      local num=$(( i + 1 ))
      local label
      label="$(tool_label "$t")"
      local dot
      if [[ "${detected_map[$i]}" == "1" ]]; then
        dot="${C_GREEN}[*]${C_RESET}"
      else
        dot="${C_DIM}[ ]${C_RESET}"
      fi
      local chk
      if [[ "${selected[$i]}" == "1" ]]; then
        chk="${C_GREEN}[x]${C_RESET}"
      else
        chk="${C_DIM}[ ]${C_RESET}"
      fi
      printf "  %s  %s)  %s  %s\n" "$chk" "$num" "$dot" "$label"
      (( i++ )) || true
    done

    printf "\n"
    printf "  ------------------------------------------------\n"
    printf "  ${C_CYAN}[1-9]${C_RESET} toggle   ${C_CYAN}[a]${C_RESET} all   ${C_CYAN}[n]${C_RESET} none   ${C_CYAN}[d]${C_RESET} detected\n"
    printf "  ${C_GREEN}[Enter]${C_RESET} install   ${C_RED}[q]${C_RESET} quit\n"
    printf "\n"
    printf "  >> "
    read -r input </dev/tty

    case "$input" in
      q|Q)
        printf "\n"; ok "Aborted."; exit 0 ;;
      a|A)
        for (( j=0; j<${#ALL_TOOLS[@]}; j++ )); do selected[$j]=1; done ;;
      n|N)
        for (( j=0; j<${#ALL_TOOLS[@]}; j++ )); do selected[$j]=0; done ;;
      d|D)
        for (( j=0; j<${#ALL_TOOLS[@]}; j++ )); do selected[$j]="${detected_map[$j]}"; done ;;
      "")
        local any=false
        local s
        for s in "${selected[@]}"; do [[ "$s" == "1" ]] && any=true && break; done
        if $any; then
          break
        else
          printf "  ${C_YELLOW}Nothing selected -- pick a tool or press q to quit.${C_RESET}\n"
          sleep 1
        fi ;;
      *)
        local toggled=false
        local num
        for num in $input; do
          if [[ "$num" =~ ^[0-9]+$ ]]; then
            local idx=$(( num - 1 ))
            if (( idx >= 0 && idx < ${#ALL_TOOLS[@]} )); then
              if [[ "${selected[$idx]}" == "1" ]]; then
                selected[$idx]=0
              else
                selected[$idx]=1
              fi
              toggled=true
            fi
          fi
        done
        if ! $toggled; then
          printf "  ${C_RED}Invalid. Enter a number 1-%s, or a command.${C_RESET}\n" "${#ALL_TOOLS[@]}"
          sleep 1
        fi ;;
    esac

    local lines=$(( ${#ALL_TOOLS[@]} + 14 ))
    local l
    for (( l=0; l<lines; l++ )); do printf '\033[1A\033[2K'; done
  done

  SELECTED_TOOLS=()
  local i=0
  for t in "${ALL_TOOLS[@]}"; do
    [[ "${selected[$i]}" == "1" ]] && SELECTED_TOOLS+=("$t")
    (( i++ )) || true
  done
}

# ---------------------------------------------------------------------------
# Installers
# ---------------------------------------------------------------------------

install_claude_code() {
  local dest="${HOME}/.claude/agents"
  local count=0

  if $DRY_RUN; then
    dim "  [dry-run] Claude Code -> $dest"
  else
    mkdir -p "$dest"
  fi

  local dir f first_line
  for dir in design engineering game-development marketing paid-media sales product project-management \
              testing support spatial-computing specialized; do
    [[ -d "$REPO_ROOT/$dir" ]] || continue
    while IFS= read -r -d '' f; do
      first_line="$(head -1 "$f")"
      [[ "$first_line" == "---" ]] || continue
      safe_cp "$f" "$dest/$(basename "$f")"
      count=$((count + 1))
    done < <(find "$REPO_ROOT/$dir" -name "*.md" -type f -print0)
  done
  ok "Claude Code: $count agents -> $dest"
}

install_copilot() {
  local dest="${HOME}/.github/agents"
  local count=0

  if $DRY_RUN; then
    dim "  [dry-run] Copilot -> $dest"
  else
    mkdir -p "$dest"
  fi

  local dir f first_line
  for dir in design engineering game-development marketing paid-media sales product project-management \
              testing support spatial-computing specialized; do
    [[ -d "$REPO_ROOT/$dir" ]] || continue
    while IFS= read -r -d '' f; do
      first_line="$(head -1 "$f")"
      [[ "$first_line" == "---" ]] || continue
      safe_cp "$f" "$dest/$(basename "$f")"
      count=$((count + 1))
    done < <(find "$REPO_ROOT/$dir" -name "*.md" -type f -print0)
  done
  ok "Copilot: $count agents -> $dest"
}

install_antigravity() {
  local src="$INTEGRATIONS/antigravity"
  local dest="${HOME}/.gemini/antigravity/skills"
  local count=0
  [[ -d "$src" ]] || { err "integrations/antigravity missing. Run convert.sh first."; return 1; }

  if $DRY_RUN; then
    dim "  [dry-run] Antigravity -> $dest"
  else
    mkdir -p "$dest"
  fi

  local d
  while IFS= read -r -d '' d; do
    local name; name="$(basename "$d")"
    if ! $DRY_RUN; then
      mkdir -p "$dest/$name"
    fi
    safe_cp "$d/SKILL.md" "$dest/$name/SKILL.md"
    count=$((count + 1))
  done < <(find "$src" -mindepth 1 -maxdepth 1 -type d -print0)
  ok "Antigravity: $count skills -> $dest"
}

install_gemini_cli() {
  local src="$INTEGRATIONS/gemini-cli"
  local dest="${HOME}/.gemini/extensions/agency-agents"
  local count=0
  [[ -d "$src" ]] || { err "integrations/gemini-cli missing. Run convert.sh first."; return 1; }

  if $DRY_RUN; then
    dim "  [dry-run] Gemini CLI -> $dest"
  else
    mkdir -p "$dest/skills"
  fi

  safe_cp "$src/gemini-extension.json" "$dest/gemini-extension.json"

  local d
  while IFS= read -r -d '' d; do
    local name; name="$(basename "$d")"
    if ! $DRY_RUN; then
      mkdir -p "$dest/skills/$name"
    fi
    safe_cp "$d/SKILL.md" "$dest/skills/$name/SKILL.md"
    count=$((count + 1))
  done < <(find "$src/skills" -mindepth 1 -maxdepth 1 -type d -print0)
  ok "Gemini CLI: $count skills -> $dest"
}

install_opencode() {
  confirm_pwd_once "OpenCode" || return 0

  local src="$INTEGRATIONS/opencode/agents"
  local dest="${PWD}/.opencode/agents"
  local count=0
  [[ -d "$src" ]] || { err "integrations/opencode missing. Run convert.sh first."; return 1; }

  if $DRY_RUN; then
    dim "  [dry-run] OpenCode -> $dest"
  else
    mkdir -p "$dest"
  fi

  local f
  while IFS= read -r -d '' f; do
    safe_cp "$f" "$dest/$(basename "$f")"
    count=$((count + 1))
  done < <(find "$src" -maxdepth 1 -name "*.md" -print0)
  ok "OpenCode: $count agents -> $dest"
}

install_openclaw() {
  local src="$INTEGRATIONS/openclaw"
  local dest="${HOME}/.openclaw/agency-agents"
  local count=0
  [[ -d "$src" ]] || { err "integrations/openclaw missing. Run convert.sh first."; return 1; }

  if $DRY_RUN; then
    dim "  [dry-run] OpenClaw -> $dest"
  else
    mkdir -p "$dest"
  fi

  local d
  while IFS= read -r -d '' d; do
    local name; name="$(basename "$d")"
    if ! $DRY_RUN; then
      mkdir -p "$dest/$name"
    fi
    safe_cp "$d/SOUL.md" "$dest/$name/SOUL.md"
    safe_cp "$d/AGENTS.md" "$dest/$name/AGENTS.md"
    safe_cp "$d/IDENTITY.md" "$dest/$name/IDENTITY.md"

    # Register with OpenClaw if available (only in live mode)
    if ! $DRY_RUN && command -v openclaw >/dev/null 2>&1; then
      openclaw agents add "$name" --workspace "$dest/$name" --non-interactive 2>/dev/null || true
    fi
    count=$((count + 1))
  done < <(find "$src" -mindepth 1 -maxdepth 1 -type d -print0)

  ok "OpenClaw: $count workspaces -> $dest"
  if command -v openclaw >/dev/null 2>&1 && ! $DRY_RUN; then
    warn "OpenClaw: run 'openclaw gateway restart' to activate new agents"
  fi
}

install_cursor() {
  confirm_pwd_once "Cursor" || return 0

  local src="$INTEGRATIONS/cursor/rules"
  local dest="${PWD}/.cursor/rules"
  local count=0
  [[ -d "$src" ]] || { err "integrations/cursor missing. Run convert.sh first."; return 1; }

  if $DRY_RUN; then
    dim "  [dry-run] Cursor -> $dest"
  else
    mkdir -p "$dest"
  fi

  local f
  while IFS= read -r -d '' f; do
    safe_cp "$f" "$dest/$(basename "$f")"
    count=$((count + 1))
  done < <(find "$src" -maxdepth 1 -name "*.mdc" -print0)
  ok "Cursor: $count rules -> $dest"
}

install_aider() {
  confirm_pwd_once "Aider" || return 0

  local src="$INTEGRATIONS/aider/CONVENTIONS.md"
  local dest="${PWD}/CONVENTIONS.md"
  [[ -f "$src" ]] || { err "integrations/aider/CONVENTIONS.md missing. Run convert.sh first."; return 1; }

  safe_cp "$src" "$dest"
  ok "Aider: installed -> $dest"
}

install_windsurf() {
  confirm_pwd_once "Windsurf" || return 0

  local src="$INTEGRATIONS/windsurf/.windsurfrules"
  local dest="${PWD}/.windsurfrules"
  [[ -f "$src" ]] || { err "integrations/windsurf/.windsurfrules missing. Run convert.sh first."; return 1; }

  safe_cp "$src" "$dest"
  ok "Windsurf: installed -> $dest"
}

install_tool() {
  case "$1" in
    claude-code) install_claude_code ;;
    copilot)     install_copilot     ;;
    antigravity) install_antigravity ;;
    gemini-cli)  install_gemini_cli  ;;
    opencode)    install_opencode    ;;
    openclaw)    install_openclaw    ;;
    cursor)      install_cursor      ;;
    aider)       install_aider       ;;
    windsurf)    install_windsurf    ;;
  esac
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
  local tool="all"
  local interactive_mode="auto"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tool)            tool="${2:?'--tool requires a value'}"; shift 2; interactive_mode="no" ;;
      --interactive)     interactive_mode="yes"; shift ;;
      --no-interactive)  interactive_mode="no"; shift ;;
      --dry-run)         DRY_RUN=true; shift ;;
      --force)           FORCE=true; shift ;;
      --skip-lint)       SKIP_LINT=true; shift ;;
      --help|-h)         usage ;;
      *)                 err "Unknown option: $1"; usage ;;
    esac
  done

  check_integrations

  # Validate explicit tool
  if [[ "$tool" != "all" ]]; then
    local valid=false t
    for t in "${ALL_TOOLS[@]}"; do [[ "$t" == "$tool" ]] && valid=true && break; done
    if ! $valid; then
      err "Unknown tool '$tool'. Valid: ${ALL_TOOLS[*]}"
      exit 1
    fi
  fi

  # Decide whether to show interactive UI
  local use_interactive=false
  if   [[ "$interactive_mode" == "yes" ]]; then
    use_interactive=true
  elif [[ "$interactive_mode" == "auto" && -t 0 && -t 1 && "$tool" == "all" ]]; then
    use_interactive=true
  fi

  SELECTED_TOOLS=()

  if $use_interactive; then
    interactive_select
  elif [[ "$tool" != "all" ]]; then
    SELECTED_TOOLS=("$tool")
  else
    header "The Agency -- Scanning for installed tools..."
    printf "\n"
    local t
    for t in "${ALL_TOOLS[@]}"; do
      if is_detected "$t" 2>/dev/null; then
        SELECTED_TOOLS+=("$t")
        printf "  ${C_GREEN}[*]${C_RESET}  %s  ${C_DIM}detected${C_RESET}\n" "$(tool_label "$t")"
      else
        printf "  ${C_DIM}[ ]  %s  not found${C_RESET}\n" "$(tool_label "$t")"
      fi
    done
  fi

  if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
    warn "No tools selected or detected. Nothing to install."
    printf "\n"
    dim "  Tip: use --tool <name> to force-install a specific tool."
    dim "  Available: ${ALL_TOOLS[*]}"
    exit 0
  fi

  # --- Security preflight ---
  run_lint_preflight

  # --- Dry-run banner ---
  if $DRY_RUN; then
    printf "\n"
    box_top
    box_row "${C_YELLOW}${C_BOLD}  DRY RUN — no files will be written${C_RESET}"
    box_bot
    printf "\n"
  fi

  # --- Install ---
  printf "\n"
  header "The Agency -- Installing agents"
  printf "  Repo:       %s\n" "$REPO_ROOT"
  printf "  Installing: %s\n" "${SELECTED_TOOLS[*]}"
  if $DRY_RUN; then printf "  Mode:       ${C_YELLOW}dry-run${C_RESET}\n"; fi
  if $FORCE; then printf "  Mode:       ${C_RED}force (no backups)${C_RESET}\n"; fi
  printf "\n"

  local installed=0 t
  for t in "${SELECTED_TOOLS[@]}"; do
    install_tool "$t"
    installed=$((installed + 1))
  done

  # --- Done ---
  if $DRY_RUN; then
    local msg="  Dry run complete. $installed tool(s) previewed."
    printf "\n"
    box_top
    box_row "${C_YELLOW}${C_BOLD}${msg}${C_RESET}"
    box_bot
    printf "\n"
    dim "  Remove --dry-run to install for real."
  else
    local msg="  Done!  Installed $installed tool(s)."
    printf "\n"
    box_top
    box_row "${C_GREEN}${C_BOLD}${msg}${C_RESET}"
    box_bot
    printf "\n"
    dim "  Run ./scripts/convert.sh to regenerate after adding or editing agents."
  fi
  printf "\n"
}

main "$@"
