#!/bin/zsh
#
# nbm-trust.sh — Network Baseline Monitor: trust current network
#
# Marks the current network state as trusted and saves it as the baseline.
#
# Usage:
#   Direct:
#     ./scripts/nbm-trust.sh           # interactive, asks for confirmation
#     ./scripts/nbm-trust.sh --yes     # skip confirmation
#     ./scripts/nbm-trust.sh --force   # overwrite existing baseline
#     ./scripts/nbm-trust.sh -yf       # skip confirm + overwrite
#
#   Source:
#     source scripts/nbm-trust.sh
#     nbm_trust --yes                  # call from another script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/nbm-snapshot.sh"

# ---- main function -----------------------------------------------------

# nbm_trust [--yes] [--force]
# Collects current network state, adds trusted_at, and saves to baseline.
# --yes    skip interactive confirmation
# --force  overwrite existing baseline without asking
nbm_trust() {
  local opt_yes=false
  local opt_force=false

  for arg in "$@"; do
    case "$arg" in
      -y|--yes)   opt_yes=true ;;
      -f|--force) opt_force=true ;;
      -yf|-fy)    opt_yes=true; opt_force=true ;;
      -h|--help)
        echo "Usage: nbm_trust [--yes] [--force]"
        echo ""
        echo "  --yes     Skip confirmation prompt"
        echo "  --force   Overwrite existing baseline without asking"
        echo "  --help    Show this message"
        return 0
        ;;
      *)
        echo "Unknown option: $arg" >&2
        return 2
        ;;
    esac
  done

  # --- pre-checks ---
  if [ -f "$NBM_SNAPSHOT_FILE" ] && [ "$opt_force" != true ]; then
    echo "Baseline already exists at $NBM_SNAPSHOT_FILE" >&2
    echo "Use --force to overwrite." >&2
    return 1
  fi

  # --- confirmation ---
  if [ "$opt_yes" != true ]; then
    echo "This will save the current network state as the trusted baseline."
    echo "File: $NBM_SNAPSHOT_FILE"
    echo ""
    printf "Continue? [y/N] "
    read -r reply
    case "$reply" in
      [yY]|[yY][eE][sS]) ;;
      *) echo "Aborted." >&2; return 0 ;;
    esac
  fi

  # --- collect and annotate ---
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local snapshot annotated
  snapshot="$(nbm_snapshot_collect)"

  # Insert trusted_at into the JSON before "source".
  #   collected_at = snapshot capture time (set by nbm_snapshot_collect)
  #   trusted_at   = time when user confirmed this as the trusted baseline
  annotated="$(echo "$snapshot" | sed '/  "source":/i\
  "trusted_at": "'"$now"'",
')"

  # --- save ---
  local dir
  dir="$(dirname "$NBM_SNAPSHOT_FILE")"
  mkdir -p "$dir" 2>/dev/null
  echo "$annotated" > "$NBM_SNAPSHOT_FILE"

  echo "Baseline trusted and saved."
  echo "File: $NBM_SNAPSHOT_FILE"
}

# ---- direct invocation guard --------------------------------------------
# Only call nbm_trust when executed directly, not when sourced.
if [[ -n "${ZSH_EVAL_CONTEXT:-}" ]]; then
  # zsh
  if [[ "${ZSH_EVAL_CONTEXT}" =~ "toplevel" ]]; then
    nbm_trust "$@"
  fi
elif [[ "${BASH_SOURCE[0]:-}" = "$0" ]]; then
  # bash
  nbm_trust "$@"
fi
