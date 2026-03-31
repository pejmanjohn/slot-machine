#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_SOURCE_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_REPO="${SLOT_MACHINE_SOURCE_REPO:-$DEFAULT_SOURCE_REPO}"
LINK_DIR="${CLAUDE_SLOT_MACHINE_LINK_DIR:-$HOME/.claude/skills}"
PULL_SOURCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-repo)
            SOURCE_REPO="$2"
            shift 2
            ;;
        --link-dir)
            LINK_DIR="$2"
            shift 2
            ;;
        --pull)
            PULL_SOURCE=true
            shift
            ;;
        --help|-h)
            cat <<'EOF'
Usage: install-claude-skill.sh [options]

Options:
  --source-repo PATH  Source checkout to install from
  --link-dir PATH     Claude skill link directory (default: ~/.claude/skills)
  --pull              Run git pull --ff-only in the source repo before installing
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

SOURCE_REPO="$(cd "$SOURCE_REPO" && pwd -P)"
LINK_PATH="$LINK_DIR/slot-machine"

if [ ! -f "$SOURCE_REPO/SKILL.md" ]; then
    echo "Source repo does not look like slot-machine: missing $SOURCE_REPO/SKILL.md" >&2
    exit 1
fi

if [ "$PULL_SOURCE" = true ]; then
    git -C "$SOURCE_REPO" pull --ff-only
fi

mkdir -p "$LINK_DIR"
rm -rf "$LINK_PATH"
ln -s "$SOURCE_REPO" "$LINK_PATH"

echo "Installed Claude skill link at $LINK_PATH"
