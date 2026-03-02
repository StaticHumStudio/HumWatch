"""Base sensor interface for HumWatch."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import List


@dataclass
class MetricReading:
    """A single metric data point."""
    category: str       # 'cpu', 'gpu', 'memory', etc.
    metric_name: str    # 'cpu_temp_package', 'mem_used', etc.
    value: float
    unit: str           # '°C', '%', 'MB', 'MHz', 'RPM', 'W', 'V', 'MB/s', 's', 'mAh', 'bool'


class BaseSensor(ABC):
    """Abstract base class for all hardware sensors."""

    @abstractmethod
    def is_available(self) -> bool:
        """Return True if this sensor's hardware is present and readable."""
        ...

    @abstractmethod
    def collect(self) -> List[MetricReading]:
        """Collect current readings. Return empty list if unavailable."""
        ...

    def close(self) -> None:
        """Clean up resources. Override if needed."""
        pass
