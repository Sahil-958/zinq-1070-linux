"""
Command-line interface for managing Zinq ZQGM-1070 mouse on Linux.
"""

import sys
import json
import argparse
from typing import List, Optional

from .device import ZinqMouse
from .protocol import LED_MODES, DPI_MAP, BUTTON_ACTIONS, BUTTON_NAMES


def format_status(mouse: ZinqMouse) -> str:
    """Format human-readable device status output."""
    connected = mouse.is_connected()
    dev_path = mouse.dev_path or "Not found"

    lines = [
        "╔═══════════════════════════════════════════════════════╗",
        "║       Zinq ZQGM-1070 Gaming Mouse Status              ║",
        "╚═══════════════════════════════════════════════════════╝",
        f"  Device node    : {dev_path}",
        f"  Connected      : {'Yes (Ready)' if connected else 'No (Disconnected or No Access)'}",
        f"  Active Stage   : Level {mouse.state.get('current_stage', 0) + 1}",
        f"  Active DPI     : {mouse.state['stages'][mouse.state.get('current_stage', 0)]} DPI",
        f"  LED Lighting   : {mouse.state.get('led_mode', 'slow').upper()}",
        f"  Fire Interval  : {mouse.state.get('fire_time_ms', 50)} ms",
        "",
        "  DPI Stages:",
    ]

    cur_stage = mouse.state.get("current_stage", 0)
    for idx, dpi in enumerate(mouse.state.get("stages", [])):
        marker = "▶" if idx == cur_stage else " "
        lines.append(f"   {marker} Stage {idx + 1}: {dpi} DPI")

    lines.append("")
    lines.append("  Button Mappings:")
    for b_id in range(1, 7):
        b_name = BUTTON_NAMES.get(b_id, f"Button {b_id}")
        action = mouse.state.get("buttons", {}).get(str(b_id), "default")
        lines.append(f"    Button {b_id} ({b_name:<16}): {action}")

    return "\n".join(lines)


def main(args: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="zinq-mouse",
        description="Manage Zinq ZQGM-1070 Gaming Mouse settings (DPI, LED modes, Button mappings) on Linux.",
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # Status
    status_parser = subparsers.add_parser("status", help="Show mouse connection status and configuration")
    status_parser.add_argument("--json", action="store_true", help="Output status as structured JSON")

    # LED
    led_parser = subparsers.add_parser("led", help="Set mouse breathing LED lighting effect")
    led_parser.add_argument(
        "mode",
        choices=list(LED_MODES.keys()),
        help="LED effect: slow (breathing slow), fast (breathing fast), static (solid on), off (disabled)",
    )

    # DPI
    dpi_parser = subparsers.add_parser("dpi", help="Set mouse DPI resolution")
    dpi_parser.add_argument(
        "value",
        type=int,
        choices=list(DPI_MAP.keys()),
        help=f"DPI value: {list(DPI_MAP.keys())}",
    )
    dpi_parser.add_argument(
        "--stage",
        type=int,
        choices=[1, 2, 3, 4],
        default=None,
        help="Specific DPI stage (1-4) to configure (defaults to active stage)",
    )

    # Stage switch
    stage_parser = subparsers.add_parser("stage", help="Switch active DPI stage profile (1-4)")
    stage_parser.add_argument("level", type=int, choices=[1, 2, 3, 4], help="DPI stage level (1 to 4)")

    # Button
    btn_parser = subparsers.add_parser("button", help="Map mouse button to hardware function")
    btn_parser.add_argument("id", type=int, choices=[1, 2, 3, 4, 5, 6], help="Button number (1 to 6)")
    btn_parser.add_argument("action", choices=list(BUTTON_ACTIONS.keys()), help="Function to assign")

    # Fire speed
    fire_parser = subparsers.add_parser("fire", help="Set rapid fire interval (ms)")
    fire_parser.add_argument("ms", type=int, help="Interval in milliseconds (e.g. 50)")

    # Reset
    subparsers.add_parser("reset", help="Reset mouse to factory default settings")

    # Monitor
    subparsers.add_parser("monitor", help="Live interrupt stream sniffer for all mouse HID input reports")

    # GUI
    subparsers.add_parser("gui", help="Launch Graphical User Interface (GUI)")

    parsed = parser.parse_args(args)

    if not parsed.command:
        # Default to status if no arguments
        mouse = ZinqMouse()
        print(format_status(mouse))
        print("\nRun 'zinq-mouse --help' or 'zinq-mouse gui' for more options.")
        return 0

    if parsed.command == "gui":
        from .gui import run_gui
        return run_gui()

    if parsed.command == "monitor":
        ZinqMouse.monitor_interrupts()
        return 0

    mouse = ZinqMouse()

    if parsed.command == "status":
        mouse.read_live_status()
        if getattr(parsed, "json", False):
            payload = {
                "connected": mouse.is_connected(),
                "device_path": mouse.dev_path,
                "current_stage": mouse.state.get("current_stage", 0),
                "stages": mouse.state.get("stages", []),
                "led_mode": mouse.state.get("led_mode", "slow"),
                "fire_time_ms": mouse.state.get("fire_time_ms", 50),
                "buttons": mouse.state.get("buttons", {}),
            }
            print(json.dumps(payload, indent=2))
        else:
            print(format_status(mouse))
        return 0

    if not mouse.is_connected():
        print("Error: Zinq ZQGM-1070 mouse not detected or device node not accessible.", file=sys.stderr)
        print("Please plug in the mouse and verify udev rule / permissions.", file=sys.stderr)
        return 1

    try:
        if parsed.command == "led":
            mouse.set_led(parsed.mode)
            print(f"LED lighting mode set to: {parsed.mode.upper()}")

        elif parsed.command == "dpi":
            stage_idx = (parsed.stage - 1) if parsed.stage else None
            mouse.set_dpi(parsed.value, stage=stage_idx)
            stage_num = (stage_idx + 1) if stage_idx is not None else (mouse.state.get("current_stage", 0) + 1)
            print(f"Stage {stage_num} DPI set to: {parsed.value} DPI")

        elif parsed.command == "stage":
            mouse.set_stage(parsed.level - 1)
            active_dpi = mouse.state["stages"][parsed.level - 1]
            print(f"Switched to Stage {parsed.level} ({active_dpi} DPI)")

        elif parsed.command == "button":
            mouse.set_button(parsed.id, parsed.action)
            btn_name = BUTTON_NAMES.get(parsed.id, f"Button {parsed.id}")
            print(f"{btn_name} (Button {parsed.id}) mapped to: {parsed.action}")

        elif parsed.command == "fire":
            mouse.set_fire_speed(parsed.ms)
            print(f"Fire interval timing set to: {parsed.ms} ms")

        elif parsed.command == "reset":
            mouse.reset()
            print("Zinq ZQGM-1070 mouse reset to factory defaults.")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
