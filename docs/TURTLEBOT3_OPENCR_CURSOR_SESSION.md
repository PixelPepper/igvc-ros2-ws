# TurtleBot3 OpenCR setup — Cursor session notes

Structured summary of the Cursor conversation (laptop motor setup, Arduino CLI, Jetson handoff).  
**Date:** March 2026. **Workspace:** `igvc-ros2-ws` / package `igvc_robot`.

For the shorter repo-focused reference, see [`TURTLEBOT3_OPENCR_SETUP_CHAT_SUMMARY.md`](./TURTLEBOT3_OPENCR_SETUP_CHAT_SUMMARY.md).

---

## 1. Goal

- Configure **TurtleBot3 Burger** (XL430, **OpenCR**) so it can communicate with **Dynamixel** motors and later run **ROS 2** on the **Jetson**.
- **Laptop (x86_64):** motor ID / bus setup via `turtlebot3_setup_motor` (Arduino IDE or Arduino CLI).
- **Jetson:** flash **Burger ROS 2** `.opencr` firmware and run `turtlebot3_base` / `turtlebot3_node`.

**Communication path:** Jetson → USB serial → **OpenCR** → Dynamicxel bus → **XL430** wheels. The laptop does not run ROS for this step.

---

## 2. Repo changes made in this session

| Item | Purpose |
|------|--------|
| `scripts/opencr_laptop_setup_helper.sh` | Laptop checks (`dialout`, `ttyACM*`), Arduino checklist, Jetson handoff; warns if multiple ACM devices |
| `scripts/udev/99-opencr-cdc.rules` | ROBOTIS OpenCR udev rules (vendor IDs, ModemManager) |
| `scripts/opencr_jetson_install_udev.sh` | One-time install of udev rules on Jetson |
| `scripts/opencr_arduino_cli_setup.sh` | Install/configure **arduino-cli** + OpenCR core on x86_64 |
| `scripts/opencr_find_motor_setup_sketch.sh` | Prints path to bundled `turtlebot3_setup_motor` sketch |
| `scripts/opencr_cli_motor.sh` | `compile` / `upload [port]` wrapper for that sketch |
| `.vscode/tasks.json` | Cursor/VS Code tasks: OpenCR setup, compile, upload, monitor, board list |
| `src/igvc_robot/launch/turtlebot3_base.launch.py` | Default `opencr_port` set to `/dev/ttyACM0` (was `ttyACM1`) |
| `docs/TURTLEBOT3_OPENCR_SETUP_CHAT_SUMMARY.md` | Updated with end-to-end path, udev, Arduino CLI section, script table |

---

## 3. Running scripts from the repo root

If your shell is already in `~/.../igvc-ros2-ws`, use:

```bash
./scripts/opencr_laptop_setup_helper.sh
./scripts/opencr_arduino_cli_setup.sh
```

Not `igvc-ros2-ws/scripts/...` (that path is only correct if your current directory is the **parent** of the repo).

---

## 4. Serial permissions (`dialout`)

- Devices are `root:dialout`, mode `660` → user should be in group **`dialout`**:
  ```bash
  sudo usermod -aG dialout "$USER"
  ```
- After that, **`groups`** should list `dialout`. If `/etc/group` shows `dialout:...:tech` but **`id`** / **`groups`** in a terminal omit `dialout`, the session is stale (common in IDE-integrated terminals):
  - Quit Cursor completely and reopen, or reboot; or run **`newgrp dialout`** for that shell.
- **`sg dialout -c 'id; groups'`** can confirm group membership without a full relogin.

---

## 5. Arduino IDE vs Arduino CLI

