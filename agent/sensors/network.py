"""Network metrics: throughput rates and cumulative bytes."""

import time
from typing import List, Optional

import psutil

from agent.sensors.base import BaseSensor, MetricReading


class NetworkSensor(BaseSensor):

    def __init__(self):
        self._prev_bytes_sent: Optional[int] = None
        self._prev_bytes_recv: Optional[int] = None
        self._prev_time: Optional[float] = None

    def is_available(self) -> bool:
        return True

    def collect(self) -> List[MetricReading]:
        readings: List[MetricReading] = []
        now = time.time()

        counters = psutil.net_io_counters(pernic=False)
        if counters is None:
            return readings

        bytes_sent = counters.bytes_sent
        bytes_recv = counters.bytes_recv

        # Cumulative totals
        readings.append(MetricReading("network", "net_bytes_sent", bytes_sent, "bytes"))
        readings.append(MetricReading("network", "net_bytes_recv", bytes_recv, "bytes"))

        # Rate calculation (delta / elapsed)
        if self._prev_bytes_sent is not None and self._prev_time is not None:
            elapsed = now - self._prev_time
            if elapsed > 0:
                sent_rate = max(0, bytes_sent - self._prev_bytes_sent) / elapsed / (1024 * 1024)
                recv_rate = max(0, bytes_recv - self._prev_bytes_recv) / elapsed / (1024 * 1024)
                readings.append(MetricReading("network", "net_sent_rate", round(sent_rate, 4), "MB/s"))
                readings.append(MetricReading("network", "net_recv_rate", round(recv_rate, 4), "MB/s"))

        self._prev_bytes_sent = bytes_sent
        self._prev_bytes_recv = bytes_recv
        self._prev_time = now

        return readings
