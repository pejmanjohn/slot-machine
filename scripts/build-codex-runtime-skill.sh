#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_SOURCE_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

DEST_DIR="${1:-}"
SOURCE_REPO="${2:-$DEFAULT_SOURCE_REPO}"

if [ -z "$DEST_DIR" ]; then
    echo "Usage: $0 DEST_DIR [SOURCE_REPO]" >&2
    exit 1
fi

SOURCE_REPO="$(cd "$SOURCE_REPO" && pwd)"

if [ -z "$DEST_DIR" ] || [ "$DEST_DIR" = "/" ]; then
    echo "Refusing to build into an unsafe destination: '$DEST_DIR'" >&2
    exit 1
fi

mkdir -p "$(dirname "$DEST_DIR")"
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

cp "$SOURCE_REPO/SKILL.md" "$DEST_DIR/SKILL.md"
ln -s "$SOURCE_REPO/profiles" "$DEST_DIR/profiles"
ln -s "$SOURCE_REPO/tests" "$DEST_DIR/tests"

cat > "$DEST_DIR/.slot-machine-install.json" <<EOF
{
  "source_repo": "$SOURCE_REPO",
  "skill_name": "slot-machine",
  "bundle_format": "codex-standalone-skill"
}
EOF

echo "Built Codex runtime skill bundle at $DEST_DIR"
