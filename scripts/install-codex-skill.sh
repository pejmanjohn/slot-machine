#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_SOURCE_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_REPO="${SLOT_MACHINE_SOURCE_REPO:-$DEFAULT_SOURCE_REPO}"
RUNTIME_ROOT="${CODEX_SLOT_MACHINE_RUNTIME_ROOT:-$HOME/.codex/slot-machine}"
LINK_DIR="${CODEX_SLOT_MACHINE_LINK_DIR:-$HOME/.agents/skills}"
PULL_SOURCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-repo)
            SOURCE_REPO="$2"
            shift 2
            ;;
        --runtime-root)
            RUNTIME_ROOT="$2"
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
Usage: install-codex-skill.sh [options]

Options:
  --source-repo PATH   Source checkout to install from
  --runtime-root PATH  Runtime root that stores the generated Codex bundle
  --link-dir PATH      Codex skill link directory (default: ~/.agents/skills)
  --pull               Run git pull --ff-only in the source repo before installing
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

SOURCE_REPO="$(cd "$SOURCE_REPO" && pwd)"
BUNDLE_DIR="$RUNTIME_ROOT/skill"
LINK_PATH="$LINK_DIR/slot-machine"

if [ "$PULL_SOURCE" = true ]; then
    git -C "$SOURCE_REPO" pull --ff-only
fi

bash "$SCRIPT_DIR/build-codex-runtime-skill.sh" "$BUNDLE_DIR" "$SOURCE_REPO"

mkdir -p "$LINK_DIR"
rm -rf "$LINK_PATH"
ln -s "$BUNDLE_DIR" "$LINK_PATH"

echo "Installed Codex skill link at $LINK_PATH"
