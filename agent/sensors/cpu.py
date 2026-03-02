"""CPU metrics: temperatures, load, clocks, power, voltage."""

import logging
from typing import List

import psutil

from agent.sensors.base import BaseSensor, MetricReading

logger = logging.getLogger("humwatch.sensors.cpu")


class CpuSensor(BaseSensor):

    def __init__(self):
        # Prime psutil's CPU percent — first call always returns 0
        psutil.cpu_percent(percpu=True)

    def is_available(self) -> bool:
        return True

    def collect(self) -> List[MetricReading]:
        readings: List[MetricReading] = []

        # Total CPU load
        total_load = psutil.cpu_percent(interval=None)
        readings.append(MetricReading("cpu", "cpu_load_total", total_load, "%"))

        # Per-core CPU load
        per_core = psutil.cpu_percent(interval=None, percpu=True)
        for i, load in enumerate(per_core):
            readings.append(MetricReading("cpu", f"cpu_load_core_{i}", load, "%"))

        return readings

    def collect_lhm(self, lhm_data: dict) -> List[MetricReading]:
        """Collect LHM-sourced CPU metrics (temps, clocks, power, voltage)."""
        readings: List[MetricReading] = []

        for key, value in lhm_data.items():
            if value is None:
                continue
            if key == "cpu_temp_package":
                readings.append(MetricReading("cpu", key, value, "°C"))
            elif key.startswith("cpu_temp_core_"):
                readings.append(MetricReading("cpu", key, value, "°C"))
            elif key.startswith("cpu_clock_core_"):
                readings.append(MetricReading("cpu", key, value, "MHz"))
            elif key == "cpu_power_package":
                readings.append(MetricReading("cpu", key, value, "W"))
            elif key == "cpu_voltage":
                readings.append(MetricReading("cpu", key, value, "V"))

        return readings
