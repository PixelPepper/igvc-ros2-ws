# Jetson handoff (after laptop motor setup) and path planning

Use this after **`turtlebot3_setup_motor`** on an x86 PC: both XL430s provisioned, then OpenCR USB moved to the Jetson.

## 1. On the Jetson — permissions and port

```bash
sudo usermod -aG dialout "$USER"
# New login (or reboot) so `groups` shows dialout
ls -l /dev/ttyACM*
```

If several `ttyACM*` devices exist, pick the one that appears when only OpenCR is plugged in (often STMicro CDC `0483`).

## 2. Flash Burger ROS 2 firmware

From the **workspace root** (this repo):

```bash
cd /path/to/igvc-ros2-ws   # or ~/ros2_ws
chmod +x scripts/opencr_jetson_flash_burger.sh   # once, if needed
OPENCR_PORT=/dev/ttyACM0 ./scripts/opencr_jetson_flash_burger.sh
```

The script installs **`libc6:armhf`** if missing (OpenCR updater requirement on ARM64).  
**Recovery:** hold **SW2**, press **RESET**, release **RESET**, release **SW2**, then re-run the script.

## 3. Hardware check

Long-press **SW1** / **SW2** — wheels should jog. If not, fix power and Dynamixel wiring before ROS.

## 4. Build workspace and smoke-test ROS

```bash
source /opt/ros/humble/setup.bash
cd /path/to/igvc-ros2-ws
colcon build --symlink-install
source install/setup.bash
export TURTLEBOT3_MODEL=burger
```

Automated check (launches base briefly, looks for topics):

```bash
OPENCR_PORT=/dev/ttyACM0 ./scripts/verify_turtlebot3_base.sh
```

Manual:

```bash
ros2 launch igvc_robot turtlebot3_base.launch.py opencr_port:=/dev/ttyACM0
# Expect /joint_states, /odom, /imu (names may be namespaced if you use namespace:=...)
```

## 5. Path planning (Nav2) — recommended packages

Your workspace does not vendor Nav2; use upstream binaries and TurtleBot3’s Nav2 bringup:

```bash
sudo apt update
sudo apt install -y ros-humble-navigation2 ros-humble-nav2-bringup ros-humble-turtlebot3-navigation2
```

Example (after you have a **map** and **localization** publishing `map` → `odom`):

```bash
export TURTLEBOT3_MODEL=burger
source /opt/ros/humble/setup.bash
source /path/to/igvc-ros2-ws/install/setup.bash
ros2 launch turtlebot3_navigation2 navigation2.launch.py map:=/full/path/to/map.yaml
```

**Reality check for IGVC:**

- Stock `turtlebot3_navigation2` assumes a **2D LiDAR scan** on the usual scan topic and consistent **TF** (`base_link`, `odom`, `map`).
- You have **`sllidar_ros2`** and **`robot_localization`** in this workspace: the next engineering step is usually:
  1. Run **RPLidar** with `frame_id` aligned to the URDF (often `base_scan` or `laser` + optional **static transform**).
  2. Choose **SLAM** (e.g. `slam_toolbox`) **or** a pre-built map + **AMCL** (or fuse GPS later).
  3. Ensure **one** publisher of **`odom` → `base_footprint`/`base_link`** (your `turtlebot3_burger.yaml` already turns off the diff-drive TF so **EKF** can own it when using `turtlebot3_localization`).
  4. Tune Nav2 **`burger`** params under `/opt/ros/humble/share/turtlebot3_navigation2/param/humble/burger.yaml` or fork a copy into `igvc_robot/config/` once frames and topics are stable.

## 6. Optional: udev and ModemManager

If the OpenCR device flickers or disappears under Linux, ROBOTIS-style udev rules (dialout, `ENV{ID_MM_DEVICE_IGNORE}="1"`) help. Your Discord notes referenced extra scripts; this repo currently ships **`scripts/opencr_jetson_flash_burger.sh`** and **`verify_turtlebot3_base.sh`** only—add udev rules locally or contribute a small `scripts/udev/` drop-in when you settle on a rule set.

## Related docs

- [TURTLEBOT3_OPENCR_SETUP_CHAT_SUMMARY.md](./TURTLEBOT3_OPENCR_SETUP_CHAT_SUMMARY.md) — OpenCR flash, ports, motor setup context.
