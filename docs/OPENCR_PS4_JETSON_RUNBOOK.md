# OpenCR PS4 control from Jetson

This document is the exact runbook for using the TurtleBot3 Burger wheel motors
from a PS4 controller on the Jetson, with no ROS in the loop.

It assumes the OpenCR has already been flashed **from the x86_64 laptop** with
the custom firmware in:

- `firmware/opencr_direct_ps4/opencr_direct_ps4.ino`

That firmware was verified on the laptop after re-running the official
`turtlebot3_setup_motor` flow:

- left motor configured successfully as ID `1` at `1000000`
- right motor configured successfully as ID `2` at `1000000`
- both motors reconnected in normal wiring
- custom PS4 firmware re-flashed and tested
- PS4 control verified on the laptop with `scripts/ps4_to_opencr.py`

## Important constraints

- Do **not** try to build or flash the OpenCR firmware from the Jetson.
- The Jetson is only the runtime host for the PS4 controller and USB serial link.
- If the OpenCR firmware ever gets overwritten, return to the laptop and reflash
  the custom firmware there.
- Do **not** run ROS, `turtlebot3_node`, Arduino serial monitor, or any other
  process that opens the same `/dev/ttyACM*` device while using the PS4 bridge.

## Runtime architecture

The runtime path is:

`PS4 controller -> Jetson -> scripts/ps4_to_opencr.py -> USB serial -> OpenCR -> motors`

The OpenCR firmware accepts these host commands over USB CDC serial at
`115200` baud:

- `V <enable> <linear_mps> <angular_radps>`
- `STOP`
- `PING`

## Required files in this repo

- `scripts/ps4_to_opencr.py`
- `firmware/opencr_direct_ps4/opencr_direct_ps4.ino`

The Jetson only needs the Python script at runtime, but the firmware path is
listed here so it is clear which sketch must already be on the OpenCR.

## One-time Jetson setup

Run these on the Jetson after pulling this repo:

```bash
cd ~/igvc-ros2-ws
python3 -m pip install --user pyserial
sudo usermod -aG dialout "$USER"
newgrp dialout
```

Notes:

- If `newgrp dialout` is inconvenient, log out of the Jetson session and log
  back in, then open a new terminal.
- Verify the group took effect with `groups`.

## Hardware setup on the Jetson

Before running the script:

1. Plug the OpenCR USB cable into the Jetson.
2. Make sure both wheel motors are connected in normal operating wiring.
3. Make sure robot main power is on.
4. Pair or connect the PS4 controller to the Jetson.
5. Confirm no other app is using the OpenCR serial device.

## Identify devices

Check the OpenCR serial device:

```bash
ls -l /dev/ttyACM*
```

Check the controller joystick device:

```bash
ls -l /dev/input/js*
```

List detected controllers via the runtime script:

```bash
cd ~/igvc-ros2-ws
python3 ./scripts/ps4_to_opencr.py --list
```

Typical expected devices:

- OpenCR: `/dev/ttyACM0`
- PS4 controller: `/dev/input/js0`

These can change after reboot or reconnect, so always verify before running.

## Default tested mapping

The tested default mapping in `scripts/ps4_to_opencr.py` is:

- joystick axis `1` -> linear velocity
- joystick axis `0` -> angular velocity
- button `5` -> deadman

The script prints the active mapping on startup.

Typical startup output:

```text
Joystick: Wireless Controller (/dev/input/js0)
Serial:   /dev/ttyACM0 @ 115200
Controls: axis 1 -> linear, axis 0 -> angular, button 5 -> deadman
Hold the deadman button to drive. Press Ctrl+C to stop.
```

## Normal run command

Run this on the Jetson:

```bash
cd ~/igvc-ros2-ws
python3 ./scripts/ps4_to_opencr.py --port /dev/ttyACM0 --joystick /dev/input/js0
```

Adjust the paths if your devices enumerate differently.

## Discover controller mapping if needed

If the controller mapping is different on the Jetson, inspect raw events:

```bash
cd ~/igvc-ros2-ws
python3 ./scripts/ps4_to_opencr.py --inspect /dev/input/js0
```

Move sticks and press buttons, then note the indices you want to use.

Example with custom mapping:

```bash
python3 ./scripts/ps4_to_opencr.py \
  --port /dev/ttyACM0 \
  --joystick /dev/input/js0 \
  --linear-axis 1 \
  --angular-axis 0 \
  --deadman-button 5
```

## Runtime behavior

- The script sends commands at `30 Hz`.
- The default speed limits are:
  - linear: `0.12 m/s`
  - angular: `1.5 rad/s`
- The deadman button must be held to drive.
- Releasing the deadman sends `STOP`.
- Pressing `Ctrl+C` also sends `STOP` before exit.
- The firmware times out after `250 ms` without valid commands and zeros the
  wheel velocities automatically.

## Safety

- Start with the robot lifted or wheels off the ground after any reconnect.
- Keep the deadman released until you are ready to test.
- Use conservative speed limits until behavior is verified on the Jetson.
- Confirm the robot stops when the deadman is released.

## What not to do on the Jetson

Do not use these for this direct-PS4 workflow:

- `scripts/opencr_jetson_flash_burger.sh`
- `scripts/opencr_jetson_flash_ps4.sh`
- `ros2 launch ...`
- `turtlebot3_node`
- `arduino-cli compile`
- `arduino-cli upload`

Those are outside the intended simple runtime path for this configuration.

## If it stops working

### `Permission denied` on `/dev/ttyACM*`

The shell session likely does not have `dialout` yet.

Run:

```bash
sudo usermod -aG dialout "$USER"
newgrp dialout
groups
```

### No `/dev/input/js0`

The controller is not connected as a Linux joystick device.

Check:

```bash
ls /dev/input/js*
python3 ./scripts/ps4_to_opencr.py --list
```

### Script starts but robot does not move

Check:

- OpenCR is on the correct `/dev/ttyACM*`
- robot main power is on
- both motors are connected
- deadman button is actually being pressed
- no other process is holding the serial port

### OpenCR does not respond on the Jetson

If `PING` or motion commands fail and you suspect the firmware changed, reflash
the custom OpenCR firmware **from the laptop**, not from the Jetson.

## Current known-good state

This repo and robot were verified on the laptop with:

- OpenCR on `/dev/ttyACM0`
- PS4 controller on `/dev/input/js0`
- `scripts/ps4_to_opencr.py`
- custom OpenCR direct PS4 firmware already flashed

That is the exact state the Jetson should use at runtime.
