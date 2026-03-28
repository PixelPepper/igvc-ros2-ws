#!/usr/bin/env bash
# Run once on the Jetson (with sudo). Installs ROBOTIS OpenCR udev rules so ModemManager
# does not grab the board and permissions allow dialout access without surprises.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_SRC="$SCRIPT_DIR/udev/99-opencr-cdc.rules"
RULES_DST="/etc/udev/rules.d/99-opencr-cdc.rules"

if [[ ! -f "$RULES_SRC" ]]; then
  echo "Missing $RULES_SRC" >&2
  exit 1
fi

echo "Installing OpenCR udev rules to $RULES_DST"
sudo cp "$RULES_SRC" "$RULES_DST"
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "Done. Unplug/replug OpenCR USB, then check: ls -l /dev/ttyACM*"
