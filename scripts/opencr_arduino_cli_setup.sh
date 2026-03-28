#!/usr/bin/env bash
# One-time (or idempotent) Arduino CLI setup for OpenCR on x86_64 Linux — use from Cursor terminal.
# Requires: curl, network. Installs arduino-cli to ~/.local/bin if missing.
set -euo pipefail

OPENCR_INDEX_URL="https://raw.githubusercontent.com/ROBOTIS-GIT/OpenCR/master/arduino/opencr_release/package_opencr_index.json"
# FQBN from OpenCR boards.txt (vendor:arch:board_id)
OPENCR_FQBN="${OPENCR_FQBN:-OpenCR:OpenCR:OpenCR}"

arch=$(uname -m)
if [[ "$arch" != "x86_64" ]]; then
  echo "Install OpenCR core on x86_64 only (Jetson/aarch64 is not supported by the OpenCR package index)." >&2
  exit 1
fi

ensure_cli() {
  local bindir="$HOME/.local/bin"
  export PATH="$bindir:$PATH"
  if command -v arduino-cli >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$bindir"
  echo "arduino-cli not found; installing latest to $bindir ..."
  # Official script (arduino.github.io/install.sh returns 404 as of 2025); see:
  # https://docs.arduino.cc/arduino-cli/installation/
  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh |
    BINDIR="$bindir" sh
  if [[ ! -x "$bindir/arduino-cli" ]]; then
    echo "Install failed: expected $bindir/arduino-cli" >&2
    exit 1
  fi
}

ensure_cli

if ! arduino-cli config dump &>/dev/null; then
  arduino-cli config init
fi

if ! arduino-cli config dump | grep -Fq "$OPENCR_INDEX_URL"; then
  echo "Adding OpenCR board package index..."
  arduino-cli config add board_manager.additional_urls "$OPENCR_INDEX_URL"
fi

echo "Updating index and installing OpenCR:OpenCR (may take a few minutes)..."
arduino-cli core update-index
arduino-cli core install OpenCR:OpenCR

echo ""
echo "Installed. Board lines (FQBN should include $OPENCR_FQBN):"
arduino-cli board listall | grep -i opencr || true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo ""
echo "Motor setup sketch directory:"
"$REPO_ROOT/scripts/opencr_find_motor_setup_sketch.sh"
echo ""
echo "Compile:  arduino-cli compile -b $OPENCR_FQBN \"\$($REPO_ROOT/scripts/opencr_find_motor_setup_sketch.sh)\""
echo "Upload:   arduino-cli upload -p /dev/ttyACM0 -b $OPENCR_FQBN \"\$($REPO_ROOT/scripts/opencr_find_motor_setup_sketch.sh)\""
echo "Monitor:  arduino-cli monitor -p /dev/ttyACM0 -c baudrate=57600   # use sketch baud if different"
echo ""
echo "In Cursor: Terminal → Run Task → OpenCR: … (see .vscode/tasks.json)"
