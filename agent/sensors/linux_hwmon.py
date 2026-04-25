"""Linux hwmon/sysfs reader — produces the same dict format as the LHM worker.

Reads from /sys/class/hwmon/, /sys/class/drm/, /sys/devices/system/cpu/,
and psutil.sensors_temperatures()/sensors_fans() to collect hardware metrics
on Linux without requiring LibreHardwareMonitor.
"""

import glob
import logging
import os
from pathlib import Path
from typing import Dict, Optional

logger = logging.getLogger("humwatch.sensors.linux_hwmon")

# Cache hwmon paths on first discovery so we don't re-scan every tick
_hwmon_cache: Dict[str, Path] = {}  # chip_name -> hwmon path
_gpu_drm_path: Optional[Path] = None
_gpu_name: Optional[str] = None


def _read_sysfs(path: str | Path, default: Optional[str] = None) -> Optional[str]:
    """Read a single-line sysfs file. Returns None on any failure."""
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except (OSError, IOError):
        return default


def _read_sysfs_int(path: str | Path) -> Optional[int]:
    val = _read_sysfs(path)
    if val is None:
        return None
    try:
        return int(val)
    except ValueError:
        return None


def _read_sysfs_float(path: str | Path) -> Optional[float]:
    val = _read_sysfs(path)
    if val is None:
        return None
    try:
        return float(val)
    except ValueError:
        return None


def _discover_hwmon() -> None:
    """Build a mapping of chip name -> hwmon sysfs path."""
    global _hwmon_cache
    _hwmon_cache.clear()

    for hwmon_dir in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        name = _read_sysfs(os.path.join(hwmon_dir, "name"))
        if name:
            _hwmon_cache[name] = Path(hwmon_dir)

    logger.info("Discovered hwmon chips: %s", list(_hwmon_cache.keys()))


def _discover_gpu_drm() -> None:
    """Find the amdgpu DRM device path for GPU load/VRAM."""
    global _gpu_drm_path, _gpu_name

    for card_dir in sorted(glob.glob("/sys/class/drm/card[0-9]*/device")):
        # Check if it's an amdgpu device
        driver_link = os.path.join(card_dir, "driver")
        if os.path.islink(driver_link):
            driver_name = os.path.basename(os.readlink(driver_link))
            if driver_name == "amdgpu":
                _gpu_drm_path = Path(card_dir)
                # Try to get GPU name from the hwmon or uevent
                uevent = _read_sysfs(os.path.join(card_dir, "uevent"))
                if uevent:
                    for line in uevent.splitlines():
                        if line.startswith("PCI_SUBSYS_ID="):
                            _gpu_name = f"AMD Radeon (amdgpu)"
                            break
                if _gpu_name is None:
                    _gpu_name = "AMD Radeon (amdgpu)"
                logger.info("Found amdgpu DRM device at %s", _gpu_drm_path)
                return

    # Check for nvidia
    for card_dir in sorted(glob.glob("/sys/class/drm/card[0-9]*/device")):
        driver_link = os.path.join(card_dir, "driver")
        if os.path.islink(driver_link):
            driver_name = os.path.basename(os.readlink(driver_link))
            if driver_name == "nvidia":
                _gpu_drm_path = Path(card_dir)
                _gpu_name = "NVIDIA GPU"
                logger.info("Found nvidia DRM device at %s", _gpu_drm_path)
                return


def get_gpu_name() -> Optional[str]:
    """Return detected GPU name (for machine_info)."""
    return _gpu_name


def init() -> None:
    """Run discovery once at startup."""
    _discover_hwmon()
    _discover_gpu_drm()


def read_sensors() -> dict:
    """Read all available Linux sensors. Returns a flat dict matching LHM key format."""
    if not _hwmon_cache:
        _discover_hwmon()
    if _gpu_drm_path is None:
        _discover_gpu_drm()

    data: dict = {}

    _read_cpu_temps(data)
    _read_cpu_clocks(data)
    _read_gpu(data)
    _read_disk_temps(data)
    _read_fans(data)

    return data


