"""
Hardware communication interface for Zinq ZQGM-1070 mouse using Linux hidraw.
"""

import os
import glob
import fcntl
import json
from pathlib import Path
from typing import Optional, Dict, Any

from .protocol import (
    REPORT_LENGTH,
    DPI_MAP,
    CODE_TO_DPI,
    LED_MODES,
    LED_MODE_NAMES,
    BUTTON_ACTIONS,
    DEFAULT_STAGES,
    build_dpi_led_packet,
    build_dpi_mask_packet,
    build_button_packet,
    build_fire_speed_packet,
    build_reset_packet,
)


def _hidiocsfeature(length: int) -> int:
    """Calculate Linux HIDIOCSFEATURE ioctl number."""
    # _IOC(_IOC_WRITE|_IOC_READ, 'H', 0x06, len) = 0xc0000000 | (len << 16) | (ord('H') << 8) | 0x06
    return 0xC0000000 | (length << 16) | (ord("H") << 8) | 0x06


def _hidiocgfeature(length: int) -> int:
    """Calculate Linux HIDIOCGFEATURE ioctl number."""
    # _IOC(_IOC_WRITE|_IOC_READ, 'H', 0x07, len) = 0xc0000000 | (len << 16) | (ord('H') << 8) | 0x07
    return 0xC0000000 | (length << 16) | (ord("H") << 8) | 0x07


