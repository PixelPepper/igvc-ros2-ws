#!/usr/bin/env bash
# Flash the opencr_direct_ps4 custom firmware onto the OpenCR from the Jetson.
#
# The .opencr binary is pre-built on x86_64 via scripts/opencr_build_ps4_firmware.sh
# and committed to the repo at firmware/opencr_direct_ps4/opencr_direct_ps4.opencr.
#
# This script downloads the ROBOTIS OpenCR update bundle (once) to obtain
# opencr_ld_shell_arm, the ARM32 serial flasher, which works on aarch64 Jetson
# via libc6:armhf.
#
# Usage:
#   OPENCR_PORT=/dev/ttyACM0 ./scripts/opencr_jetson_flash_ps4.sh
#
# Recovery if upload fails: hold SW2, press RESET, release RESET, release SW2,
# then retry.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FW_NAME="opencr_direct_ps4"
OPENCR_FILE="$REPO_ROOT/firmware/opencr_direct_ps4/${FW_NAME}.opencr"
BUNDLE_URL="https://github.com/ROBOTIS-GIT/OpenCR-Binaries/raw/master/turtlebot3/ROS2/latest/opencr_update.tar.bz2"
BUNDLE_DIR="${OPENCR_UPDATE_DIR:-$HOME/opencr_update}"
FLASHER_CACHE="${BUNDLE_DIR}/opencr_ld_shell_arm"

if [[ ! -f "$OPENCR_FILE" ]]; then
  echo "Firmware not found: $OPENCR_FILE" >&2
  echo "Build it on x86_64: ./scripts/opencr_build_ps4_firmware.sh" >&2
  exit 1
fi

detect_port() {
  shopt -s nullglob
  local a=(/dev/ttyACM*)
  shopt -u nullglob
  if ((${#a[@]} == 1)); then
    echo "${a[0]}"
    return
  fi
  if ((${#a[@]} > 1)); then
    echo "Multiple ACM devices: ${a[*]}" >&2
    echo "Set OPENCR_PORT to the correct one (OpenCR has idVendor=0483)." >&2
    return 1
  fi
  echo "No /dev/ttyACM* found — plug the OpenCR into the Jetson." >&2
  return 1
}

PORT="${OPENCR_PORT:-}"
if [[ -z "$PORT" ]]; then
  PORT=$(detect_port) || exit 1
fi
if [[ ! -e "$PORT" ]]; then
  echo "Port not found: $PORT" >&2
  exit 1
fi

# Install libc6:armhf so the ARM32 opencr_ld_shell_arm binary can run on aarch64.
if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q '^armhf$'; then
  echo "Adding armhf architecture (required by opencr_ld_shell_arm)..."
  sudo dpkg --add-architecture armhf
fi
if ! dpkg -l libc6:armhf 2>/dev/null | grep -q '^ii'; then
  echo "Installing libc6:armhf..."
  sudo apt-get update -qq
  sudo apt-get install -y libc6:armhf
fi

# Download and cache the ROBOTIS bundle if the ARM flasher isn't present yet.
if [[ ! -x "$FLASHER_CACHE" ]]; then
  echo "Downloading ROBOTIS OpenCR update bundle (one-time, for opencr_ld_shell_arm)..."
  TMP_BUNDLE="$(mktemp)"
  wget -qO "$TMP_BUNDLE" "$BUNDLE_URL"
  mkdir -p "$BUNDLE_DIR"
  # The bundle is uploaded as .tar.bz2 but GitHub serves it as gzip.
  if tar -xzf "$TMP_BUNDLE" -C "$(dirname "$BUNDLE_DIR")" 2>/dev/null; then
    :
  elif tar -xjf "$TMP_BUNDLE" -C "$(dirname "$BUNDLE_DIR")" 2>/dev/null; then
    :
  else
    echo "Could not extract firmware bundle." >&2
    file "$TMP_BUNDLE" >&2
    rm -f "$TMP_BUNDLE"
    exit 1
  fi
  rm -f "$TMP_BUNDLE"
  chmod +x "$BUNDLE_DIR/opencr_ld_shell_arm"
fi

if [[ ! -x "$FLASHER_CACHE" ]]; then
  echo "opencr_ld_shell_arm not found at $FLASHER_CACHE after bundle extraction." >&2
  exit 1
fi

echo "Using OpenCR port: $PORT"
echo "Firmware:          $OPENCR_FILE"
echo "Flasher:           $FLASHER_CACHE"
echo ""
echo "Flashing... (recovery: hold SW2, press RESET, release RESET, release SW2, retry)"
"$FLASHER_CACHE" "$PORT" 115200 "$OPENCR_FILE" 1
echo ""
echo "Done. Firmware opencr_direct_ps4 flashed to $PORT."
echo ""
echo "Run the PS4 bridge:"
echo "  python3 $REPO_ROOT/scripts/ps4_to_opencr.py --port $PORT"
