#!/usr/bin/env bash
# Source this file (do not execute) so your shell gets ROS + this workspace:
#   source ~/ros2_ws/scripts/setup_ros_env.bash
#
# ROS 2 / colcon / ament setup scripts break under bash `set -u` (nounset).
# This wrapper temporarily disables nounset only while sourcing.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Run: source ${BASH_SOURCE[0]}" >&2
  exit 1
fi

if [[ "${-}" == *u* ]]; then
  set +u
  _igvc_restore_nounset=1
fi

_ROS_DISTRO="${ROS_DISTRO:-humble}"
if [[ -f "/opt/ros/${_ROS_DISTRO}/setup.bash" ]]; then
  # shellcheck source=/dev/null
  source "/opt/ros/${_ROS_DISTRO}/setup.bash"
else
  echo "Missing /opt/ros/${_ROS_DISTRO}/setup.bash" >&2
  [[ "${_igvc_restore_nounset:-}" == 1 ]] && set -u
  unset _ROS_DISTRO
  return 1 2>/dev/null || exit 1
fi
unset _ROS_DISTRO

_WS_ROOT="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${_WS_ROOT}/install/setup.bash" ]]; then
  # shellcheck source=/dev/null
  source "${_WS_ROOT}/install/setup.bash"
else
  echo "Missing ${_WS_ROOT}/install/setup.bash — run colcon build in the workspace." >&2
  [[ "${_igvc_restore_nounset:-}" == 1 ]] && set -u
  unset _WS_ROOT
  return 1 2>/dev/null || exit 1
fi
unset _WS_ROOT

if [[ "${_igvc_restore_nounset:-}" == 1 ]]; then
  set -u
  unset _igvc_restore_nounset
fi
