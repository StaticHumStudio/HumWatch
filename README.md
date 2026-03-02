# HumWatch

**"What hums beneath the shell."**

A self-hosted, local-first hardware monitoring system for Windows PCs accessible over Tailscale.

---

## Features

- **Full hardware telemetry** — CPU, GPU, memory, disk, network, fans, battery
- **7-day rolling history** in a local SQLite database
- **Real-time dashboard** with live gauges, charts, and sparklines
- **Server-Sent Events** for instant updates without polling
- **Multi-machine view** — monitor all your PCs from one dashboard
- **Zero-config discovery** — GPU and battery sections appear automatically when hardware is present
- **Themeable** — ships with three themes, easy to create your own
- **Local-first** — no cloud, no accounts, all data stays on your machine
- **Tailscale-native** — designed for access over your mesh network

## What It Monitors

| Category | Metrics |
|----------|---------|
| CPU | Per-core temperature, load, clock speed, package power, voltage |
| GPU | Temperature, load, VRAM, core/memory clocks, power draw, fan speed |
| Memory | RAM and swap usage |
| Disk | Read/write throughput, volume usage, drive temperatures |
| Network | Upload/download rates, cumulative transfer |
| Battery | Charge level, charge rate, voltage, health/wear, cycle count |
| Fans | Individual fan RPMs |
| Processes | Top processes by CPU and memory usage |

## Quick Start

```bash
# Clone and enter the directory
cd HumWatch

# Install Python dependencies
pip install -r requirements.txt

# (Optional) Download LibreHardwareMonitor for full sensor access
powershell -ExecutionPolicy Bypass -File scripts\download-lhm.ps1

# Start the agent
python -m agent.main
```

Open **http://localhost:9100** in your browser.

Without LibreHardwareMonitor, HumWatch runs in psutil-only mode — you get CPU load, memory, disk, network, and battery basics. With LHM, you also get temperatures, voltages, GPU metrics, fan speeds, and more.

## Install as a Windows Service

HumWatch can run as a background service that starts automatically with Windows.

**Prerequisites:** [NSSM](https://nssm.cc/download) (the Non-Sucking Service Manager) on your PATH.

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1
```

This registers HumWatch as an auto-start service with log rotation. Manage it with:

```
nssm status HumWatch
nssm stop HumWatch
nssm start HumWatch
nssm restart HumWatch
```

To remove the service:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\uninstall-service.ps1
```

## Multi-Machine Setup

HumWatch is designed for Tailscale networks. Each PC runs its own HumWatch instance.

1. Install and start HumWatch on each machine
2. On any machine's dashboard, go to **Machines**
3. Enter the Tailscale IP (e.g., `100.64.0.2`) of another machine
4. The dashboard shows live status cards for all your machines

Each machine's data stays local. The multi-machine view fetches live snapshots over HTTP.

## Theming

HumWatch ships with three themes:

| Theme | Description |
|-------|-------------|
| **Default** | Void black with gold and teal accents |
| **Light** | Warm off-white with blue accents |
| **Terminal** | Green-on-black, monospace, scanlines |

Switch themes from **Settings** in the dashboard.

To create your own theme, see [THEMING.md](THEMING.md).

## Configuration

HumWatch reads from `config.json` at the project root. Environment variables take precedence.

| Setting | Config Key | Env Var | Default |
|---------|-----------|---------|---------|
| Port | `port` | `HUMWATCH_PORT` | `9100` |
| Collection interval | `collection_interval_seconds` | `HUMWATCH_INTERVAL` | `10` |
| Data retention | `retention_days` | — | `7` |
| Database path | `db_path` | `HUMWATCH_DB` | `humwatch.db` |

Alert thresholds (CPU/GPU temp warn/critical, RAM warn/critical) can be set in `config.json` or overridden per-browser in the Settings page.

## API

HumWatch exposes a REST API on the same port as the dashboard.

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Agent status, version, uptime |
| `GET /api/info` | Machine identity (hostname, OS, CPU, GPU, RAM, Tailscale IP) |
| `GET /api/config` | Current configuration and thresholds |
| `GET /api/current` | Latest readings grouped by category |
| `GET /api/history?metric=cpu_temp_package&from=...&to=...` | Historical time-series (auto-downsampled) |
| `GET /api/history/multi?metrics=cpu_temp_package,gpu_temp&from=...&to=...` | Multiple metrics in one request |
| `GET /api/processes` | Current top processes |
| `GET /api/sse` | Server-Sent Events stream (real-time) |

All timestamps are ISO 8601 UTC. History queries are automatically downsampled based on the requested time range.

## Tech Stack

- **Agent:** Python 3.10+, FastAPI, Uvicorn, psutil, aiosqlite
- **Sensors:** LibreHardwareMonitor (optional, via pythonnet)
- **Database:** SQLite in WAL mode
- **Dashboard:** Vanilla JavaScript, Chart.js 4, Lucide Icons
- **Fonts:** Inter, JetBrains Mono (Google Fonts CDN)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `python -m agent.main`
5. Submit a pull request

## License

[MIT](LICENSE) — Copyright (c) 2026 Static Hum Studio

---

*A Static Hum Studio Production*
