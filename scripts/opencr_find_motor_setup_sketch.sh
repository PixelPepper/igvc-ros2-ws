#!/usr/bin/env bash
# Print the directory containing turtlebot3_setup_motor.ino (after OpenCR core is installed).
set -euo pipefail

USER_DIR="${ARDUINO_DIRECTORIES_USER:-$HOME/.arduino15}"
HW_ROOT="$USER_DIR/packages/OpenCR/hardware/OpenCR"

if [[ ! -d "$HW_ROOT" ]]; then
  echo "OpenCR core not found under $HW_ROOT" >&2
  echo "Run: ./scripts/opencr_arduino_cli_setup.sh" >&2
  exit 1
fi

ver=$(ls -1 "$HW_ROOT" 2>/dev/null | sort -V | tail -1)
if [[ -z "$ver" ]]; then
  echo "No OpenCR core version directory under $HW_ROOT" >&2
  exit 1
fi

ino=$(find "$HW_ROOT/$ver" -name 'turtlebot3_setup_motor.ino' -print -quit 2>/dev/null || true)
if [[ -z "$ino" ]]; then
  echo "turtlebot3_setup_motor.ino not found under $HW_ROOT/$ver" >&2
  exit 1
fi

dirname "$ino"
