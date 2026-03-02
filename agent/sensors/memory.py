"""Memory metrics: RAM and swap usage."""

from typing import List

import psutil

from agent.sensors.base import BaseSensor, MetricReading


class MemorySensor(BaseSensor):

    def is_available(self) -> bool:
        return True

    def collect(self) -> List[MetricReading]:
        readings: List[MetricReading] = []

        vm = psutil.virtual_memory()
        readings.append(MetricReading("memory", "mem_used", vm.used / (1024 * 1024), "MB"))
        readings.append(MetricReading("memory", "mem_total", vm.total / (1024 * 1024), "MB"))
        readings.append(MetricReading("memory", "mem_percent", vm.percent, "%"))

        swap = psutil.swap_memory()
        readings.append(MetricReading("memory", "mem_swap_used", swap.used / (1024 * 1024), "MB"))
        readings.append(MetricReading("memory", "mem_swap_total", swap.total / (1024 * 1024), "MB"))

        return readings
