from agent.collector import _map_battery_sensor, _map_cpu_sensor, _map_gpu_sensor


class DummySensorType:
    Temperature = object()
    Clock = object()
    Power = object()
    Voltage = object()
    Load = object()
    SmallData = object()
    Fan = object()
    Energy = object()
    Level = object()
    Current = object()


def test_cpu_temp_fallback_names_map_to_package():
    data = {}
    _map_cpu_sensor(data, DummySensorType.Temperature, "Tctl/Tdie", 72.5, DummySensorType)
    assert data["cpu_temp_package"] == 72.5


def test_gpu_hotspot_maps_primary_and_hotspot():
    data = {}
    _map_gpu_sensor(data, DummySensorType.Temperature, "GPU Hot Spot", 88.0, DummySensorType)
    assert data["gpu_temp_hotspot"] == 88.0
    assert data["gpu_temp"] == 88.0


def test_battery_remaining_capacity_is_preserved():
    data = {}
    _map_battery_sensor(data, DummySensorType.Energy, "Remaining Capacity", 41234.0, DummySensorType)
    assert data["battery_remaining_capacity"] == 41234.0
