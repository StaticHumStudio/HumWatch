"""Main collection loop — orchestrates sensor polling, LHM thread, DB writes, and SSE pub/sub."""

import asyncio
import logging
import queue
import threading
import time
from datetime import datetime, timezone
from typing import Dict, List, Optional, Set

import psutil

from agent.config import get_config, PROJECT_ROOT
from agent.database import get_db
from agent.sensors.base import MetricReading
from agent.sensors.system import SystemSensor
from agent.sensors.memory import MemorySensor
from agent.sensors.network import NetworkSensor
from agent.sensors.disk import DiskSensor
from agent.sensors.cpu import CpuSensor
from agent.sensors.gpu import GpuSensor
from agent.sensors.fan import FanSensor
from agent.sensors.battery import BatterySensor

logger = logging.getLogger("humwatch.collector")

# --- Module-level state ---

# Latest readings for /api/current (updated each tick)
latest_readings: Dict = {}

# Latest process snapshot for /api/processes
latest_processes: List[Dict] = []

# SSE subscriber queues
_subscribers: Set[asyncio.Queue] = set()
_subscribers_lock = threading.Lock()

# Collector task reference
_collector_task: Optional[asyncio.Task] = None

# LHM thread control
_lhm_thread: Optional[threading.Thread] = None
_lhm_stop_event = threading.Event()
_lhm_queue: queue.Queue = queue.Queue(maxsize=5)
_lhm_available = False
_gpu_name: Optional[str] = None


def get_latest_readings() -> Dict:
    """Get the latest readings dict (for API routes)."""
    return latest_readings


def get_latest_processes() -> List[Dict]:
    """Get the latest process snapshot (for API routes)."""
    return latest_processes


def get_lhm_status() -> dict:
    """Get LHM thread diagnostic info (for /api/debug)."""
    return {
        "lhm_available": _lhm_available,
        "gpu_name": _gpu_name,
        "lhm_thread_alive": _lhm_thread.is_alive() if _lhm_thread else False,
        "lhm_queue_size": _lhm_queue.qsize(),
    }


def subscribe() -> asyncio.Queue:
    """Subscribe to real-time metric updates. Returns a queue that receives data each tick."""
    q: asyncio.Queue = asyncio.Queue(maxsize=10)
    with _subscribers_lock:
        _subscribers.add(q)
    return q


def unsubscribe(q: asyncio.Queue) -> None:
    """Unsubscribe from metric updates."""
    with _subscribers_lock:
        _subscribers.discard(q)


async def _publish(data: dict) -> None:
    """Push data to all SSE subscribers."""
    with _subscribers_lock:
        dead: List[asyncio.Queue] = []
        for q in _subscribers:
            try:
                q.put_nowait(data)
            except asyncio.QueueFull:
                # Slow consumer — drop oldest and retry
                try:
                    q.get_nowait()
                    q.put_nowait(data)
                except (asyncio.QueueEmpty, asyncio.QueueFull):
                    dead.append(q)
        for q in dead:
            _subscribers.discard(q)


# --- LHM Thread ---

def _lhm_worker():
    """Dedicated thread for LibreHardwareMonitor sensor reading."""
    global _lhm_available, _gpu_name

    try:
        import clr
        lib_path = str(PROJECT_ROOT / "lib" / "LibreHardwareMonitorLib")
        clr.AddReference(lib_path)
        from LibreHardwareMonitor.Hardware import Computer
    except Exception as e:
        logger.warning("LibreHardwareMonitor not available: %s", e)
        logger.info("Running in psutil-only mode (no temperature, voltage, GPU, or fan data)")
        _lhm_available = False
        return

    try:
        computer = Computer()
        computer.IsCpuEnabled = True
        computer.IsGpuEnabled = True
        computer.IsMemoryEnabled = True
        computer.IsMotherboardEnabled = True
        computer.IsStorageEnabled = True
        computer.IsBatteryEnabled = True
        computer.IsControllerEnabled = True
        computer.IsNetworkEnabled = True
        computer.Open()
        _lhm_available = True
        logger.info("LibreHardwareMonitor initialized successfully")
    except Exception as e:
        logger.warning("Failed to initialize LHM Computer: %s", e)
        _lhm_available = False
        return

    # Log discovered hardware
    for hardware in computer.Hardware:
        logger.info("LHM found: %s (type=%s)", hardware.Name, hardware.HardwareType)

    try:
        # Read immediately on first cycle, then sleep between subsequent reads
        first_run = True
        while not _lhm_stop_event.is_set():
            if not first_run:
                if _lhm_stop_event.wait(timeout=get_config().collection_interval_seconds):
                    break
            first_run = False
            try:
                data = _read_lhm_sensors(computer)
                if data:
                    logger.debug("LHM read %d metrics: %s", len(data), list(data.keys()))
                # Non-blocking put — drop oldest if full
                try:
                    _lhm_queue.put_nowait(data)
                except queue.Full:
                    try:
                        _lhm_queue.get_nowait()
                    except queue.Empty:
                        pass
                    _lhm_queue.put_nowait(data)
            except Exception as e:
                logger.error("LHM read error: %s", e)
    finally:
        try:
            computer.Close()
        except Exception:
            pass
        logger.info("LHM worker thread stopped")


