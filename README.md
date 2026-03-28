# IGVC ROS 2 workspace (Humble)

ROS 2 Humble workspace for IGVC: `igvc_robot` (TurtleBot3 / localization), RPLidar (`sllidar_ros2`), and u-blox GPS (`ublox`).

## Prerequisites

- **Ubuntu 22.04** (or another OS with **ROS 2 Humble** installed the same way as on Ubuntu).
- ROS 2 Humble: [Install](https://docs.ros.org/en/humble/Installation.html).
- Build tools:

```bash
sudo apt update
sudo apt install -y python3-colcon-common-extensions python3-rosdep git
```

- Robot-specific packages (adjust if you omit hardware):

```bash
sudo apt install -y ros-humble-turtlebot3 ros-humble-robot-localization
```

Set the TurtleBot model once per shell (or add to `~/.bashrc`):

```bash
export TURTLEBOT3_MODEL=burger
```

## Clone and build

```bash
git clone https://github.com/csucaimeigvc/igvc-ros2-ws.git igvc_ros2_ws
cd igvc_ros2_ws
```

If you use SSH and have keys set up with GitHub:

```bash
git clone git@github.com:csucaimeigvc/igvc-ros2-ws.git igvc_ros2_ws
cd igvc_ros2_ws
```

Then install dependencies and build:

```bash
# One-time: register rosdep rules
sudo rosdep init   # skip if you already ran this on the machine
rosdep update

# Install declared dependencies from all packages under src/
rosdep install --from-paths src --ignore-src -r -y

source /opt/ros/humble/setup.bash
colcon build --symlink-install
source install/setup.bash
```

Use every new terminal:

```bash
cd igvc_ros2_ws
source /opt/ros/humble/setup.bash
source install/setup.bash
```

## Quick checks

```bash
ros2 pkg list | grep -E 'igvc_robot|sllidar|ublox'
```

## Launch examples

```bash
# TurtleBot3 base (set OpenCR serial port for your machine)
ros2 launch igvc_robot turtlebot3_base.launch.py opencr_port:=/dev/ttyACM0

# Base + EKF / localization stack
ros2 launch igvc_robot turtlebot3_localization.launch.py opencr_port:=/dev/ttyACM0
```

More context: [docs/TURTLEBOT3_OPENCR_SETUP_CHAT_SUMMARY.md](docs/TURTLEBOT3_OPENCR_SETUP_CHAT_SUMMARY.md).

After laptop motor setup, flash on Jetson and plan Nav2 integration: [docs/JETSON_HANDOFF_AND_NAV2.md](docs/JETSON_HANDOFF_AND_NAV2.md).

## Repository layout

| Path | Role |
|------|------|
| `src/igvc_robot` | Launches, params, TurtleBot3 + localization integration |
| `src/sllidar_ros2` | Slamtec RPLidar ROS 2 driver |
| `src/ublox` | u-blox GPS driver stack |
| `ping_pong` | Optional Arduino encoder sketch (legacy bridge path) |

## Troubleshooting

**`COLCON_TRACE`, `AMENT_TRACE_SETUP_FILES`, or other “unbound variable” when sourcing ROS:** Your shell has `set -u` (nounset). ROS 2 and colcon setup scripts assume many optional variables may be unset.

Use the workspace helper (recommended):

```bash
source ~/ros2_ws/scripts/setup_ros_env.bash
```

Or disable nounset only for sourcing:

```bash
set +u
source /opt/ros/humble/setup.bash
source install/setup.bash
set -u
```

## License

Per-package licenses are in each package’s `package.xml` / upstream files (e.g. BSD for `sllidar_ros2`, MIT for `igvc_robot`).
