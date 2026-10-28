"""
Desktop GUI launcher for Zinq ZQGM-1070 mouse using the native Flutter application.
"""

import os
import sys
import subprocess
from pathlib import Path


def run_gui() -> int:
    """Launch the native Flutter Material 3 Expressive desktop application."""
    repo_root = Path(__file__).resolve().parent.parent
    bundle_bin = repo_root / "gui/build/linux/x64/release/bundle/zinq_mouse_gui"
    if bundle_bin.exists():
        os.execv(str(bundle_bin), [str(bundle_bin)])

    gui_dir = repo_root / "gui"
    if gui_dir.exists():
        return subprocess.run(["flutter", "run", "-d", "linux"], cwd=str(gui_dir)).returncode

    print(
        "Error: Flutter GUI release bundle not found. Run 'flutter build linux --release' in gui/",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(run_gui())