- **`arduino`** was not installed; options mentioned: `apt install arduino`, Arduino IDE 2 from arduino.cc, or **Arduino CLI** via repo scripts.
- **Arduino CLI install URL fix:** `https://arduino.github.io/arduino-cli/install.sh` returned **404**. The script was updated to use the official script per [Arduino CLI installation](https://docs.arduino.cc/arduino-cli/installation/):
  ```bash
  curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="$HOME/.local/bin" sh
  ```
  (Create `~/.local/bin` first; add it to **`PATH`**.)

---

## 6. Successful Arduino CLI + OpenCR core (reference)

After `./scripts/opencr_arduino_cli_setup.sh`:

- **arduino-cli** e.g. 1.4.1 in `~/.local/bin`
- Core **OpenCR:OpenCR@1.5.3**
- **FQBN:** `OpenCR:OpenCR:OpenCR`
- Sketch dir example:
  `~/.arduino15/packages/OpenCR/hardware/OpenCR/1.5.3/libraries/turtlebot3/examples/turtlebot3_setup/turtlebot3_setup_motor`

**Typical commands:**

```bash
export PATH="$HOME/.local/bin:$PATH"
./scripts/opencr_cli_motor.sh compile
./scripts/opencr_cli_motor.sh upload /dev/ttyACM0
arduino-cli monitor -p /dev/ttyACM0 -c baudrate=57600
```

**Multiple `ttyACM*` devices:** identify OpenCR by unplug/replug and watching which node appears; OpenCR CDC often **STMicro `idVendor=0483`**.

---

## 7. `turtlebot3_setup_motor` serial menu

Menu options:

1. setup left motor  
2. setup right motor  
3. test left motor  
4. test right motor  

**Rule:** only **one** XL430 on the bus while running **1** or **2**.

### 7.1 Error: `[TxRxResult] There is no status packet!`

- OpenCR got **no Dynamixel reply** after trying baud **57600** and **1000000**.
- **Cause:** almost always **no motor bus power**, wrong **OpenCR Dynamixel port**, or bad/loose cable — not the serial monitor baud.
- **Fix:** connect **robot power** (e.g. charged **LiPo** per TurtleBot3 wiring to the **correct battery input / switch**, not “USB only”), **main power on**, correct **left/right** port for the motor being configured, then retry **1** or **2**.

### 7.2 Successful left setup (example)

```
Find Motor...
    ... SUCCESS
    [ID: 1 found at baud: 1000000]
Setup Motor Left...
    ok
```

Then optionally **3** to test left; **power off**, swap to **right motor only**, run **2** (and **4** to test). When both sides are done: **power off**, reconnect **both** motors.

---

## 8. After motor setup — flash Burger on Jetson

1. **Reconnect both** wheel motors to normal left/right wiring.
2. Move **OpenCR USB** from laptop → **Jetson**.
3. On Jetson (once):
   ```bash
   <repo>/scripts/opencr_jetson_install_udev.sh
   ```
4. Flash:
   ```bash
   OPENCR_PORT=/dev/ttyACM0 <repo>/scripts/opencr_jetson_flash_burger.sh
   ```
   Adjust `OPENCR_PORT` after `ls -l /dev/ttyACM*`.
5. Verify:
   ```bash
   <repo>/scripts/verify_turtlebot3_base.sh
   ```
   or:
   ```bash
   source <repo>/install/setup.bash
   ros2 launch igvc_robot turtlebot3_base.launch.py opencr_port:=/dev/ttyACM0
   ```

**Recovery if upload fails:** hold **SW2**, press **RESET**, release **RESET**, release **SW2**, retry flash.

**Hardware check:** long-press **SW1** / **SW2** — wheels should jog.

---

## 9. Cursor integration

- **Tasks:** `Terminal → Run Task…` → **OpenCR:** setup, compile, upload, monitor (see `.vscode/tasks.json`).
- **Serial monitor** default baud in task: **57600** (match sketch; try **115200** if garbled).

---

## 10. Session outcome (user state at end of chat)

- Left and right motors configured via menu options **2** and **4** (and prior **1** for left); user ready for **Jetson Burger flash** per section 8.

---

*Generated from project Cursor chat; keep in version control if useful for the team.*
