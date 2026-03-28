#!/usr/bin/env bash
# Run on your x86_64 Ubuntu laptop in a LOCAL terminal (not inside SSH to the Jetson)
# while the OpenCR micro-USB is plugged into the laptop — for turtlebot3_setup_motor.
#
# ROS never runs on the laptop for this step. You are only programming motor IDs on the
# XL430s through OpenCR. After this, move OpenCR USB to the Jetson, flash Burger ROS 2
# firmware, then launch turtlebot3_base on the Jetson (see repo scripts below).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

arch=$(uname -m)
if [[ "$arch" != "x86_64" ]]; then
  echo "ERROR: OpenCR Arduino core is not available for arch=$arch."
  echo "Run this script on an x86_64 PC with OpenCR connected via USB."
  exit 1
fi

echo "=== How this connects to the Jetson ==="
echo "Laptop (this machine): upload turtlebot3_setup_motor → OpenCR talks on the Dynamixel"
echo "  bus and assigns left/right XL430 IDs. Use motor power (e.g. 12 V SMPS) as in the manual."
echo "Jetson: USB to OpenCR + Burger .opencr firmware → turtlebot3_node uses serial at 1M baud"
echo "  (see config/turtlebot3_burger.yaml) to read encoders, IMU, and command wheels."
echo ""

echo "=== OpenCR laptop prerequisites ==="
echo "Architecture: OK ($arch)"
if groups | grep -qw dialout; then
  echo "dialout group: OK"
else
  echo "WARN: add serial access:  sudo usermod -aG dialout \"\$USER\""
  echo "      Then log out and back in (or reboot)."
fi

echo ""
echo "=== USB serial devices (unplug/replug OpenCR to spot the right node) ==="
shopt -s nullglob
acms=(/dev/ttyACM*)
if ((${#acms[@]})); then
  ls -la "${acms[@]}"
  if ((${#acms[@]} > 1)); then
    echo ""
    echo "NOTE: Multiple ttyACM* devices — identify OpenCR before picking Tools → Port:"
    echo "  Unplug OpenCR USB, run:  ls /dev/ttyACM*"
    echo "  Plug OpenCR back in, run again — the new or changed node is usually OpenCR."
    echo "  Or:  udevadm info -q property -n /dev/ttyACM0 | grep -E 'ID_VENDOR_ID|ID_MODEL'"
    echo "  OpenCR CDC often shows idVendor=0483 (STMicro)."
  fi
else
  echo "(none) — connect OpenCR micro-USB to this laptop."
fi
shopt -u nullglob

if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import serial.tools.list_ports" 2>/dev/null; then
    echo ""
    echo "=== serial.tools.list_ports (pyserial) ==="
    python3 -m serial.tools.list_ports -v 2>/dev/null || true
  fi
fi

echo ""
echo "=== Arduino IDE — motor setup (Phase A) ==="
echo "Rule: power off, connect only ONE XL430 at a time to the Dynamixel bus while running setup."
echo ""
echo "1) File → Preferences → Additional boards manager URLs:"
echo "   https://raw.githubusercontent.com/ROBOTIS-GIT/OpenCR/master/arduino/opencr_release/package_opencr_index.json"
echo "2) Tools → Board → Boards Manager → install \"OpenCR\"."
echo "3) Tools → Board → OpenCR Board; Tools → Port → pick the ttyACM* above."
echo "4) File → Examples → turtlebot3 → turtlebot3_setup → turtlebot3_setup_motor → Upload."
echo "5) Tools → Serial Monitor — set baud to match the sketch (see Serial.begin in the .ino)."
echo "   Follow prompts: LEFT motor (only that XL430), then power off, swap wire, RIGHT motor."
echo "   Official guide: https://emanual.robotis.com/docs/en/platform/turtlebot3/faq/#setup-dynamixels-for-turtlebot3"
echo ""
echo "6) Power off, reconnect BOTH wheel motors to OpenCR. Optional hardware check: long-press"
echo "   SW1/SW2 on OpenCR — wheels should jog if wiring and motor power are good."
echo ""
echo "=== Handoff to Jetson (Phase B — required for ROS / Dynamixel control from Jetson) ==="
echo "1) Unplug OpenCR USB from this laptop; plug OpenCR USB into the Jetson."
echo "2) On Jetson (once):  $REPO_ROOT/scripts/opencr_jetson_install_udev.sh"
echo "3) On Jetson:         OPENCR_PORT=/dev/ttyACM0 $REPO_ROOT/scripts/opencr_jetson_flash_burger.sh"
echo "   (use the ttyACM* that appears when only OpenCR is connected — ls -l /dev/ttyACM*)"
echo "4) On Jetson:         $REPO_ROOT/scripts/verify_turtlebot3_base.sh"
echo "   Or: ros2 launch igvc_robot turtlebot3_base.launch.py opencr_port:=/dev/ttyACM0"
echo ""
echo "If verify fails with \"Failed connection with Devices\", motor IDs, power, or daisy-chain"
echo "are still wrong — repeat motor setup on the laptop, then re-flash Burger on the Jetson."
