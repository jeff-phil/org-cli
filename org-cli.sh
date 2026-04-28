#!/usr/bin/env bash
# org-cli.sh — Standalone CLI wrapper for org-cli.el
#
# Provides a clean command-line interface to all org-cli.el functions.
# Can be used directly from any coding agent or shell.
#
# Usage:
#   org-cli.sh <command> [args...]
#   org-cli.sh --help
#
# Environment:
#   ORG_CLI_DIR     — Directory containing org-cli.el (default: script's own directory)
#   ORG_CLI_INIT_EL — Path to Emacs init file to load (default: none)
#   EMACS           — Path to emacs binary (default: emacs)

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORG_CLI_DIR="${ORG_CLI_DIR:-$SCRIPT_DIR}"
ORG_CLI_INIT_EL="${ORG_CLI_INIT_EL:-}"
EMACS="${EMACS:-emacs}"

# ---------------------------------------------------------------------------
# Help / Usage
# ---------------------------------------------------------------------------

usage() {
    cat <<EOF
org-cli — CLI tool for Org-mode files

Usage: org-cli.sh <command> [args...]

Commands:
  get-todo-config                        Get TODO keyword configuration
  get-tag-config                         Get tag configuration
  get-allowed-files                      List allowed Org files

  read-file FILE                         Read complete Org file contents
  read-outline FILE                      Read hierarchical outline of Org file
  read-headline FILE HEADLINE-PATH       Read specific headline by path
  read-by-id UUID                        Read headline by its ID property

  list-todos FILE [HEADLINE-PATH] [FORMAT]
                                         List TODO items
                                         FORMAT: json (default), markdown, or kanban

  update-todo-state URI CURRENT NEW      Update TODO state of a headline
  add-todo TITLE STATE PARENT-URI [TAGS] [BODY] [AFTER-URI]
                                         Add a new TODO item
  rename-headline URI CURRENT-TITLE NEW-TITLE
                                         Rename a headline
  edit-body URI OLD-BODY NEW-BODY [REPLACE-ALL]
                                         Edit body content of a headline
  set-planning URI TYPE [TIMESTAMP]      Set/remove DEADLINE, SCHEDULED, or CLOSED

URI formats:
  org-headline:///ABSOLUTE-PATH#HEADLINE-PATH
  org-id://UUID

Options:
  --help, -h, help                       Show this help message

Notes:
  - If org-cli-allowed-files is nil, all files are allowed
  - FILE arguments accept relative paths (resolved to absolute automatically)
  - TAGS: comma-separated list (e.g. work,urgent)
  - AFTER-URI: optional, org-id:// URI of sibling to insert after
  - REPLACE-ALL: "true" or "false" (default: "false")
  - Arguments starting with @ read content from file (@- for stdin)

Environment:
  ORG_CLI_DIR      Directory containing org-cli.el (default: script's own directory)
  ORG_CLI_INIT_EL  Path to Emacs init file to load before org-cli.el (default: none)
  EMACS            Path to emacs binary (default: emacs)

Examples:
  # Read a file (relative or absolute path)
  org-cli.sh read-file notes.org
  org-cli.sh read-file /path/to/notes.org

  # List TODOs as kanban board
  org-cli.sh list-todos notes.org "" kanban

  # Read a specific headline
  org-cli.sh read-headline notes.org "Shopping%20List"

  # Read by ID
  org-cli.sh read-by-id 679329de-9af5-4c36-b892-df909a7300c3

  # Add a TODO item
  org-cli.sh add-todo "Buy milk" TODO "org-headline:///path/to/notes.org#" "shopping"

  # Update TODO state
  org-cli.sh update-todo-state "org-id://abc-123" TODO DONE

  # Set a deadline
  org-cli.sh set-planning "org-id://abc-123" deadline 2025-05-01

  # Edit body (replace entire body)
  org-cli.sh edit-body "org-id://abc-123" "" "New body content"

  # Read body from stdin
  org-cli.sh edit-body "org-id://abc-123" @- "New body content"

  # Use custom Emacs init for org-todo-keywords / org-tag-alist
  ORG_CLI_INIT_EL=~/.emacs.d/init.el org-cli.sh get-todo-config

  # Use a different Emacs build
  EMACS=/opt/homebrew/bin/emacs org-cli.sh list-todos notes.org "" kanban
EOF
}

# ---------------------------------------------------------------------------
# Resolve relative file paths to absolute
# ---------------------------------------------------------------------------

# Commands where the first positional arg is a FILE path.
FILE_ARG_COMMANDS="read-file read-outline read-headline list-todos"

# Resolve a single path to absolute if it's relative.
# Leaves empty strings, @-prefixed args, and absolute paths unchanged.
resolve_path() {
    local p="$1"
    if [[ -z "$p" || "$p" == /* || "$p" == @* ]]; then
        echo "$p"
    else
        echo "$(cd "$(dirname "$p")" && pwd)/$(basename "$p")"
    fi
}

# ---------------------------------------------------------------------------
# Run org-cli.el via Emacs batch mode
# ---------------------------------------------------------------------------

run_org_cli() {
    if ! command -v "$EMACS" &>/dev/null; then
        echo "Error: emacs not found at '$EMACS'" >&2
        echo "       Install Emacs to use org-cli, or set EMACS to the correct path." >&2
        echo "       macOS:  brew install emacs" >&2
        echo "       Ubuntu: sudo apt install emacs" >&2
        echo "       Fedora: sudo dnf install emacs" >&2
        exit 127
    fi

    local cmd="$1"
    shift

    # Resolve the FILE argument for commands that take one
    if echo " $FILE_ARG_COMMANDS " | grep -q " $cmd " && [[ $# -gt 0 ]]; then
        set -- "$(resolve_path "$1")" "${@:2}"
    fi

    # Build the Emacs invocation
    local emacs_args=(
        --batch
        -L "$ORG_CLI_DIR"
    )

    # Optionally load init.el before org-cli
    if [[ -n "$ORG_CLI_INIT_EL" ]]; then
        if [[ ! -f "$ORG_CLI_INIT_EL" ]]; then
            echo "Error: ORG_CLI_INIT_EL not found: $ORG_CLI_INIT_EL" >&2
            exit 1
        fi
        emacs_args+=(-l "$ORG_CLI_INIT_EL")
    fi

    emacs_args+=(
        -l org-cli.el
        -f org-cli
        "$cmd"
    )

    "$EMACS" "${emacs_args[@]}" "$@"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "${1:-}" in
    --help|-h|help)
        usage
        exit 0
        ;;
    *)
        run_org_cli "$@"
        ;;
esac