_lhm_first_dump = True  # Log all sensors on first read for diagnostics


def _extract_index(name: str) -> Optional[int]:
    """Extract a zero-based index from sensor names like `Core #3` or `Core 3`."""
    digits = "".join(c for c in name if c.isdigit())
    if not digits:
        return None
    return max(0, int(digits) - 1)


def _walk_hardware_nodes(hardware):
    """Yield hardware and all nested sub-hardware nodes recursively."""
    yield hardware
    for sub in hardware.SubHardware:
        yield from _walk_hardware_nodes(sub)


def _read_lhm_sensors(computer) -> dict:
    """Read all sensors from LHM and return as a flat dict."""
    global _gpu_name, _lhm_first_dump
    from LibreHardwareMonitor.Hardware import HardwareType, SensorType

    data = {}
    fan_index = 0

    for disk_index, hardware in enumerate(computer.Hardware):
        hardware.Update()

        # Track GPU name
        hw_type = hardware.HardwareType
        is_gpu = hw_type in (
            HardwareType.GpuNvidia, HardwareType.GpuAmd, HardwareType.GpuIntel
        )
        if is_gpu and _gpu_name is None:
            _gpu_name = hardware.Name

        for node in _walk_hardware_nodes(hardware):
            node.Update()

            # One-time diagnostic dump of ALL sensors for this node
            if _lhm_first_dump:
                sensor_list = [f"  {s.SensorType}: {s.Name} = {s.Value}" for s in node.Sensors]
                logger.info(
                    "LHM sensors for %s (type=%s): %d sensors%s",
                    node.Name,
                    node.HardwareType,
                    len(sensor_list),
                    "\n" + "\n".join(sensor_list) if sensor_list else " (none)",
                )

            for sensor in node.Sensors:
                if sensor.Value is None:
                    continue

                s_type = sensor.SensorType
                s_name = sensor.Name
                s_value = float(sensor.Value)

                if is_gpu:
                    _map_gpu_sensor(data, s_type, s_name, s_value, SensorType)
                elif hw_type == HardwareType.Cpu:
                    _map_cpu_sensor(data, s_type, s_name, s_value, SensorType)
                elif hw_type == HardwareType.Battery:
                    _map_battery_sensor(data, s_type, s_name, s_value, SensorType)
                elif hw_type == HardwareType.Storage:
                    if s_type == SensorType.Temperature:
                        data[f"disk_temp_{disk_index}"] = s_value

                if s_type == SensorType.Fan:
                    data[f"fan_{fan_index}_speed"] = s_value
                    fan_index += 1

    _lhm_first_dump = False
    return data


def _map_cpu_sensor(data, s_type, s_name, s_value, SensorType):
    """Map a CPU LHM sensor to our metric names."""
    if s_type == SensorType.Temperature:
        name_lower = s_name.lower()
        if (
            "package" in name_lower
            or "total" in name_lower
            or "tdie" in name_lower
            or "tctl" in name_lower
            or "cpu" == name_lower.strip()
        ):
            data["cpu_temp_package"] = s_value
        elif "core" in name_lower or "ccd" in name_lower:
            idx = _extract_index(s_name)
            if idx is not None:
                data[f"cpu_temp_core_{idx}"] = s_value
    elif s_type == SensorType.Clock:
        name_lower = s_name.lower()
        if "bus" in name_lower:
            data["cpu_clock_bus"] = s_value
        elif "core" in name_lower or "ccd" in name_lower or "cpu" in name_lower:
            idx = _extract_index(s_name)
            if idx is not None:
                data[f"cpu_clock_core_{idx}"] = s_value
            elif "cpu_clock_core_0" not in data:
                # Fallback for CPUs that only expose a single generic CPU clock sensor.
                data["cpu_clock_core_0"] = s_value
    elif s_type == SensorType.Power:
        name_lower = s_name.lower()
        if "package" in name_lower or "total" in name_lower:
            data["cpu_power_package"] = s_value
        elif "cores" in name_lower:
            data["cpu_power_cores"] = s_value
    elif s_type == SensorType.Voltage:
        name_lower = s_name.lower()
        if "vid" in name_lower and "cpu_voltage" not in data:
            data["cpu_voltage"] = s_value
        elif "cpu" in name_lower or "vcore" in name_lower or "package" in name_lower:
            data["cpu_voltage"] = s_value


