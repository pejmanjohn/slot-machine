#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${1:-$HOME/.agents/skills/slot-machine}"
SOURCE_REPO="${2:-$(cd "$SCRIPT_DIR/.." && pwd)}"

exec bash "$SCRIPT_DIR/build-codex-runtime-skill.sh" "$DEST_DIR" "$SOURCE_REPO"
