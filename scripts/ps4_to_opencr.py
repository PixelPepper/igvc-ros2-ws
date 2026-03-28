#!/usr/bin/env python3
"""Bridge a Linux joystick device to the OpenCR direct motor firmware.

The OpenCR firmware expects lines like:
  V <enable> <linear_mps> <angular_radps>
  STOP
  PING

This script reads a Linux joystick from /dev/input/js* and streams velocity
commands over the OpenCR USB CDC port.

Typical DualShock 4 defaults on Linux:
  - Left stick Y axis: 1
  - Left stick X axis: 0
  - R1 deadman button: 5

Examples:
  ./scripts/ps4_to_opencr.py --list
  ./scripts/ps4_to_opencr.py --inspect /dev/input/js0
  ./scripts/ps4_to_opencr.py --port /dev/ttyACM1 --joystick /dev/input/js0
"""

from __future__ import annotations

import argparse
import array
import fcntl
import glob
import os
import select
import struct
import sys
import time
from typing import List, Sequence, Tuple

try:
    import serial
    from serial import SerialException
except ImportError:  # pragma: no cover - handled at runtime on target
    serial = None
    SerialException = Exception


JS_EVENT_BUTTON = 0x01
JS_EVENT_AXIS = 0x02
JS_EVENT_INIT = 0x80

JSIOCGAXES = 0x80016A11
JSIOCGBUTTONS = 0x80016A12


def jsiocgname(length: int) -> int:
    return 0x80006A13 + (length << 16)


def get_joystick_name(fd: int) -> str:
    buf = array.array("B", [0] * 128)
    try:
        fcntl.ioctl(fd, jsiocgname(len(buf)), buf, True)
        raw = buf.tobytes().split(b"\x00", 1)[0]
        return raw.decode(errors="replace") or "Unknown joystick"
    except OSError:
        return "Unknown joystick"


def get_joystick_counts(fd: int) -> Tuple[int, int]:
    axes = array.array("B", [0])
    buttons = array.array("B", [0])
    fcntl.ioctl(fd, JSIOCGAXES, axes, True)
    fcntl.ioctl(fd, JSIOCGBUTTONS, buttons, True)
    return int(axes[0]), int(buttons[0])


def list_joysticks() -> List[Tuple[str, str]]:
    devices: List[Tuple[str, str]] = []
    for path in sorted(glob.glob("/dev/input/js*")):
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as exc:
            devices.append((path, f"<unavailable: {exc}>"))
            continue

        try:
            devices.append((path, get_joystick_name(fd)))
        finally:
            os.close(fd)

    return devices


def auto_select_joystick() -> str:
    devices = list_joysticks()
    if not devices:
        raise RuntimeError("No joystick devices found under /dev/input/js*")
    if len(devices) > 1:
        joined = "\n".join(f"  {path}: {name}" for path, name in devices)
        raise RuntimeError(
            "Multiple joystick devices found. Pass --joystick explicitly:\n" + joined
        )
    return devices[0][0]


def normalize_axis(raw_value: int, deadzone: float) -> float:
    value = raw_value / 32767.0
    value = max(-1.0, min(1.0, value))
    if abs(value) < deadzone:
        return 0.0

    scaled = (abs(value) - deadzone) / (1.0 - deadzone)
    return scaled if value >= 0.0 else -scaled


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def drain_serial(ser) -> Sequence[str]:
    lines = []
    try:
        waiting = ser.in_waiting
        if waiting <= 0:
            return lines
        data = ser.read(waiting).decode(errors="replace")
        for line in data.splitlines():
            stripped = line.strip()
            if stripped:
                lines.append(stripped)
    except SerialException:
        return lines
    return lines


def send_line(ser, line: str) -> None:
    ser.write(line.encode("ascii"))


def open_serial(port: str, baudrate: int):
    if serial is None:
        raise RuntimeError(
            "pyserial is not installed. Run: python3 -m pip install --user pyserial"
        )

    try:
        ser = serial.Serial(port, baudrate, timeout=0.0, write_timeout=0.5)
    except SerialException as exc:
        raise RuntimeError(f"Failed to open serial port {port}: {exc}") from exc

    time.sleep(1.0)
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    return ser