class ZinqMouse:
    """Control interface for Zinq ZQGM-1070 Gaming Mouse."""

    VID = "18f8"
    PID = "0f99"
    CONFIG_PATH = Path.home() / ".config" / "zinq-mouse" / "config.json"

    def __init__(self, dev_path: Optional[str] = None):
        self._dev_path = dev_path or self.find_device()
        self.state: Dict[str, Any] = {
            "current_stage": 0,
            "stages": list(DEFAULT_STAGES),
            "led_mode": "slow",
            "fire_time_ms": 50,
            "buttons": {
                "1": "left",
                "2": "middle",
                "3": "right",
                "4": "back",
                "5": "forward",
                "6": "dpiloop",
            },
        }
        self.load_config()

    @classmethod
    def find_device(cls) -> Optional[str]:
        """Dynamically discover the control hidraw node for the Zinq mouse."""
        for hidraw in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
            dev_name = os.path.basename(hidraw)
            dev_node = f"/dev/{dev_name}"

            # 1. Verify USB Vendor & Product ID
            uevent_file = os.path.join(hidraw, "device", "uevent")
            if os.path.exists(uevent_file):
                try:
                    with open(uevent_file, "r") as uf:
                        uevent_text = uf.read()
                    if "18F8" not in uevent_text or "0F99" not in uevent_text:
                        continue
                except Exception:
                    continue

            # 2. Verify Control Interface (Usage Page 0xFF01, Report ID 0x07)
            desc_file = os.path.join(hidraw, "device", "report_descriptor")
            if not os.path.exists(desc_file):
                continue

            try:
                with open(desc_file, "rb") as f:
                    desc = f.read()

                if b"\x06\x01\xff" in desc and b"\x85\x07" in desc:
                    return dev_node
            except Exception:
                continue

        return None

    @classmethod
    def find_all_devices(cls) -> list:
        """Find all hidraw nodes associated with the Zinq mouse."""
        nodes = []
        for hidraw in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
            dev_node = f"/dev/{os.path.basename(hidraw)}"
            uevent_file = os.path.join(hidraw, "device", "uevent")
            if os.path.exists(uevent_file):
                try:
                    with open(uevent_file, "r") as uf:
                        uevent_text = uf.read()
                    if "18F8" in uevent_text and "0F99" in uevent_text:
                        nodes.append(dev_node)
                except Exception:
                    continue
        return nodes

    @classmethod
    def monitor_interrupts(cls, callback=None) -> None:
        """
        Listen to live interrupt input reports on all mouse interfaces.
        """
        import select
        import time

        nodes = cls.find_all_devices()
        if not nodes:
            print("No Zinq ZQGM-1070 device nodes found to monitor.")
            return

        fds = {}
        for node in nodes:
            try:
                fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
                fds[fd] = node
            except Exception as e:
                print(f"Cannot open {node}: {e}")

        print(f"Monitoring live HID interrupt stream on: {list(fds.values())}")
        print("Move mouse, click buttons, or press DPI switch to view incoming reports...")
        print("Press Ctrl+C to exit.\n")

        try:
            while True:
                r, _, _ = select.select(list(fds.keys()), [], [], 0.2)
                for fd in r:
                    try:
                        data = os.read(fd, 64)
                        if data:
                            dev = fds[fd]
                            ts = time.strftime("%H:%M:%S")
                            report_id = data[0]
                            desc = f"Report ID 0x{report_id:02x}"
                            if dev.endswith("1") and report_id == 0x01 and len(data) >= 6:
                                btns = data[1]
                                dx = int.from_bytes(data[2:4], "little", signed=True)
                                dy = int.from_bytes(data[4:6], "little", signed=True)
                                desc = f"Mouse (Buttons=0b{btns:05b}, dX={dx}, dY={dy})"
                            elif report_id == 0x02:
                                desc = f"Consumer Control (Code: {data[1:].hex()})"
                            elif report_id == 0x03:
                                desc = f"Keyboard Key (Code: {data[1:].hex()})"
                            elif report_id == 0x06:
                                desc = f"Vendor Notification (Data: {data[1:].hex()})"

                            msg = f"[{ts}] [{dev}] {desc} | Raw: {data.hex()}"
                            if callback:
                                callback(msg)
                            else:
                                print(msg)
                    except Exception:
                        pass
        except KeyboardInterrupt:
            pass
        finally:
            for fd in fds:
                os.close(fd)

    @property
    def dev_path(self) -> Optional[str]:
        if not self._dev_path or not os.path.exists(self._dev_path):
            self._dev_path = self.find_device()
        return self._dev_path

    def is_connected(self) -> bool:
        """Check if mouse is plugged in and accessible."""
        p = self.dev_path
        if not p or not os.path.exists(p):
            return False
        return os.access(p, os.R_OK | os.W_OK)

    def _send_packet(self, data: bytes) -> None:
        """Send 8-byte HID Feature Report to mouse."""
        p = self.dev_path
        if not p:
            raise FileNotFoundError("Zinq ZQGM-1070 mouse not detected.")
        if not os.access(p, os.W_OK):
            raise PermissionError(
                f"Cannot write to {p}. Ensure udev rule is installed or add user to correct group."
            )

        ioctl_num = _hidiocsfeature(len(data))
        with open(p, "r+b") as fd:
            fcntl.ioctl(fd.fileno(), ioctl_num, data)

    def read_live_status(self) -> Optional[Dict[str, Any]]:
        """
        Query live hardware state directly from mouse MCU via HIDIOCGFEATURE.
        Returns live active stage, live DPI, and live LED mode.
        """
        p = self.dev_path
        if not p or not os.access(p, os.R_OK | os.W_OK):
            return None

        try:
            ioctl_num = _hidiocgfeature(8)
            buf = bytearray([0x07] + [0] * 7)
            with open(p, "r+b") as fd:
                fcntl.ioctl(fd.fileno(), ioctl_num, buf, True)

            if buf[0] == 0x07 and buf[1] == 0x09:
                stage = buf[2]
                mode_raw = buf[3]
                dpi_code = (mode_raw >> 4) - 8
                led_code = mode_raw & 0x0F
                led_mode = LED_MODE_NAMES.get(led_code, self.state.get("led_mode", "slow"))
                dpi = CODE_TO_DPI.get(dpi_code)

                if 0 <= stage <= 3:
                    changed = (
                        self.state.get("current_stage") != stage
                        or self.state.get("led_mode") != led_mode
                    )
                    self.state["current_stage"] = stage
                    if dpi and dpi in DPI_MAP:
                        if self.state["stages"][stage] != dpi:
                            self.state["stages"][stage] = dpi
                            changed = True
                    self.state["led_mode"] = led_mode
                    if changed:
                        self.save_config()

                return {
                    "current_stage": self.state["current_stage"],
                    "led_mode": self.state["led_mode"],
                    "dpi": dpi,
                }
        except Exception:
            pass
        return None

    def set_dpi_and_led(self, stage: int, dpi: int, led_mode: str) -> None:
        """
        Configure mouse DPI for a specific stage and set the LED mode.
        """
        if led_mode not in LED_MODES:
            raise ValueError(f"Unknown LED mode '{led_mode}'. Choose: {list(LED_MODES.keys())}")
        if dpi not in DPI_MAP:
            raise ValueError(f"Unsupported DPI '{dpi}'. Choose: {list(DPI_MAP.keys())}")
        if not (0 <= stage <= 3):
            raise ValueError("Stage must be 0, 1, 2, or 3.")

        mode_code = LED_MODES[led_mode]
        pkt = build_dpi_led_packet(stage, dpi, mode_code)
        self._send_packet(pkt)

        # Update cached state
        self.state["current_stage"] = stage
        self.state["stages"][stage] = dpi
        self.state["led_mode"] = led_mode
        self.save_config()

    def set_led(self, mode: str) -> None:
        """Set LED lighting effect mode (slow, fast, static, off)."""
        stage = self.state.get("current_stage", 0)
        dpi = self.state.get("stages", DEFAULT_STAGES)[stage]
        self.set_dpi_and_led(stage, dpi, mode)

    def set_dpi(self, dpi: int, stage: Optional[int] = None) -> None:
        """Set DPI value for the current or specified stage."""
        if stage is None:
            stage = self.state.get("current_stage", 0)
        mode = self.state.get("led_mode", "slow")
        self.set_dpi_and_led(stage, dpi, mode)

    def set_stage(self, stage: int) -> None:
        """Switch active DPI stage (0, 1, 2, or 3)."""
        if not (0 <= stage <= 3):
            raise ValueError("Stage must be 0, 1, 2, or 3.")
        dpi = self.state.get("stages", DEFAULT_STAGES)[stage]
        mode = self.state.get("led_mode", "slow")
        self.set_dpi_and_led(stage, dpi, mode)

    def set_button(self, button_id: int, action: str) -> None:
        """Map a mouse button (1..6) to a hardware function."""
        if action not in BUTTON_ACTIONS:
            raise ValueError(f"Unknown action '{action}'. Choose: {list(BUTTON_ACTIONS.keys())}")
        action_code = BUTTON_ACTIONS[action]
        pkt = build_button_packet(button_id, action_code)
        self._send_packet(pkt)

        self.state["buttons"][str(button_id)] = action
        self.save_config()

    def set_fire_speed(self, ms: int = 50) -> None:
        """Set rapid fire click interval timing in milliseconds."""
        pkt = build_fire_speed_packet(ms)
        self._send_packet(pkt)
        self.state["fire_time_ms"] = ms
        self.save_config()

    def reset(self) -> None:
        """Reset mouse to factory defaults."""
        pkt = build_reset_packet()
        self._send_packet(pkt)
        self.state = {
            "current_stage": 0,
            "stages": list(DEFAULT_STAGES),
            "led_mode": "slow",
            "fire_time_ms": 50,
            "buttons": {
                "1": "left",
                "2": "middle",
                "3": "right",
                "4": "back",
                "5": "forward",
                "6": "dpiloop",
            },
        }
        self.save_config()

    def apply_all(self) -> None:
        """Apply full stored state to hardware."""
        # 1. Button mappings
        for btn_str, action in self.state.get("buttons", {}).items():
            try:
                self.set_button(int(btn_str), action)
            except Exception:
                pass
        # 2. Fire speed
        self.set_fire_speed(self.state.get("fire_time_ms", 50))
        # 3. Active DPI & LED
        stage = self.state.get("current_stage", 0)
        dpi = self.state.get("stages", DEFAULT_STAGES)[stage]
        mode = self.state.get("led_mode", "slow")
        self.set_dpi_and_led(stage, dpi, mode)

    def load_config(self) -> None:
        """Load persistent settings from disk."""
        if self.CONFIG_PATH.exists():
            try:
                with open(self.CONFIG_PATH, "r", encoding="utf-8") as f:
                    saved = json.load(f)
                    self.state.update(saved)
            except Exception:
                pass

    def save_config(self) -> None:
        """Save settings persistently to disk."""
        try:
            self.CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
            with open(self.CONFIG_PATH, "w", encoding="utf-8") as f:
                json.dump(self.state, f, indent=2)
        except Exception:
            pass
