# HumWatch

**"What hums beneath the shell."**

A self-hosted, local-first hardware monitoring system for Windows and Linux PCs.

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
- **Network-agnostic** — works over LAN, Tailscale, ZeroTier, WireGuard, or any overlay network

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

## Requirements

- **Windows 10/11** *or* **Linux** (any distro with `/sys/class/hwmon`)
- **A web browser** for the dashboard
- **Overlay network** *(optional)* — Tailscale, ZeroTier, WireGuard, or similar for multi-machine access across networks

## Installation

### Installer (recommended)

1. Download **`HumWatch-Setup-vX.X.X.exe`** from the [releases page](https://github.com/StaticHumStudio/HumWatch/releases)
2. Run the installer — click **Yes** when Windows asks for admin access
3. Follow the prompts (default install path `C:\HumWatch` is fine)

The installer handles everything: bundled Python 3.12, all dependencies, LibreHardwareMonitor (v0.9.6 + PawnIO driver), Windows service registration, firewall rule, and auto-start on boot.

Once installed, open **http://localhost:9100** in your browser.

### From source (development)

```bash
cd HumWatch
pip install -r requirements.txt

# (Optional) Download LibreHardwareMonitor for full sensor access
# Also installs the PawnIO driver (replaces deprecated WinRing0)
powershell -ExecutionPolicy Bypass -File scripts\download-lhm.ps1

python -m agent.main
```

Without LibreHardwareMonitor, HumWatch runs in psutil-only mode — you get CPU load, memory, disk, network, and battery basics. With LHM, you also get temperatures, voltages, GPU metrics, fan speeds, and more.

> **Note:** LHM v0.9.5+ requires the [PawnIO](https://github.com/PawnIO/PawnIO) driver (replaces the deprecated WinRing0 driver). The `download-lhm.ps1` script installs it automatically via `winget`. To install manually: `winget install PawnIO.PawnIO`

### Install as a Windows Service (from source)

```powershell
# Run as Administrator
powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1
```

This registers HumWatch as an auto-start service with log rotation. To remove:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\uninstall-service.ps1
```

### Linux (from source)

On Linux, HumWatch reads sensors directly from `/sys/class/hwmon`,
`/sys/class/drm`, and `/proc/cpuinfo`... no LHM, no extra drivers.

```bash
cd HumWatch
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m agent.main
```

To install as a systemd service, edit paths in `humwatch.service` if
needed, then:

```bash
sudo cp humwatch.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now humwatch
```

Check status with `systemctl status humwatch` and logs with
`journalctl -u humwatch -f`.

## Dashboard

The dashboard sidebar contains these pages:

| Page | Description |
|------|-------------|
| **Overview** | CPU load, GPU load, RAM usage, temps, battery at a glance |
| **CPU** | Per-core load, temperatures, clock speeds, power draw |
| **GPU** | Temperature, load, VRAM, fan speed (only with a dedicated GPU) |
| **Memory** | RAM and swap usage over time, top memory consumers |
| **Disk** | Read/write speeds, volume usage, drive temperatures |
| **Network** | Upload/download rates, cumulative transfer |
| **Battery** | Charge level, charge rate, health/wear (laptops only) |
| **Processes** | Top 10 resource-consuming processes, updated live |
| **Machines** | Multi-machine view with status cards |
| **Settings** | Themes, alert thresholds, configuration |

The connection indicator in the sidebar shows: **green** = live, **amber** = reconnecting, **gray** = disconnected.

## Multi-Machine Setup

Each PC runs its own HumWatch instance. Machines on the same LAN or overlay network (Tailscale, ZeroTier, WireGuard, etc.) can monitor each other.

1. Ensure machines can reach each other over the network (same LAN, VPN, or overlay network)
2. Install HumWatch on each machine you want to monitor
3. From any machine's dashboard, go to **Machines** and add the IP address of other machines
4. Click any machine card to open its full dashboard

IPs are saved per-browser. HumWatch auto-discovers other instances on your local subnet and via Tailscale/ZeroTier CLI if installed.

## Managing the Service

| Action | Command |
|--------|---------|
| Check status | `nssm status HumWatch` |
| Stop | `nssm stop HumWatch` |
| Start | `nssm start HumWatch` |
| Restart | `nssm restart HumWatch` |

Run these from an **Administrator PowerShell**. NSSM lives at `C:\HumWatch\tools\nssm.exe`.

### Uninstalling

Use **Windows Settings > Apps** (or **Control Panel > Programs and Features**) to uninstall HumWatch. The uninstaller stops and removes the service before deleting files.

## Configuration

HumWatch reads from `config.json` at the install root. Environment variables take precedence.

| Setting | Config Key | Env Var | Default |
|---------|-----------|---------|---------|
| Port | `port` | `HUMWATCH_PORT` | `9100` |
| Collection interval | `collection_interval_seconds` | `HUMWATCH_INTERVAL` | `10` |
| Data retention | `retention_days` | — | `7` |
| Database path | `db_path` | `HUMWATCH_DB` | `humwatch.db` |

Alert thresholds (CPU/GPU temp, RAM/disk usage, battery level) can be set in `config.json` or overridden per-browser in the Settings page.

After editing `config.json`, restart the service: `nssm restart HumWatch`

## Theming

HumWatch ships with three themes:

| Theme | Description |
|-------|-------------|
| **Default** | Void black with gold and teal accents |
| **Light** | Warm off-white with blue accents |
| **Terminal** | Green-on-black, monospace, scanlines |

Switch themes from **Settings** in the dashboard.

To create your own theme, see [THEMING.md](THEMING.md).

## Troubleshooting

**Can't open localhost:9100** — Check that the service is running: `nssm status HumWatch`. If stopped, run `nssm start HumWatch`. If port 9100 is taken, change `port` in `config.json` and restart the service.

**No temperatures or fan speeds** — Restart the service. Some hardware isn't supported by LibreHardwareMonitor. Check `C:\HumWatch\logs\humwatch-stderr.log` for errors.

**GPU section missing** — Normal if you only have integrated graphics. LibreHardwareMonitor can't read sensors on some integrated GPUs.

**Battery section missing** — Normal on desktops.

**Can't reach Machine A from Machine B** — Verify both machines are on the same network (LAN or overlay), HumWatch is running on Machine A, and you can ping Machine A's IP. If the firewall rule is missing:
```powershell
netsh advfirewall firewall add rule name="HumWatch" dir=in action=allow protocol=TCP localport=9100
```

**Dashboard says "Disconnected"** — Usually resolves in seconds. If not, check that the service is running and hard-refresh the browser (`Ctrl+Shift+R`).

**Database growing large** — Reduce `retention_days` in `config.json` and restart the service.

## API

HumWatch exposes a REST API on the same port as the dashboard.

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Agent status, version, uptime |
| `GET /api/info` | Machine identity (hostname, OS, CPU, GPU, RAM, network IP) |
| `GET /api/config` | Current configuration and thresholds |
| `GET /api/current` | Latest readings grouped by category |
| `GET /api/history?metric=cpu_temp_package&from=...&to=...` | Historical time-series (auto-downsampled) |
| `GET /api/history/multi?metrics=cpu_temp_package,gpu_temp&from=...&to=...` | Multiple metrics in one request |
| `GET /api/processes` | Current top processes |
| `GET /api/sse` | Server-Sent Events stream (real-time) |

All timestamps are ISO 8601 UTC. History queries are automatically downsampled based on the requested time range.

## Tech Stack

- **Agent:** Python 3.10+, FastAPI, Uvicorn, psutil, aiosqlite
- **Sensors:** LibreHardwareMonitor on Windows (optional, via pythonnet); `/sys/class/hwmon` + `/sys/class/drm` on Linux
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

[GPL-3.0](LICENSE) — Copyright (c) 2026 Static Hum Studio

---

*A Static Hum Studio Production*