def _map_gpu_sensor(data, s_type, s_name, s_value, SensorType):
    """Map a GPU LHM sensor to our metric names.

    Intel iGPUs report load as 'D3D 3D', 'D3D Copy', etc. — not 'GPU Core'.
    They also use shared system RAM, so SmallData values may already be in MB.
    """
    name_lower = s_name.lower()

    if s_type == SensorType.Temperature:
        if "hot spot" in name_lower or "hotspot" in name_lower:
            data["gpu_temp_hotspot"] = s_value
            if "gpu_temp" not in data:
                data["gpu_temp"] = s_value
        elif "memory" in name_lower:
            data["gpu_temp_memory"] = s_value
            if "gpu_temp" not in data:
                data["gpu_temp"] = s_value
        else:
            data["gpu_temp"] = s_value
    elif s_type == SensorType.Load:
        # For iGPU: take 'D3D 3D' as the primary load, or 'GPU Core', or first load seen
        if "3d" in name_lower or "core" in name_lower or "gpu" in name_lower:
            data["gpu_load"] = s_value
        elif "gpu_load" not in data:
            # Fallback: take any load sensor if we haven't found one yet
            data["gpu_load"] = s_value
    elif s_type == SensorType.Clock:
        if "memory" in name_lower:
            data["gpu_clock_memory"] = s_value
        else:
            data["gpu_clock_core"] = s_value
    elif s_type == SensorType.SmallData:
        if "used" in name_lower or "usage" in name_lower:
            # Discrete GPUs report in GB, iGPUs may report in MB
            # If value < 16 it's likely GB, otherwise MB
            data["gpu_vram_used"] = s_value * 1024 if s_value < 16 else s_value
        elif "total" in name_lower or "available" in name_lower:
            data["gpu_vram_total"] = s_value * 1024 if s_value < 16 else s_value
    elif s_type == SensorType.Power:
        if "core" in name_lower and "gpu_power" not in data:
            data["gpu_power"] = s_value
        elif "package" in name_lower or "total" in name_lower:
            data["gpu_power"] = s_value
        elif "gpu_power" not in data:
            data["gpu_power"] = s_value
    elif s_type == SensorType.Fan:
        data["gpu_fan_speed"] = s_value


def _map_battery_sensor(data, s_type, s_name, s_value, SensorType):
    """Map a Battery LHM sensor to our metric names."""
    if s_type == SensorType.Voltage:
        data["battery_voltage"] = s_value
    elif s_type == SensorType.Power:
        data["battery_charge_rate"] = s_value
    elif s_type == SensorType.Current:
        data["battery_current"] = s_value
    elif s_type == SensorType.Energy:
        name_lower = s_name.lower()
        if "designed" in name_lower:
            data["battery_designed_capacity"] = s_value
        elif "remaining" not in name_lower:
            # "Fully-Charged Capacity" → current max capacity
            data["battery_current_capacity"] = s_value
        else:
            data["battery_remaining_capacity"] = s_value
    elif s_type == getattr(SensorType, "Throughput", None):
        data["battery_charge_rate"] = s_value
    elif s_type == SensorType.Temperature:
        data["battery_temp"] = s_value
    elif s_type == SensorType.Level:
        name_lower = s_name.lower()
        if "degradation" in name_lower or "wear" in name_lower:
            data["battery_degradation"] = s_value
        elif "charge" in name_lower:
            data["battery_charge_level"] = s_value


# --- Main Collection Loop ---

async def start_collector():
    """Start the collection loop and LHM thread."""
    global _collector_task, _lhm_thread

    # Start LHM thread
    _lhm_stop_event.clear()
    _lhm_thread = threading.Thread(target=_lhm_worker, name="lhm-worker", daemon=True)
    _lhm_thread.start()

    # Give LHM time to initialize and do its first read
    await asyncio.sleep(3)

    # Update GPU name in machine_info if detected
    if _gpu_name:
        from agent.services.machine_info import update_machine_info
        await update_machine_info(gpu_name=_gpu_name)
        logger.info("GPU detected: %s", _gpu_name)
    else:
        logger.info("No discrete GPU detected by LHM")

    # Start async collection loop
    _collector_task = asyncio.create_task(_collection_loop())
    logger.info("Collector started")


async def stop_collector():
    """Stop the collection loop and LHM thread."""
    global _collector_task, _lhm_thread

    if _collector_task:
        _collector_task.cancel()
        try:
            await _collector_task
        except asyncio.CancelledError:
            pass
        _collector_task = None

    _lhm_stop_event.set()
    if _lhm_thread and _lhm_thread.is_alive():
        _lhm_thread.join(timeout=5)
    _lhm_thread = None

    logger.info("Collector stopped")


