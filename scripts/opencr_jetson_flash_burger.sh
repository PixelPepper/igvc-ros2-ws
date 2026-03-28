#!/usr/bin/env bash
# Run on Jetson with OpenCR USB connected to the Jetson (after PC motor setup).
set -euo pipefail

MODEL="${OPENCR_MODEL:-burger}"
ARCHIVE_URL="https://github.com/ROBOTIS-GIT/OpenCR-Binaries/raw/master/turtlebot3/ROS2/latest/opencr_update.tar.bz2"
WORKDIR="${OPENCR_HOME:-$HOME}"

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
    echo "Set OPENCR_PORT=/dev/ttyACM0 (or the one that is OpenCR)." >&2
    return 1
  fi
  echo "No /dev/ttyACM* — plug OpenCR into this Jetson." >&2
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

echo "Using OpenCR port: $PORT  model: $MODEL"

if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q '^armhf$'; then
  echo "Adding armhf architecture (required by OpenCR updater)..."
  sudo dpkg --add-architecture armhf
fi

if ! dpkg -l libc6:armhf 2>/dev/null | grep -q '^ii'; then
  echo "Installing libc6:armhf..."
  sudo apt-get update
  sudo apt-get install -y libc6:armhf
fi

cd "$WORKDIR"
rm -rf opencr_update opencr_bundle
echo "Downloading firmware bundle..."
wget -O opencr_bundle "$ARCHIVE_URL"
# Upstream file is named *.tar.bz2 but is often gzip-compressed on raw.githubusercontent.com
if tar -xzf opencr_bundle 2>/dev/null; then
  :
elif tar -xjf opencr_bundle 2>/dev/null; then
  :
else
  echo "Could not extract firmware bundle (expected gzip or bzip2 tar)." >&2
  file opencr_bundle >&2
  exit 1
fi
rm -f opencr_bundle
cd opencr_update

FW="${MODEL}.opencr"
if [[ ! -f "$FW" ]]; then
  echo "Missing $FW in $(pwd)" >&2
  exit 1
fi

echo "Flashing $FW to $PORT (recovery: hold SW2, press RESET, release RESET, release SW2, retry)..."
./update.sh "$PORT" "$FW"
echo "Done."
