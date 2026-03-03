"""HumWatch — Pre-flight verification.

Run standalone:  python -m agent.verify
Called by setup.bat after install to catch problems early.
Exit code 0 = all good, 1 = warnings (psutil-only), 2 = fatal.
"""

import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# ANSI colors (supported on Windows 10+)
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
CYAN = "\033[96m"
RESET = "\033[0m"
BOLD = "\033[1m"

_warnings = 0
_errors = 0


def ok(msg: str) -> None:
    print(f"  {GREEN}[OK]{RESET}  {msg}")


def warn(msg: str, fix: str = "") -> None:
    global _warnings
    _warnings += 1
    print(f"  {YELLOW}[!!]{RESET}  {msg}")
    if fix:
        print(f"         {CYAN}Fix: {fix}{RESET}")


def fail(msg: str, fix: str = "") -> None:
    global _errors
    _errors += 1
    print(f"  {RED}[FAIL]{RESET} {msg}")
    if fix:
        print(f"         {CYAN}Fix: {fix}{RESET}")


def check_python() -> None:
    """Verify Python version and venv."""
    v = sys.version_info
    print(f"\n{BOLD}Python{RESET}")
    if v >= (3, 10):
        ok(f"Python {v.major}.{v.minor}.{v.micro}")
    elif v >= (3, 8):
        warn(f"Python {v.major}.{v.minor}.{v.micro} — 3.10+ recommended")
    else:
        fail(f"Python {v.major}.{v.minor}.{v.micro} — need 3.8+",
             "Install Python 3.10+ from https://python.org")

    in_venv = sys.prefix != sys.base_prefix
    if in_venv:
        ok(f"Running inside venv ({sys.prefix})")
    else:
        warn("Not running inside a venv — packages may conflict",
             "Run setup.bat to create the venv")


def check_packages() -> None:
    """Verify required Python packages."""
    print(f"\n{BOLD}Python packages{RESET}")
    required = {
        "fastapi": "fastapi",
        "uvicorn": "uvicorn",
        "psutil": "psutil",
        "aiosqlite": "aiosqlite",
        "pydantic": "pydantic",
        "httpx": "httpx",
    }
    for display, module in required.items():
        try:
            __import__(module)
            ok(display)
        except ImportError:
            fail(f"{display} not installed", f"pip install {display}")

    # pythonnet is special — it's required for LHM but not fatal
    try:
        import clr  # noqa: F401
        ok("pythonnet (clr)")
    except ImportError:
        warn("pythonnet not installed — LHM sensors won't work (no temps, GPU, fans)",
             "pip install pythonnet")
    except Exception as e:
        warn(f"pythonnet import error: {e}")


def check_lhm_dll() -> None:
    """Verify LibreHardwareMonitor DLLs exist."""
    print(f"\n{BOLD}LibreHardwareMonitor{RESET}")
    dll = PROJECT_ROOT / "lib" / "LibreHardwareMonitorLib.dll"
    if dll.exists():
        size_kb = dll.stat().st_size / 1024
        if size_kb > 100:
            ok(f"LibreHardwareMonitorLib.dll ({size_kb:.0f} KB)")
        else:
            warn(f"LibreHardwareMonitorLib.dll exists but only {size_kb:.0f} KB — may be corrupt",
                 "Delete lib/ folder and re-run setup.bat")
    else:
        warn("LibreHardwareMonitorLib.dll not found — no hardware sensors",
             "Re-run setup.bat to download LHM DLLs")

    hidsharp = PROJECT_ROOT / "lib" / "HidSharp.dll"
    if hidsharp.exists():
        ok("HidSharp.dll")
    else:
        warn("HidSharp.dll not found — some sensors may not work")


def check_lhm_load() -> None:
    """Try to actually load LHM through pythonnet — the real test."""
    print(f"\n{BOLD}LHM load test{RESET}")
    try:
        import clr
    except ImportError:
        warn("Skipped — pythonnet not available")
        return
    except Exception as e:
        warn(f"Skipped — pythonnet runtime unavailable: {e}")
        return

    dll = PROJECT_ROOT / "lib" / "LibreHardwareMonitorLib"
    try:
        clr.AddReference(str(dll))
        from LibreHardwareMonitor.Hardware import Computer
        ok("LHM library loads successfully")
    except Exception as e:
        warn(f"LHM library failed to load: {e}",
             "Check that .NET Framework 4.7.2+ is installed")
        return

    # Try to open (requires admin for full access)
    try:
        computer = Computer()
        computer.IsCpuEnabled = True
        computer.IsGpuEnabled = True
        computer.Open()

        hw_names = []
        for hw in computer.Hardware:
            hw_names.append(f"{hw.Name} ({hw.HardwareType})")

        computer.Close()

        if hw_names:
            ok(f"LHM detected {len(hw_names)} hardware item(s):")
            for name in hw_names:
                print(f"         - {name}")
        else:
            warn("LHM opened but found no hardware — may need admin privileges",
                 "Run as Administrator for full sensor access")
    except Exception as e:
        err_str = str(e)
        if "access" in err_str.lower() or "denied" in err_str.lower():
            warn("LHM needs admin privileges for hardware access",
                 "Run as Administrator: right-click run.bat -> Run as administrator")
        else:
            warn(f"LHM Computer.Open() failed: {e}")


def check_admin() -> None:
    """Check if running with admin privileges."""
    print(f"\n{BOLD}Privileges{RESET}")
    try:
        import ctypes
        is_admin = bool(ctypes.windll.shell32.IsUserAnAdmin())
        if is_admin:
            ok("Running as Administrator")
        else:
            warn("Not running as Administrator — LHM needs admin for hardware access",
                 "Right-click run.bat -> Run as administrator")
    except Exception:
        warn("Could not check admin status")


def check_config() -> None:
    """Verify config file if present."""
    print(f"\n{BOLD}Configuration{RESET}")
    config_file = PROJECT_ROOT / "config.json"
    if config_file.exists():
        try:
            import json
            with open(config_file) as f:
                json.load(f)
            ok("config.json is valid JSON")
        except Exception as e:
            fail(f"config.json parse error: {e}")
    else:
        ok("No config.json (using defaults)")


def main() -> int:
    global _warnings, _errors

    print(f"\n{BOLD}{'=' * 50}")
    print(f"  HumWatch Pre-flight Check")
    print(f"{'=' * 50}{RESET}")

    check_python()
    check_packages()
    check_lhm_dll()
    check_lhm_load()
    check_admin()
    check_config()

    # Summary
    print(f"\n{BOLD}{'=' * 50}{RESET}")
    if _errors > 0:
        print(f"  {RED}FAILED{RESET} — {_errors} error(s), {_warnings} warning(s)")
        print(f"  Fix the errors above before running HumWatch.")
        return 2
    elif _warnings > 0:
        print(f"  {YELLOW}PASSED WITH WARNINGS{RESET} — {_warnings} warning(s)")
        print(f"  HumWatch will run but some features may be limited.")
        return 1
    else:
        print(f"  {GREEN}ALL CHECKS PASSED{RESET}")
        print(f"  HumWatch is ready to run with full sensor support.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
