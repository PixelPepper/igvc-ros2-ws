#!/usr/bin/env bash
# Run on Jetson with OpenCR on the Jetson and ROS 2 workspace built.
set -euo pipefail

WS="$(cd "$(dirname "$0")/.." && pwd)"
# ROS/colcon/ament setup scripts reference many unset optional vars; `set -u` breaks them.
set +u
# shellcheck source=/dev/null
source "$WS/install/setup.bash" || { set -u; exit 1; }
set -u

PORT="${OPENCR_PORT:-}"
if [[ -z "$PORT" ]]; then
  shopt -s nullglob
  acms=(/dev/ttyACM*)
  shopt -u nullglob
  if ((${#acms[@]} == 1)); then
    PORT="${acms[0]}"
  elif ((${#acms[@]} > 1)); then
    echo "Multiple ACM devices: ${acms[*]}"
    echo "Set OPENCR_PORT=/dev/ttyACM0 (example) and re-run."
    exit 1
  else
    echo "No /dev/ttyACM* — connect OpenCR to this Jetson."
    exit 1
  fi
fi

echo "Using opencr_port=$PORT"
echo "Launching turtlebot3_base in background, then checking topics after ~12s..."
ros2 launch igvc_robot turtlebot3_base.launch.py "opencr_port:=$PORT" &
LAUNCH_PID=$!
sleep 12

ok=1
for t in /joint_states /odom /imu; do
  if ros2 topic list 2>/dev/null | grep -qx "$t"; then
    echo "OK: topic $t"
  else
    echo "MISSING: $t"
    ok=0
  fi
done

kill -INT "$LAUNCH_PID" 2>/dev/null || true
sleep 2
wait "$LAUNCH_PID" 2>/dev/null || true

if [[ "$ok" -eq 1 ]]; then
  echo "verify_turtlebot3_base: passed (topics present while launch ran)."
  exit 0
fi
echo "verify_turtlebot3_base: failed — check OpenCR firmware, motor wiring, and port."
exit 1
