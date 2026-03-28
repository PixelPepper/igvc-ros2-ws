#!/usr/bin/env bash
# Build and package the opencr_direct_ps4 custom firmware on x86_64.
#
# Output: firmware/opencr_direct_ps4/opencr_direct_ps4.opencr
#
# Run this on the laptop (x86_64) whenever the sketch changes, then commit
# the resulting .opencr so the Jetson can flash it via
# scripts/opencr_jetson_flash_ps4.sh without needing arduino-cli.
#
# Requirements: arduino-cli + OpenCR:OpenCR core (run opencr_arduino_cli_setup.sh once).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKETCH_DIR="$REPO_ROOT/firmware/opencr_direct_ps4"
BUILD_DIR="${OPENCR_BUILD_DIR:-/tmp/opencr_ps4_build}"
FQBN="${OPENCR_FQBN:-OpenCR:OpenCR:OpenCR}"
OUT_DIR="$SKETCH_DIR"
VERSION="${OPENCR_FW_VERSION:-V260326R1}"
FW_NAME="opencr_direct_ps4"

arch=$(uname -m)
if [[ "$arch" != "x86_64" ]]; then
  echo "This script must run on x86_64. The OpenCR arduino-cli core is not available for $arch." >&2
  exit 1
fi

export PATH="$HOME/.local/bin:$PATH"
if ! command -v arduino-cli >/dev/null 2>&1; then
  echo "arduino-cli not found. Run: ./scripts/opencr_arduino_cli_setup.sh" >&2
  exit 1
fi

echo "=== Compiling $FW_NAME (FQBN: $FQBN) ==="
mkdir -p "$BUILD_DIR"
arduino-cli compile \
  --fqbn "$FQBN" \
  --build-path "$BUILD_DIR" \
  "$SKETCH_DIR"

BIN="$BUILD_DIR/${FW_NAME}.ino.bin"
if [[ ! -f "$BIN" ]]; then
  echo "Compile succeeded but expected binary not found: $BIN" >&2
  exit 1
fi

echo "=== Packaging $BIN → $OUT_DIR/${FW_NAME}.opencr ==="
python3 - <<PYEOF
import struct, sys

HEADER_SIZE = 0x508          # 1288 bytes, matches ROBOTIS bundle format
MAGIC       = b'\xaa\xaa\x55\x55'
NAME_OFF    = 0x04
NAME_LEN    = 128
VER_OFF     = 0x84
VER_LEN     = 128
PLEN_OFF    = 0x104

with open("$BIN", "rb") as f:
    payload = f.read()

header = bytearray(HEADER_SIZE)
header[0:4] = MAGIC
name_bytes = b"$FW_NAME"[:NAME_LEN - 1]
header[NAME_OFF : NAME_OFF + len(name_bytes)] = name_bytes
ver_bytes = b"$VERSION"[:VER_LEN - 1]
header[VER_OFF : VER_OFF + len(ver_bytes)] = ver_bytes
struct.pack_into('<I', header, PLEN_OFF, len(payload))

out_path = "$OUT_DIR/${FW_NAME}.opencr"
with open(out_path, "wb") as f:
    f.write(header)
    f.write(payload)

print(f"Written {len(header) + len(payload)} bytes → {out_path}")
print(f"  firmware: $FW_NAME  version: $VERSION  payload: {len(payload)} bytes")
PYEOF

echo ""
echo "Done. Commit firmware/opencr_direct_ps4/${FW_NAME}.opencr to the repo,"
echo "then flash on the Jetson with:"
echo "  OPENCR_PORT=/dev/ttyACM0 ./scripts/opencr_jetson_flash_ps4.sh"
