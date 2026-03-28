#!/usr/bin/env bash
# Run turtlebot3_setup_motor compile/upload via arduino-cli (after opencr_arduino_cli_setup.sh).
# Usage:  ./scripts/opencr_cli_motor.sh compile
#         ./scripts/opencr_cli_motor.sh upload [/dev/ttyACM0]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FQBN="${OPENCR_FQBN:-OpenCR:OpenCR:OpenCR}"
SKETCH="$("$REPO_ROOT/scripts/opencr_find_motor_setup_sketch.sh")"

cmd="${1:-}"
case "$cmd" in
compile)
  arduino-cli compile -b "$FQBN" "$SKETCH"
  ;;
upload)
  port="${2:-${OPENCR_PORT:-/dev/ttyACM0}}"
  arduino-cli upload -p "$port" -b "$FQBN" "$SKETCH"
  ;;
*)
  echo "Usage: $0 compile | upload [/dev/ttyACM0]" >&2
  echo "Env: OPENCR_FQBN (default $FQBN), OPENCR_PORT (default /dev/ttyACM0 for upload)" >&2
  exit 1
  ;;
esac
