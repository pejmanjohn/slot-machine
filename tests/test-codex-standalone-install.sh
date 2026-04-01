#!/usr/bin/env bash
# Tier 1: Validate the standalone Codex install bundle shape
set -uo pipefail

source "$(dirname "$0")/test-helpers.sh"

FAILED=0
BUILD_SCRIPT_PATH="$SKILL_DIR/scripts/build-codex-runtime-skill.sh"
INSTALL_SCRIPT_PATH="$SKILL_DIR/scripts/install-codex-skill.sh"
UPDATE_SCRIPT_PATH="$SKILL_DIR/scripts/update-codex-skill.sh"
COMPAT_SCRIPT_PATH="$SKILL_DIR/scripts/install-codex-standalone-skill.sh"
TMP_ROOT=$(mktemp -d)
DEST_DIR="$TMP_ROOT/slot-machine"
LINK_DIR="$TMP_ROOT/agents/skills"
RUNTIME_ROOT="$TMP_ROOT/codex/slot-machine"
BUNDLE_DIR="$RUNTIME_ROOT/skill"
LINK_PATH="$LINK_DIR/slot-machine"
METADATA_PATH="$BUNDLE_DIR/.slot-machine-install.json"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

echo "=== Codex Install Workflow: Scripts Exist ==="
if [ -x "$BUILD_SCRIPT_PATH" ]; then
    echo "  [PASS] Build script exists and is executable"
else
    echo "  [FAIL] Missing executable script: $BUILD_SCRIPT_PATH"
    FAILED=$((FAILED + 1))
fi

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

if [ -x "$COMPAT_SCRIPT_PATH" ]; then
    echo "  [PASS] Compatibility standalone install script exists and is executable"
else
    echo "  [FAIL] Missing executable script: $COMPAT_SCRIPT_PATH"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Standalone Codex Install: Compatibility Bundle Materialization ==="
if [ -x "$COMPAT_SCRIPT_PATH" ] && bash "$COMPAT_SCRIPT_PATH" "$DEST_DIR"; then
    echo "  [PASS] Standalone install script created bundle at $DEST_DIR"
else
    echo "  [FAIL] Standalone install script failed to create bundle"
    FAILED=$((FAILED + 1))
fi

if [ -e "$DEST_DIR/SKILL.md" ] && [ ! -L "$DEST_DIR/SKILL.md" ]; then
    echo "  [PASS] Standalone bundle has a real SKILL.md file"
else
    echo "  [FAIL] Standalone bundle must create a real SKILL.md file"
    FAILED=$((FAILED + 1))
fi

if [ -f "$DEST_DIR/SKILL.md" ] && cmp -s "$SKILL_DIR/SKILL.md" "$DEST_DIR/SKILL.md"; then
    echo "  [PASS] Standalone bundle SKILL.md matches repo-root SKILL.md"
else
    echo "  [FAIL] Standalone bundle SKILL.md must match repo-root SKILL.md"
    FAILED=$((FAILED + 1))
fi

for relative_path in \
    profiles/coding/0-profile.md \
    tests/fixtures/sample-metrics.json \
    scripts/codex-slot-runner.py \
    references/orchestrator-trace.md \
    references/harness-execution.md \
    references/result-artifacts.md; do
    if [ -e "$DEST_DIR/$relative_path" ]; then
        echo "  [PASS] Standalone bundle exposes $relative_path"
    else
        echo "  [FAIL] Standalone bundle missing $relative_path"
        FAILED=$((FAILED + 1))
    fi
done

if [ -e "$DEST_DIR/.codex-plugin" ]; then
    echo "  [FAIL] Standalone Codex bundle must not include .codex-plugin metadata"
    FAILED=$((FAILED + 1))
else
    echo "  [PASS] Standalone Codex bundle omits .codex-plugin metadata"
fi

echo ""
echo "=== Codex Install Workflow: Default Install ==="
if [ -x "$INSTALL_SCRIPT_PATH" ] && \
   CODEX_SLOT_MACHINE_LINK_DIR="$LINK_DIR" \
   CODEX_SLOT_MACHINE_RUNTIME_ROOT="$RUNTIME_ROOT" \
   bash "$INSTALL_SCRIPT_PATH"; then
    echo "  [PASS] Install script created runtime bundle and skill link"
else
    echo "  [FAIL] Install script failed"
    FAILED=$((FAILED + 1))
fi

if [ -L "$LINK_PATH" ] && [ "$(readlink "$LINK_PATH")" = "$BUNDLE_DIR" ]; then
    echo "  [PASS] Install script points the Codex skill link at the runtime bundle"
else
    echo "  [FAIL] Install script must symlink $LINK_PATH to $BUNDLE_DIR"
    FAILED=$((FAILED + 1))
fi

if [ -f "$METADATA_PATH" ]; then
    echo "  [PASS] Install script writes runtime metadata"
else
    echo "  [FAIL] Install script must write runtime metadata"
    FAILED=$((FAILED + 1))
fi

echo "BROKEN" > "$BUNDLE_DIR/SKILL.md"

echo ""
echo "=== Codex Install Workflow: Update ==="
if [ -x "$UPDATE_SCRIPT_PATH" ] && \
   CODEX_SLOT_MACHINE_LINK_DIR="$LINK_DIR" \
   CODEX_SLOT_MACHINE_RUNTIME_ROOT="$RUNTIME_ROOT" \
   bash "$UPDATE_SCRIPT_PATH"; then
    echo "  [PASS] Update script refreshed the runtime bundle"
else
    echo "  [FAIL] Update script failed"
    FAILED=$((FAILED + 1))
fi

if [ -f "$BUNDLE_DIR/SKILL.md" ] && cmp -s "$SKILL_DIR/SKILL.md" "$BUNDLE_DIR/SKILL.md"; then
    echo "  [PASS] Update script restored SKILL.md from the source repo"
else
    echo "  [FAIL] Update script must restore SKILL.md from the source repo"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=== Standalone Codex Install Tests Complete ==="
echo "Failures: $FAILED"
exit $FAILED
