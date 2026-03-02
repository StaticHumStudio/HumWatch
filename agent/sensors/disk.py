"""Disk metrics: I/O rates, volume usage, temperatures."""

import logging
import time
from typing import Dict, List, Optional, Tuple

import psutil

from agent.sensors.base import BaseSensor, MetricReading

logger = logging.getLogger("humwatch.sensors.disk")


class DiskSensor(BaseSensor):

    def __init__(self):
        self._prev_io: Optional[Dict[str, Tuple[int, int]]] = None  # {disk: (read_bytes, write_bytes)}
        self._prev_time: Optional[float] = None

    def is_available(self) -> bool:
        return True

    def collect(self) -> List[MetricReading]:
        readings: List[MetricReading] = []
        now = time.time()

        # Volume usage
        try:
            partitions = psutil.disk_partitions(all=False)
            for part in partitions:
                try:
                    usage = psutil.disk_usage(part.mountpoint)
                    # Extract drive letter (e.g., "C" from "C:\")
                    drive = part.mountpoint.rstrip(":\\/ ").upper()
                    if drive:
                        readings.append(MetricReading(
                            "disk", f"disk_usage_{drive}", usage.percent, "%"
                        ))
                except (PermissionError, OSError):
                    pass
        except Exception as e:
            logger.debug("Error reading disk partitions: %s", e)

        # I/O throughput rates per physical disk
        try:
            io_counters = psutil.disk_io_counters(perdisk=True)
            if io_counters:
                current_io: Dict[str, Tuple[int, int]] = {}
                for disk_name, counters in io_counters.items():
                    current_io[disk_name] = (counters.read_bytes, counters.write_bytes)

                if self._prev_io is not None and self._prev_time is not None:
                    elapsed = now - self._prev_time
                    if elapsed > 0:
                        # Aggregate all physical disks for overall rate
                        total_read_rate = 0.0
                        total_write_rate = 0.0
                        for disk_name, (read_b, write_b) in current_io.items():
                            if disk_name in self._prev_io:
                                prev_read, prev_write = self._prev_io[disk_name]
                                read_rate = max(0, read_b - prev_read) / elapsed / (1024 * 1024)
                                write_rate = max(0, write_b - prev_write) / elapsed / (1024 * 1024)
                                total_read_rate += read_rate
                                total_write_rate += write_rate

                        readings.append(MetricReading(
                            "disk", "disk_read_rate", round(total_read_rate, 4), "MB/s"
                        ))
                        readings.append(MetricReading(
                            "disk", "disk_write_rate", round(total_write_rate, 4), "MB/s"
                        ))

                self._prev_io = current_io
                self._prev_time = now
            else:
                self._prev_time = now
        except Exception as e:
            logger.debug("Error reading disk I/O: %s", e)

        return readings

    def collect_lhm(self, lhm_data: dict) -> List[MetricReading]:
        """Collect LHM-sourced disk metrics (temperatures)."""
        readings: List[MetricReading] = []

        for key, value in lhm_data.items():
            if key.startswith("disk_temp_") and value is not None:
                readings.append(MetricReading("disk", key, value, "°C"))

        return readings
