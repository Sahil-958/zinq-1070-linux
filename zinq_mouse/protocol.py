"""
Protocol definitions for Zinq Technologies ZQGM-1070 Gaming Mouse.
(Instant Technology / Maxxter USB VID: 0x18f8, PID: 0x0f99)
"""

# HID Report Constants
REPORT_ID = 0x07
REPORT_LENGTH = 8

# Subcommand IDs
CMD_DPI_LED = 0x09
CMD_BUTTON = 0x10
CMD_DPI_MASK = 0x11
CMD_FIRE_SPEED = 0x12
CMD_RESET = 0x20

# DPI Presets and their hardware codes
DPI_MAP = {
    1200: 1,
    1600: 2,
    2000: 3,
    2400: 4,
    3200: 0,
}

CODE_TO_DPI = {v: k for k, v in DPI_MAP.items()}

# Default DPI stages matching factory config
DEFAULT_STAGES = [1200, 1600, 2400, 3200]

# LED Lighting Modes
LED_MODES = {
    "slow": 0,    # Breathing Slow
    "fast": 1,    # Breathing Fast
    "static": 2,  # Solid Constant On
    "off": 3,     # LED Off
}

LED_MODE_NAMES = {v: k for k, v in LED_MODES.items()}

# Mouse Buttons (1 to 6)
BUTTON_NAMES = {
    1: "Left Button",
    2: "Middle Button",
    3: "Right Button",
    4: "Forward (Side 1)",
    5: "Back (Side 2)",
    6: "DPI Switch",
}

# Button Actions matching authentic Instant Technology MCU hardware codes
BUTTON_ACTIONS = {
    "left": 1,
    "middle": 2,
    "right": 3,
    "forward": 4,
    "back": 5,
    "dpiloop": 6,       # Native Hardware DPI Loop (0x06)
    "desktop": 11,      # Show Desktop
    "disabled": 12,     # Key disabled / off
    "fire": 13,         # Rapid Fire
    "browser": 14,      # Web Browser
    "player": 15,       # Media Player
    "mail": 16,         # Email
    "dpi+": 17,         # DPI Increment
    "dpi-": 18,         # DPI Decrement
    "ledswitch": 19,    # LED Light Switch
    "volup": 21,        # Volume Up
    "voldown": 22,      # Volume Down
    "playpause": 23,    # Play / Pause
    "next": 24,         # Next Track
    "prev": 25,         # Previous Track
    "mute": 26,         # Audio Mute
}

ACTION_TO_NAME = {v: k for k, v in BUTTON_ACTIONS.items()}


def build_dpi_led_packet(stage: int, dpi: int, led_mode: int) -> bytes:
    """
    Build 8-byte HID Feature Report 0x07 for DPI and LED mode.
    stage: 0..3 (Level 1..4)
    dpi: 1200, 1600, 2000, 2400, or 3200
    led_mode: 0 (slow), 1 (fast), 2 (static), 3 (off)
    """
    if dpi not in DPI_MAP:
        raise ValueError(f"Unsupported DPI: {dpi}. Valid choices: {list(DPI_MAP.keys())}")
    if led_mode not in LED_MODE_NAMES:
        raise ValueError(f"Unsupported LED mode: {led_mode}. Valid choices: {list(LED_MODE_NAMES.keys())}")
    if not (0 <= stage <= 3):
        raise ValueError(f"Stage index must be 0..3 (got {stage})")

    dpi_code = DPI_MAP[dpi]
    byte3 = ((dpi_code + 8) << 4) | (led_mode & 0x0F)
    return bytes([REPORT_ID, CMD_DPI_LED, stage, byte3, 0x00, 0x00, 0x00, 0x00])


def build_dpi_mask_packet(mask: int = 0) -> bytes:
    """Build 8-byte HID Feature Report for DPI stage mask/enable flags."""
    return bytes([REPORT_ID, CMD_DPI_MASK, mask & 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00])


def build_button_packet(button_id: int, action_code: int) -> bytes:
    """
    Build 8-byte HID Feature Report for button mapping.
    button_id: 1..6
    action_code: hardware action ID
    """
    if not (1 <= button_id <= 6):
        raise ValueError(f"Button ID must be 1..6 (got {button_id})")
    return bytes([REPORT_ID, CMD_BUTTON, button_id, action_code & 0xFF, 0x00, 0x00, 0x00, 0x00])


def build_fire_speed_packet(fire_time_ms: int = 50) -> bytes:
    """
    Build 8-byte HID Feature Report for fire interval timing.
    fire_time_ms: 10..500 ms (default 50 ms)
    """
    code = (fire_time_ms >> 3) & 0xFF
    return bytes([REPORT_ID, CMD_FIRE_SPEED, code, 0x00, 0x00, 0x00, 0x00, 0x00])


def build_reset_packet() -> bytes:
    """Build 8-byte HID Feature Report for factory hardware reset."""
    return bytes([REPORT_ID, CMD_RESET, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