async def _collection_loop():
    """Main collection loop — runs every collection_interval_seconds."""
    global latest_readings, latest_processes

    config = get_config()
    interval = config.collection_interval_seconds

    # Initialize psutil-based sensors
    sensors = {
        "system": SystemSensor(),
        "memory": MemorySensor(),
        "network": NetworkSensor(),
        "disk": DiskSensor(),
        "cpu": CpuSensor(),
        "gpu": GpuSensor(),
        "fan": FanSensor(),
        "battery": BatterySensor(),
    }

    enabled = set(config.enable_categories)

    # One-time diagnostic: log sensor availability
    for cat_name, sensor in sensors.items():
        avail = sensor.is_available()
        logger.info("Sensor %s: available=%s, has_collect_lhm=%s",
                     cat_name, avail, hasattr(sensor, "collect_lhm"))

    while True:
        try:
            tick_start = time.time()
            timestamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

            all_readings: List[MetricReading] = []

            # Collect psutil-based metrics
            for cat_name, sensor in sensors.items():
                if cat_name not in enabled:
                    continue
                try:
                    if sensor.is_available():
                        readings = sensor.collect()
                        all_readings.extend(readings)
                except Exception as e:
                    logger.debug("Sensor %s error: %s", cat_name, e)

            # Grab LHM data from queue (latest available)
            lhm_data: dict = {}
            while not _lhm_queue.empty():
                try:
                    lhm_data = _lhm_queue.get_nowait()
                except queue.Empty:
                    break

            # Merge LHM data into sensor readings
            if lhm_data:
                for cat_name, sensor in sensors.items():
                    if cat_name not in enabled:
                        continue
                    if hasattr(sensor, "collect_lhm"):
                        try:
                            lhm_readings = sensor.collect_lhm(lhm_data)
                            all_readings.extend(lhm_readings)
                        except Exception as e:
                            logger.debug("LHM sensor %s error: %s", cat_name, e)

            # Collect top processes
            processes = _collect_processes(config.process_snapshot_count)

            # Build the structured readings dict for API/SSE
            categories: Dict = {}
            for reading in all_readings:
                if reading.category not in categories:
                    categories[reading.category] = {}
                categories[reading.category][reading.metric_name] = {
                    "value": reading.value,
                    "unit": reading.unit,
                }

            # Update in-memory state
            latest_readings = {
                "timestamp": timestamp,
                "categories": categories,
            }
            latest_processes = processes

            # Write to database
            await _write_metrics(timestamp, all_readings)
            await _write_processes(timestamp, processes)

            # Publish to SSE subscribers
            await _publish({
                "metrics": latest_readings,
                "processes": {
                    "timestamp": timestamp,
                    "processes": processes,
                },
            })

            # Sleep for the remainder of the interval
            elapsed = time.time() - tick_start
            sleep_time = max(0.1, interval - elapsed)
            await asyncio.sleep(sleep_time)

        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error("Collection loop error: %s", e)
            await asyncio.sleep(interval)


def _collect_processes(count: int) -> List[Dict]:
    """Collect top N processes by CPU usage."""
    procs = []
    for proc in psutil.process_iter(["pid", "name", "cpu_percent", "memory_info"]):
        try:
            info = proc.info
            mem_mb = info["memory_info"].rss / (1024 * 1024) if info.get("memory_info") else 0
            procs.append({
                "pid": info["pid"],
                "name": info["name"] or "Unknown",
                "cpu_percent": info.get("cpu_percent") or 0.0,
                "memory_mb": round(mem_mb, 1),
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue

    # Sort by CPU usage descending, take top N
    procs.sort(key=lambda p: p["cpu_percent"], reverse=True)
    return procs[:count]


async def _write_metrics(timestamp: str, readings: List[MetricReading]):
    """Batch insert metric readings into the database."""
    if not readings:
        return

    db = await get_db()
    rows = [
        (timestamp, r.category, r.metric_name, r.value, r.unit)
        for r in readings
    ]
    await db.executemany(
        "INSERT INTO metrics (timestamp, category, metric_name, value, unit) VALUES (?, ?, ?, ?, ?)",
        rows,
    )
    await db.commit()


async def _write_processes(timestamp: str, processes: List[Dict]):
    """Batch insert process snapshots into the database."""
    if not processes:
        return

    db = await get_db()
    rows = [
        (timestamp, p["pid"], p["name"], p["cpu_percent"], p["memory_mb"])
        for p in processes
    ]
    await db.executemany(
        "INSERT INTO process_snapshots (timestamp, pid, name, cpu_percent, memory_mb) VALUES (?, ?, ?, ?, ?)",
        rows,
    )
    await db.commit()
