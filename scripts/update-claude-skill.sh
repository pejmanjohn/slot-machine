#!/usr/bin/env bash
set -euo pipefail

LINK_DIR="${CLAUDE_SLOT_MACHINE_LINK_DIR:-$HOME/.claude/skills}"
PULL_SOURCE=false
SOURCE_REPO_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-repo)
            SOURCE_REPO_OVERRIDE="$2"
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
Usage: update-claude-skill.sh [options]

Options:
  --source-repo PATH  Override the source checkout to update from
  --link-dir PATH     Claude skill link directory (default: ~/.claude/skills)
  --pull              Run git pull --ff-only in the source repo before updating
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

is_git_checkout() {
    local candidate="$1"
    git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

LINK_PATH="$LINK_DIR/slot-machine"
SOURCE_REPO="$SOURCE_REPO_OVERRIDE"
INSTALL_LAYOUT="symlink"

if [ -z "$SOURCE_REPO" ]; then
    if [ -L "$LINK_PATH" ]; then
        SOURCE_REPO="$(cd "$LINK_PATH" && pwd -P)"
        INSTALL_LAYOUT="symlink"
    elif [ -d "$LINK_PATH" ] && is_git_checkout "$LINK_PATH"; then
        SOURCE_REPO="$LINK_PATH"
        INSTALL_LAYOUT="checkout"
    fi
fi

if [ -z "$SOURCE_REPO" ]; then
    echo "Could not determine the Claude skill source repo. Re-run install-claude-skill.sh or pass --source-repo." >&2
    exit 1
fi

SOURCE_REPO="$(cd "$SOURCE_REPO" && pwd -P)"

if [ ! -f "$SOURCE_REPO/SKILL.md" ]; then
    echo "Source repo does not look like slot-machine: missing $SOURCE_REPO/SKILL.md" >&2
    exit 1
fi

if [ "$PULL_SOURCE" = true ]; then
    git -C "$SOURCE_REPO" pull --ff-only
fi

mkdir -p "$LINK_DIR"

if [ "$INSTALL_LAYOUT" = "checkout" ] && [ -z "$SOURCE_REPO_OVERRIDE" ]; then
    echo "Updated Claude skill checkout at $LINK_PATH"
    exit 0
fi

rm -rf "$LINK_PATH"
ln -s "$SOURCE_REPO" "$LINK_PATH"

echo "Updated Claude skill link at $LINK_PATH"
