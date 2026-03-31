#!/usr/bin/env bash
# Tier 1: Validate the Claude install/update workflow
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

FAILED=0
INSTALL_SCRIPT_PATH="$SKILL_DIR/scripts/install-claude-skill.sh"
UPDATE_SCRIPT_PATH="$SKILL_DIR/scripts/update-claude-skill.sh"
TMP_ROOT=$(mktemp -d)
LINK_DIR="$TMP_ROOT/claude/skills"
LINK_PATH="$LINK_DIR/slot-machine"
LEGACY_LINK_DIR="$TMP_ROOT/legacy-claude/skills"
LEGACY_LINK_PATH="$LEGACY_LINK_DIR/slot-machine"
CANONICAL_SOURCE_REPO="$(cd "$SKILL_DIR" && pwd -P)"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

echo "=== Claude Install Workflow: Scripts Exist ==="
if [ -x "$INSTALL_SCRIPT_PATH" ]; then
    echo "  [PASS] Install script exists and is executable"
else
    echo "  [FAIL] Missing executable script: $INSTALL_SCRIPT_PATH"
    FAILED=$((FAILED + 1))
fi

if [ -x "$UPDATE_SCRIPT_PATH" ]; then
    echo "  [PASS] Update script exists and is executable"
else
    echo "  [FAIL] Missing executable script: $UPDATE_SCRIPT_PATH"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Claude Install Workflow: Symlink Install ==="
if [ -x "$INSTALL_SCRIPT_PATH" ] && \
   SLOT_MACHINE_SOURCE_REPO="$SKILL_DIR" \
   CLAUDE_SLOT_MACHINE_LINK_DIR="$LINK_DIR" \
   bash "$INSTALL_SCRIPT_PATH"; then
    echo "  [PASS] Install script created Claude skill link"
else
    echo "  [FAIL] Install script failed"
    FAILED=$((FAILED + 1))
fi

if [ -L "$LINK_PATH" ] && [ "$(cd "$LINK_PATH" && pwd -P)" = "$CANONICAL_SOURCE_REPO" ]; then
    echo "  [PASS] Install script points the Claude skill link at the source repo"
else
    echo "  [FAIL] Install script must symlink $LINK_PATH to $CANONICAL_SOURCE_REPO"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Claude Install Workflow: Symlink Update ==="
if [ -x "$UPDATE_SCRIPT_PATH" ] && \
   CLAUDE_SLOT_MACHINE_LINK_DIR="$LINK_DIR" \
   bash "$UPDATE_SCRIPT_PATH"; then
    echo "  [PASS] Update script refreshed the Claude skill link from the installed symlink"
else
    echo "  [FAIL] Update script failed for a symlinked install"
    FAILED=$((FAILED + 1))
fi

if [ -L "$LINK_PATH" ] && [ "$(cd "$LINK_PATH" && pwd -P)" = "$CANONICAL_SOURCE_REPO" ]; then
    echo "  [PASS] Update script preserves the Claude skill symlink target"
else
    echo "  [FAIL] Update script must preserve the installed Claude symlink target"
    FAILED=$((FAILED + 1))
fi

mkdir -p "$LEGACY_LINK_DIR"
git clone -q "$SKILL_DIR" "$LEGACY_LINK_PATH"

echo ""
echo "=== Claude Install Workflow: Legacy Checkout Update ==="
if [ -d "$LEGACY_LINK_PATH/.git" ] && [ ! -L "$LEGACY_LINK_PATH" ]; then
    echo "  [PASS] Legacy install fixture created a direct git checkout"
else
    echo "  [FAIL] Could not create legacy Claude install fixture"
    FAILED=$((FAILED + 1))
fi

if [ -x "$UPDATE_SCRIPT_PATH" ] && \
   CLAUDE_SLOT_MACHINE_LINK_DIR="$LEGACY_LINK_DIR" \
   bash "$UPDATE_SCRIPT_PATH"; then
    echo "  [PASS] Update script supports a legacy direct-checkout install"
else
    echo "  [FAIL] Update script failed for a legacy direct-checkout install"
    FAILED=$((FAILED + 1))
fi

if [ -d "$LEGACY_LINK_PATH/.git" ] && [ ! -L "$LEGACY_LINK_PATH" ]; then
    echo "  [PASS] Legacy checkout update preserves the direct install layout"
else
    echo "  [FAIL] Update script must not replace a legacy direct checkout with a broken layout"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Claude Install Workflow Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
