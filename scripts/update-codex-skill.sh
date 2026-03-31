#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_ROOT="${CODEX_SLOT_MACHINE_RUNTIME_ROOT:-$HOME/.codex/slot-machine}"
LINK_DIR="${CODEX_SLOT_MACHINE_LINK_DIR:-$HOME/.agents/skills}"
PULL_SOURCE=false
SOURCE_REPO_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-repo)
            SOURCE_REPO_OVERRIDE="$2"
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
Usage: update-codex-skill.sh [options]

Options:
  --source-repo PATH   Override the source checkout to update from
  --runtime-root PATH  Runtime root that stores the generated Codex bundle
  --link-dir PATH      Codex skill link directory (default: ~/.agents/skills)
  --pull               Run git pull --ff-only in the source repo before rebuilding
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

BUNDLE_DIR="$RUNTIME_ROOT/skill"
LINK_PATH="$LINK_DIR/slot-machine"
METADATA_PATH="$BUNDLE_DIR/.slot-machine-install.json"

SOURCE_REPO="$SOURCE_REPO_OVERRIDE"
if [ -z "$SOURCE_REPO" ] && [ -f "$METADATA_PATH" ]; then
    SOURCE_REPO="$(sed -n 's/.*"source_repo"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$METADATA_PATH" | head -n 1)"
fi

if [ -z "$SOURCE_REPO" ]; then
    echo "Could not determine the source repo. Re-run install-codex-skill.sh or pass --source-repo." >&2
    exit 1
fi

SOURCE_REPO="$(cd "$SOURCE_REPO" && pwd)"

if [ "$PULL_SOURCE" = true ]; then
    git -C "$SOURCE_REPO" pull --ff-only
fi

bash "$SCRIPT_DIR/build-codex-runtime-skill.sh" "$BUNDLE_DIR" "$SOURCE_REPO"

mkdir -p "$LINK_DIR"
rm -rf "$LINK_PATH"
ln -s "$BUNDLE_DIR" "$LINK_PATH"

echo "Updated Codex skill link at $LINK_PATH"