def open_joystick(path: str) -> Tuple[int, str, List[int], List[int]]:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError as exc:
        raise RuntimeError(f"Failed to open joystick {path}: {exc}") from exc

    try:
        name = get_joystick_name(fd)
        axis_count, button_count = get_joystick_counts(fd)
        axes = [0] * axis_count
        buttons = [0] * button_count
    except Exception:
        os.close(fd)
        raise

    return fd, name, axes, buttons


def read_joystick_events(fd: int, axes: List[int], buttons: List[int]) -> None:
    while True:
        try:
            data = os.read(fd, 8)
        except BlockingIOError:
            return

        if len(data) != 8:
            return

        _, value, event_type, number = struct.unpack("IhBB", data)
        event_type &= ~JS_EVENT_INIT

        if event_type == JS_EVENT_AXIS and number < len(axes):
            axes[number] = value
        elif event_type == JS_EVENT_BUTTON and number < len(buttons):
            buttons[number] = value


def inspect_joystick(path: str) -> int:
    fd, name, axes, buttons = open_joystick(path)
    print(f"Inspecting {path}: {name}")
    print("Move sticks and press buttons. Press Ctrl+C to exit.")
    try:
        while True:
            readable, _, _ = select.select([fd], [], [], 1.0)
            if not readable:
                continue

            while True:
                try:
                    data = os.read(fd, 8)
                except BlockingIOError:
                    break

                if len(data) != 8:
                    break

                _, value, event_type, number = struct.unpack("IhBB", data)
                init_event = bool(event_type & JS_EVENT_INIT)
                event_type &= ~JS_EVENT_INIT
                prefix = "init " if init_event else ""

                if event_type == JS_EVENT_AXIS:
                    if number < len(axes):
                        axes[number] = value
                    norm = value / 32767.0
                    print(f"{prefix}axis {number}: raw={value:6d} norm={norm:+.3f}")
                elif event_type == JS_EVENT_BUTTON:
                    if number < len(buttons):
                        buttons[number] = value
                    print(f"{prefix}button {number}: value={value}")
    except KeyboardInterrupt:
        print("\nStopped joystick inspection.")
        return 0
    finally:
        os.close(fd)