def _read_cpu_temps(data: dict) -> None:
    """Read CPU temperatures from k10temp (AMD) or coretemp (Intel)."""
    # AMD k10temp
    hwmon = _hwmon_cache.get("k10temp")
    if hwmon:
        tctl = _read_sysfs_float(hwmon / "temp1_input")
        if tctl is not None:
            data["cpu_temp_package"] = tctl / 1000.0

        # k10temp on Zen 3+ may expose per-CCD temps (temp2, temp3, etc.)
        for i in range(2, 10):
            temp_file = hwmon / f"temp{i}_input"
            label_file = hwmon / f"temp{i}_label"
            if temp_file.exists():
                label = _read_sysfs(label_file) or ""
                temp = _read_sysfs_float(temp_file)
                if temp is not None:
                    # CCD labels like "Tccd1", "Tccd2"
                    if "ccd" in label.lower():
                        idx = i - 2
                        data[f"cpu_temp_core_{idx}"] = temp / 1000.0
        return

    # Intel coretemp
    hwmon = _hwmon_cache.get("coretemp")
    if hwmon:
        # coretemp exposes Package id 0, Core 0, Core 1, etc.
        for i in range(1, 50):
            temp_file = hwmon / f"temp{i}_input"
            label_file = hwmon / f"temp{i}_label"
            if not temp_file.exists():
                break
            label = (_read_sysfs(label_file) or "").lower()
            temp = _read_sysfs_float(temp_file)
            if temp is None:
                continue
            temp_c = temp / 1000.0
            if "package" in label:
                data["cpu_temp_package"] = temp_c
            elif "core" in label:
                # "Core 0", "Core 1", etc.
                digits = "".join(c for c in label if c.isdigit())
                if digits:
                    data[f"cpu_temp_core_{int(digits)}"] = temp_c


def _read_cpu_clocks(data: dict) -> None:
    """Read per-core CPU clocks from cpufreq sysfs."""
    cpu_dirs = sorted(glob.glob("/sys/devices/system/cpu/cpu[0-9]*"))
    for cpu_dir in cpu_dirs:
        freq_file = os.path.join(cpu_dir, "cpufreq", "scaling_cur_freq")
        freq_khz = _read_sysfs_int(freq_file)
        if freq_khz is not None:
            cpu_num = os.path.basename(cpu_dir).replace("cpu", "")
            try:
                idx = int(cpu_num)
                data[f"cpu_clock_core_{idx}"] = freq_khz / 1000.0  # kHz -> MHz
            except ValueError:
                pass


def _read_gpu(data: dict) -> None:
    """Read GPU metrics from amdgpu hwmon and DRM sysfs."""
    # Temperature, power, voltage, shader clock from hwmon
    hwmon = _hwmon_cache.get("amdgpu")
    if hwmon:
        temp = _read_sysfs_float(hwmon / "temp1_input")
        if temp is not None:
            data["gpu_temp"] = temp / 1000.0

        power = _read_sysfs_float(hwmon / "power1_input")
        if power is not None:
            data["gpu_power"] = power / 1000000.0  # microwatts -> watts

        # freq1 = shader clock (sclk)
        freq = _read_sysfs_float(hwmon / "freq1_input")
        if freq is not None:
            data["gpu_clock_core"] = freq / 1000000.0  # Hz -> MHz

        # freq2 = memory clock (mclk) if present
        freq2 = _read_sysfs_float(hwmon / "freq2_input")
        if freq2 is not None:
            data["gpu_clock_memory"] = freq2 / 1000000.0

    # GPU load and VRAM from DRM sysfs
    if _gpu_drm_path:
        busy = _read_sysfs_float(_gpu_drm_path / "gpu_busy_percent")
        if busy is not None:
            data["gpu_load"] = busy

        vram_used = _read_sysfs_int(_gpu_drm_path / "mem_info_vram_used")
        if vram_used is not None:
            data["gpu_vram_used"] = vram_used / (1024 * 1024)  # bytes -> MB

        vram_total = _read_sysfs_int(_gpu_drm_path / "mem_info_vram_total")
        if vram_total is not None:
            data["gpu_vram_total"] = vram_total / (1024 * 1024)

        # Memory clock from pp_dpm_mclk (fallback if not in hwmon)
        if "gpu_clock_memory" not in data:
            mclk_text = _read_sysfs(_gpu_drm_path / "pp_dpm_mclk")
            if mclk_text:
                for line in mclk_text.splitlines():
                    if "*" in line:
                        # "2: 1200Mhz *" -> extract the active frequency
                        parts = line.split()
                        if len(parts) >= 2:
                            freq_str = parts[1].lower().replace("mhz", "")
                            try:
                                data["gpu_clock_memory"] = float(freq_str)
                            except ValueError:
                                pass
                        break


def _read_disk_temps(data: dict) -> None:
    """Read NVMe/disk temperatures from hwmon."""
    disk_index = 0
    for chip_name, hwmon in _hwmon_cache.items():
        if chip_name.startswith("nvme") or chip_name.startswith("drivetemp"):
            temp = _read_sysfs_float(hwmon / "temp1_input")
            if temp is not None:
                data[f"disk_temp_{disk_index}"] = temp / 1000.0
                disk_index += 1


def _read_fans(data: dict) -> None:
    """Read fan speeds from any hwmon chip that exposes them."""
    fan_index = 0
    for chip_name, hwmon in _hwmon_cache.items():
        for i in range(1, 10):
            fan_file = hwmon / f"fan{i}_input"
            if fan_file.exists():
                rpm = _read_sysfs_int(fan_file)
                if rpm is not None:
                    data[f"fan_{fan_index}_speed"] = float(rpm)
                    fan_index += 1
