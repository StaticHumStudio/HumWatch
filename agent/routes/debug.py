"""Debug / diagnostics endpoint — exposes LHM status, Python info, and recent logs."""

import os
import sys
from pathlib import Path

from fastapi import APIRouter, Query

from agent.collector import get_lhm_status
from agent.config import PROJECT_ROOT

router = APIRouter()

_LOG_FILE = PROJECT_ROOT / "humwatch.log"


@router.get("/debug")
async def get_debug(log_lines: int = Query(80, ge=1, le=500)):
    """Return diagnostic information for remote troubleshooting."""
    lhm = get_lhm_status()

    # Python environment info
    python_info = {
        "executable": sys.executable,
        "version": sys.version,
        "in_venv": sys.prefix != sys.base_prefix,
        "prefix": sys.prefix,
        "base_prefix": sys.base_prefix,
    }

    # Check LHM DLL exists
    lhm_dll = PROJECT_ROOT / "lib" / "LibreHardwareMonitorLib.dll"
    lhm_info = {
        **lhm,
        "dll_exists": lhm_dll.exists(),
        "dll_path": str(lhm_dll),
    }

    # Check if running as admin
    is_admin = False
    try:
        import ctypes
        is_admin = bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        pass

    # Read tail of log file
    log_tail = []
    if _LOG_FILE.exists():
        try:
            with open(_LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
                log_tail = [line.rstrip() for line in lines[-log_lines:]]
        except Exception as e:
            log_tail = [f"Error reading log: {e}"]

    return {
        "lhm": lhm_info,
        "python": python_info,
        "is_admin": is_admin,
        "pid": os.getpid(),
        "cwd": os.getcwd(),
        "log_tail": log_tail,
    }