def run_bridge(args: argparse.Namespace) -> int:
    joystick_path = args.joystick or auto_select_joystick()
    fd, joystick_name, axes, buttons = open_joystick(joystick_path)
    ser = open_serial(args.port, args.baudrate)

    if args.linear_axis >= len(axes):
        raise RuntimeError(
            f"Linear axis {args.linear_axis} is out of range for {joystick_name}"
        )
    if args.angular_axis >= len(axes):
        raise RuntimeError(
            f"Angular axis {args.angular_axis} is out of range for {joystick_name}"
        )
    if args.deadman_button >= len(buttons):
        raise RuntimeError(
            f"Deadman button {args.deadman_button} is out of range for {joystick_name}"
        )

    print(f"Joystick: {joystick_name} ({joystick_path})")
    print(f"Serial:   {args.port} @ {args.baudrate}")
    print(
        "Controls: "
        f"axis {args.linear_axis} -> linear, "
        f"axis {args.angular_axis} -> angular, "
        f"button {args.deadman_button} -> deadman"
    )
    print("Hold the deadman button to drive. Press Ctrl+C to stop.")

    try:
        send_line(ser, "PING\n")
        time.sleep(0.1)
        for line in drain_serial(ser):
            print(f"[opencr] {line}")
    except SerialException as exc:
        raise RuntimeError(f"Failed during OpenCR handshake: {exc}") from exc

    last_deadman = False
    last_status_print = 0.0
    send_period = 1.0 / args.rate_hz
    next_send = time.monotonic()

    try:
        while True:
            now = time.monotonic()
            timeout = max(0.0, next_send - now)
            readable, _, _ = select.select([fd], [], [], timeout)
            if readable:
                read_joystick_events(fd, axes, buttons)

            now = time.monotonic()
            if now < next_send:
                continue

            next_send = now + send_period

            for line in drain_serial(ser):
                if line not in {"OK V", "OK STOP"}:
                    print(f"[opencr] {line}")

            deadman_pressed = bool(buttons[args.deadman_button])
            linear_input = normalize_axis(axes[args.linear_axis], args.deadzone)
            angular_input = normalize_axis(axes[args.angular_axis], args.deadzone)

            linear_mps = clamp(
                args.linear_sign * linear_input * args.max_linear_mps,
                -args.max_linear_mps,
                args.max_linear_mps,
            )
            angular_radps = clamp(
                args.angular_sign * angular_input * args.max_angular_radps,
                -args.max_angular_radps,
                args.max_angular_radps,
            )

            if deadman_pressed:
                send_line(ser, f"V 1 {linear_mps:.3f} {angular_radps:.3f}\n")
            elif last_deadman:
                send_line(ser, "STOP\n")

            if now - last_status_print > 0.5:
                state = "ON " if deadman_pressed else "OFF"
                print(
                    f"deadman={state} linear={linear_mps:+.3f} m/s "
                    f"angular={angular_radps:+.3f} rad/s"
                )
                last_status_print = now

            last_deadman = deadman_pressed
    except KeyboardInterrupt:
        print("\nStopping robot...")
        try:
            send_line(ser, "STOP\n")
            time.sleep(0.05)
        except SerialException:
            pass
        return 0
    finally:
        try:
            ser.close()
        except Exception:
            pass
        os.close(fd)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Drive OpenCR direct motor firmware from a Linux joystick."
    )
    parser.add_argument("--port", default="/dev/ttyACM1", help="OpenCR serial port")
    parser.add_argument(
        "--baudrate", type=int, default=115200, help="OpenCR serial baudrate"
    )
    parser.add_argument(
        "--joystick",
        help="Joystick device path, e.g. /dev/input/js0. Defaults to auto-detect.",
    )
    parser.add_argument(
        "--list", action="store_true", help="List available joystick devices and exit"
    )
    parser.add_argument(
        "--inspect",
        metavar="JOYSTICK",
        help="Print raw joystick events to discover axis/button mappings",
    )
    parser.add_argument(
        "--linear-axis",
        type=int,
        default=1,
        help="Axis index for linear velocity (default: 1, left stick Y)",
    )
    parser.add_argument(
        "--angular-axis",
        type=int,
        default=0,
        help="Axis index for angular velocity (default: 0, left stick X)",
    )
    parser.add_argument(
        "--deadman-button",
        type=int,
        default=5,
        help="Button index that must be held to drive (default: 5, often R1)",
    )
    parser.add_argument(
        "--max-linear-mps",
        type=float,
        default=0.12,
        help="Maximum linear speed command in m/s",
    )
    parser.add_argument(
        "--max-angular-radps",
        type=float,
        default=1.5,
        help="Maximum angular speed command in rad/s",
    )
    parser.add_argument(
        "--rate-hz", type=float, default=30.0, help="Command send rate in Hz"
    )
    parser.add_argument(
        "--deadzone",
        type=float,
        default=0.10,
        help="Axis deadzone from 0.0 to 0.9",
    )
    parser.add_argument(
        "--linear-sign",
        type=float,
        default=-1.0,
        help="Multiply normalized linear axis by this sign (default: -1.0)",
    )
    parser.add_argument(
        "--angular-sign",
        type=float,
        default=-1.0,
        help="Multiply normalized angular axis by this sign (default: -1.0)",
    )
    return parser


def main() -> int:
    parser = build_arg_parser()
    args = parser.parse_args()

    if args.deadzone < 0.0 or args.deadzone >= 1.0:
        parser.error("--deadzone must be in the range [0.0, 1.0)")
    if args.rate_hz <= 0.0:
        parser.error("--rate-hz must be > 0")

    if args.list:
        devices = list_joysticks()
        if not devices:
            print("No joystick devices found under /dev/input/js*")
            return 1
        for path, name in devices:
            print(f"{path}: {name}")
        return 0

    if args.inspect:
        return inspect_joystick(args.inspect)

    try:
        return run_bridge(args)
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
