# HumWatch — Project Specification

## A Static Hum Studio Production

**Repo:** `StaticHumStudio/HumWatch`
**License:** MIT
**Tagline:** *"What hums beneath the shell."*

---

## 1. Project Overview

HumWatch is a self-hosted, local-first hardware monitoring system for Windows PCs accessible over your local or overlay network. Each monitored PC runs a lightweight Python agent that collects full hardware telemetry — thermal, performance, battery, and system metrics — stores 7 days of history in a local SQLite database, and serves both a REST API and a web dashboard on a single port.

There is no central server. Each PC is its own self-contained monitoring station. The dashboard includes a multi-machine view with automatic peer discovery across LAN, Tailscale, ZeroTier, WireGuard, and other overlay networks.

### Design Philosophy

- **Local-first:** All data stays on the machine that generated it. No cloud, no external dependencies.
- **Zero-config discovery:** If a machine has a battery, battery metrics appear automatically. If it has a discrete GPU, GPU metrics appear. No configuration files to edit.
- **Network-agnostic:** Works over LAN, Tailscale, ZeroTier, WireGuard, or any overlay network. Binds to `0.0.0.0` by default so it's reachable from any interface.
- **Themeable:** Ships with Static Hum Studio's signature aesthetic but uses a clean CSS custom property system so anyone can re-theme it in minutes.

---

## 2. Architecture

```
┌─────────────────────────────────────────────┐
│  Each Windows PC                            │
│                                             │
│  ┌─────────────┐    ┌──────────────────┐    │
│  │  Collector   │───▶│  SQLite (WAL)    │    │
│  │  (10s loop)  │    │  7-day rolling   │    │
│  └─────────────┘    └──────────────────┘    │
│         │                    ▲               │
│         ▼                    │               │
│  ┌─────────────────────────────────────┐    │
│  │  FastAPI Server (:9100)             │    │
│  │  ├── /api/* — REST endpoints        │    │
│  │  ├── /sse — real-time stream        │    │
│  │  └── /* — static dashboard SPA      │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
         ▲
         │  HTTP over LAN / overlay network
         ▼
┌─────────────────────────────────────────────┐
│  Browser (any device on network)            │
│  ├── Single-machine view                    │
│  └── Multi-machine dashboard                │
└─────────────────────────────────────────────┘
```

### Port

Default: `9100`. Configurable via `HUMWATCH_PORT` environment variable or `config.json`.

---

## 3. Tech Stack

### Agent / Backend

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Runtime | Python 3.11+ | Agent runtime |
| Web Framework | FastAPI + Uvicorn | API server, SSE, static file serving |
| System Metrics | psutil | CPU, memory, disk, network, battery, per-process stats |
| Hardware Sensors | LibreHardwareMonitorLib via pythonnet (clr) | CPU/GPU temps, fan speeds, voltages, clock speeds |
| Database | SQLite (WAL mode) | 7-day rolling time-series storage |
| Scheduling | asyncio background task | 10-second collection loop |
| Windows Service | nssm (Non-Sucking Service Manager) | Run agent as auto-start Windows service |

### Dashboard / Frontend

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Framework | Vanilla JS (single-page app) | No build step, served as static files |
| Charts | Chart.js 4.x (via CDN) | Historical time-series graphs |
| Real-time | Server-Sent Events (EventSource API) | Live gauge updates without polling |
| Theming | CSS custom properties | Full re-theming via single file override |
| Layout | CSS Grid + Flexbox | Responsive, adapts to mobile/tablet/desktop |
| Icons | Lucide Icons (via CDN) | Lightweight, consistent iconography |

---

## 4. Sensor Data Model

### 4.1 Metric Categories

The collector gathers metrics in these categories. Each category auto-detects availability — if the hardware isn't present, the category is silently skipped.

#### CPU
- `cpu_temp_package` — Package/overall CPU temperature (°C)
- `cpu_temp_core_N` — Per-core temperature (°C), one per logical core
- `cpu_load_total` — Total CPU utilization (%)
- `cpu_load_core_N` — Per-core utilization (%)
- `cpu_clock_core_N` — Per-core clock speed (MHz)
- `cpu_power_package` — Package power draw (W), if available
- `cpu_voltage` — Core voltage (V), if available

#### GPU (discrete, if present)
- `gpu_temp` — GPU core temperature (°C)
- `gpu_load` — GPU utilization (%)
- `gpu_clock_core` — Core clock speed (MHz)
- `gpu_clock_memory` — Memory clock speed (MHz)
- `gpu_vram_used` — VRAM used (MB)
- `gpu_vram_total` — VRAM total (MB)
- `gpu_power` — GPU power draw (W), if available
- `gpu_fan_speed` — Fan speed (RPM or %), if available

#### Memory
- `mem_used` — Used RAM (MB)
- `mem_total` — Total RAM (MB)
- `mem_percent` — RAM utilization (%)
- `mem_swap_used` — Used swap/page file (MB)
- `mem_swap_total` — Total swap/page file (MB)

#### Disk
- `disk_read_rate` — Read throughput (MB/s), per physical disk
- `disk_write_rate` — Write throughput (MB/s), per physical disk
- `disk_usage_DRIVE` — Usage % per mounted volume (e.g., `disk_usage_C`)
- `disk_temp_N` — Drive temperature (°C), if available via SMART/LHM

#### Network
- `net_sent_rate` — Upload throughput (MB/s)
- `net_recv_rate` — Download throughput (MB/s)
- `net_bytes_sent` — Total bytes sent since boot
- `net_bytes_recv` — Total bytes received since boot

#### Fans
- `fan_N_speed` — Individual fan RPM values from LibreHardwareMonitor
- `fan_N_name` — Human-readable fan label

#### Battery (laptops only, auto-detected)
- `battery_percent` — Charge level (%)
- `battery_plugged` — AC adapter connected (boolean → stored as 1/0)
- `battery_time_remaining` — Estimated seconds remaining (null if charging)
- `battery_voltage` — Current voltage (V), if available via LHM
- `battery_charge_rate` — Charge/discharge rate (W), if available
- `battery_designed_capacity` — Designed full charge capacity (mAh), if available
- `battery_current_capacity` — Current full charge capacity (mAh), if available
- `battery_wear_level` — Derived: `current_capacity / designed_capacity * 100` (%)
- `battery_temp` — Battery temperature (°C), if available
- `battery_cycle_count` — Charge cycles, if reported by hardware

#### System
- `uptime_seconds` — System uptime
- `boot_time` — Last boot timestamp (ISO 8601)

### 4.2 SQLite Schema

```sql
-- Machine identity (one row, updated on each startup)
CREATE TABLE machine_info (
    id INTEGER PRIMARY KEY DEFAULT 1,
    hostname TEXT NOT NULL,
    os_version TEXT,
    cpu_name TEXT,
    gpu_name TEXT,
    total_ram_mb INTEGER,
    network_ip TEXT,
    agent_version TEXT,
    last_boot TEXT,
    updated_at TEXT NOT NULL
);

-- Time-series metric storage
CREATE TABLE metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,          -- ISO 8601, UTC
    category TEXT NOT NULL,           -- 'cpu', 'gpu', 'memory', 'disk', 'network', 'fan', 'battery', 'system'
    metric_name TEXT NOT NULL,        -- e.g., 'cpu_temp_core_0'
    value REAL NOT NULL,
    unit TEXT                         -- '°C', '%', 'MB', 'MHz', 'RPM', 'W', 'V', 'MB/s', 's', 'mAh', 'bool'
);

-- Indices for query performance
CREATE INDEX idx_metrics_timestamp ON metrics(timestamp);
CREATE INDEX idx_metrics_category_timestamp ON metrics(category, timestamp);
CREATE INDEX idx_metrics_name_timestamp ON metrics(metric_name, timestamp);

-- Snapshot of top processes at each collection interval
CREATE TABLE process_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,          -- ISO 8601, UTC
    pid INTEGER NOT NULL,
    name TEXT NOT NULL,
    cpu_percent REAL,
    memory_mb REAL
);

CREATE INDEX idx_process_timestamp ON process_snapshots(timestamp);
```

### 4.3 Data Retention

- **Rolling window:** 7 days.
- **Cleanup job:** Runs once per hour via asyncio task. Deletes all rows from `metrics` and `process_snapshots` where `timestamp` is older than 7 days.
- **Approximate storage:** At 10-second intervals with ~40 metrics per tick, expect ~2.4M rows/week. SQLite in WAL mode handles this comfortably. Estimated database size: 200–400 MB depending on hardware sensor count.
- **Process snapshots:** Store top 10 processes by CPU usage at each interval.

---

## 5. API Specification

All endpoints served from the same FastAPI instance on port 9100.

### 5.1 Machine Info

```
GET /api/info
```

Returns `machine_info` row: hostname, OS, CPU name, GPU name, RAM, network IP, agent version, last boot, uptime.

### 5.2 Current Readings

```
GET /api/current
```

Returns the most recent reading for every metric, grouped by category. This is what the live dashboard uses on initial load before SSE takes over.

Response shape:
```json
{
    "timestamp": "2026-03-01T15:30:00Z",
    "categories": {
        "cpu": {
            "cpu_temp_package": {"value": 62.0, "unit": "°C"},
            "cpu_load_total": {"value": 34.2, "unit": "%"},
            ...
        },
        "gpu": { ... },
        "memory": { ... },
        "disk": { ... },
        "network": { ... },
        "fan": { ... },
        "battery": { ... },
        "system": { ... }
    }
}
```

### 5.3 Historical Data

```
GET /api/history?metric={metric_name}&from={iso_timestamp}&to={iso_timestamp}&resolution={seconds}
```

Parameters:
- `metric` (required): Metric name, e.g., `cpu_temp_package`
- `from` (optional): Start of range. Default: 1 hour ago.
- `to` (optional): End of range. Default: now.
- `resolution` (optional): Bucket size in seconds for downsampling. Default: auto-calculated based on range (10s for <1h, 60s for <6h, 300s for <24h, 900s for >24h). Data is averaged within each bucket.

Response: Array of `{timestamp, value}` objects.

```
GET /api/history/multi?metrics={comma_separated}&from={iso}&to={iso}&resolution={seconds}
```

Same as above but accepts multiple metric names. Returns object keyed by metric name.

### 5.4 Process Snapshot

```
GET /api/processes
```

Returns the most recent process snapshot (top 10 by CPU).

```
GET /api/processes/history?from={iso}&to={iso}
```

Returns process snapshots within the time range.

### 5.5 Real-Time Stream

```
GET /api/sse
```

Server-Sent Events stream. Emits a `data` event every 10 seconds with the same shape as `/api/current`. The client uses `EventSource` to subscribe.

Event format:
```
event: metrics
data: {"timestamp": "...", "categories": { ... }}

event: processes
data: {"timestamp": "...", "processes": [ ... ]}
```

### 5.6 Health Check

```
GET /api/health
```

Returns `{"status": "ok", "version": "x.y.z", "uptime_seconds": N}`. Useful for multi-machine dashboard to check if a remote instance is reachable.

### 5.7 Configuration

```
GET /api/config
```

Returns current configuration (collection interval, retention days, port, enabled categories).

---

## 6. Dashboard Specification

The dashboard is a vanilla JS single-page application served as static files by FastAPI. No build step. All dependencies loaded via CDN with integrity hashes.

### 6.1 Pages / Views

#### Home / Overview

The default landing page. Shows:

- **Machine identity card:** Hostname, OS, CPU, GPU, RAM, uptime, network IP, agent version.
- **Live gauges:** Circular/arc gauges for CPU temp, GPU temp, CPU load, GPU load, RAM usage. These update in real-time via SSE.
- **Battery widget:** (Only if battery detected.) Shows charge %, plugged status, estimated time remaining, wear level as a health bar. Subtle animation when charging.
- **Alert indicators:** Visual warning if any temp exceeds configurable thresholds (default: CPU > 85°C = warning amber, > 95°C = critical red; GPU > 80°C = warning, > 90°C = critical).
- **Quick sparklines:** Tiny inline charts showing the last 5 minutes for key metrics.

#### CPU Detail

- Per-core temperature chart (line chart, all cores overlaid, color-coded)
- Per-core load chart
- Per-core clock speed chart
- Package power draw (if available)
- Voltage reading
- Time range selector: 5m, 15m, 1h, 6h, 24h, 3d, 7d

#### GPU Detail

- Temperature history chart
- Load history chart
- VRAM usage (used/total) with history
- Core and memory clock charts
- Power draw chart (if available)
- Fan speed chart (if available)
- Time range selector

#### Memory Detail

- RAM usage over time (area chart, used vs. total)
- Swap usage over time
- Current top processes by memory (table, live-updating)

#### Disk Detail

- Read/write throughput charts per physical disk
- Volume usage bars (C:, D:, etc.)
- Drive temperatures (if available)

#### Network Detail

- Upload/download throughput chart
- Cumulative transfer since boot

#### Battery Detail (only visible if battery present)

- Charge % over time (area chart)
- Plugged/unplugged status timeline (binary bar along the bottom of the chart)
- Charge/discharge rate over time
- Voltage over time
- Battery health: designed vs current capacity, wear level
- Temperature over time (if available)
- Cycle count display

#### Processes

- Table of top processes at current moment (live via SSE)
- Ability to click a timestamp on any chart to see what processes were running at that time

#### Multi-Machine View

- Peers are auto-discovered on the network (Tailscale, ZeroTier, LAN subnet scan). Users can also manually enter IPs or hostnames. Manual entries are saved in `localStorage`.
- For each machine: shows a compact summary card (hostname, CPU temp, GPU temp, CPU load, RAM %, battery % if applicable, online/offline status).
- Clicking a card opens that machine's full dashboard in a new tab (navigates to its network IP).
- Machines that don't respond to `/api/health` within 3 seconds show as "offline" with a muted card.
- Auto-refreshes status every 30 seconds.

### 6.2 Navigation

Sidebar navigation on desktop, bottom tab bar on mobile. Pages:

1. **Overview** (home icon)
2. **CPU** (chip icon)
3. **GPU** (monitor icon)
4. **Memory** (database icon)
5. **Disk** (hard-drive icon)
6. **Network** (wifi icon)
7. **Battery** (battery icon) — only shown if battery detected
8. **Processes** (list icon)
9. **Machines** (server icon) — multi-machine view
10. **Settings** (gear icon) — theme selector, alert thresholds, machine list management

### 6.3 Responsive Behavior

- **Desktop (>1024px):** Sidebar nav, multi-column gauge layout.
- **Tablet (768–1024px):** Collapsible sidebar, 2-column layout.
- **Mobile (<768px):** Bottom tab bar (top 5 most important pages, with "more" overflow), single-column, stacked cards.

---

## 7. Theming System

### 7.1 CSS Custom Property Architecture

All visual styling flows through CSS custom properties defined in a single `:root` block in `theme.css`. Anyone can override the entire look by replacing or overriding this file.

```css
:root {
    /* === CORE PALETTE === */
    --hw-bg-primary: #0a0a0f;           /* Main background */
    --hw-bg-secondary: #12121a;         /* Card/panel background */
    --hw-bg-tertiary: #1a1a26;          /* Nested element background */
    --hw-bg-hover: #22222e;             /* Hover state background */

    --hw-text-primary: #e8e6e1;         /* Primary text */
    --hw-text-secondary: #9a9890;       /* Secondary/muted text */
    --hw-text-tertiary: #6a6860;        /* Tertiary/disabled text */

    --hw-accent-primary: #c9a84c;       /* Gold/amber — primary accent */
    --hw-accent-primary-dim: #7a6a30;   /* Gold dimmed for backgrounds */
    --hw-accent-secondary: #4ecdc4;     /* Bioluminescent teal — secondary accent */
    --hw-accent-secondary-dim: #2a6e68; /* Teal dimmed */
    --hw-accent-glow: #5bff8f;          /* Bioluminescent green — highlights, active states */

    /* === STATUS COLORS === */
    --hw-status-ok: #4ecdc4;            /* Normal/good */
    --hw-status-warn: #f0a830;          /* Warning (amber) */
    --hw-status-critical: #e74c3c;      /* Critical/danger (red) */
    --hw-status-offline: #555555;       /* Offline/unavailable */

    /* === GAUGE COLORS === */
    --hw-gauge-cold: #4ecdc4;           /* Low temp — teal */
    --hw-gauge-warm: #c9a84c;           /* Medium temp — gold */
    --hw-gauge-hot: #e74c3c;            /* High temp — red */

    /* === CHART PALETTE === */
    --hw-chart-1: #c9a84c;
    --hw-chart-2: #4ecdc4;
    --hw-chart-3: #5bff8f;
    --hw-chart-4: #e74c3c;
    --hw-chart-5: #9b59b6;
    --hw-chart-6: #3498db;
    --hw-chart-7: #e67e22;
    --hw-chart-8: #1abc9c;

    /* === TYPOGRAPHY === */
    --hw-font-display: 'JetBrains Mono', 'Fira Code', monospace;   /* Headers, gauges, data */
    --hw-font-body: 'Inter', 'Segoe UI', system-ui, sans-serif;     /* Body text, labels */
    --hw-font-size-xs: 0.7rem;
    --hw-font-size-sm: 0.8rem;
    --hw-font-size-md: 0.95rem;
    --hw-font-size-lg: 1.2rem;
    --hw-font-size-xl: 1.6rem;
    --hw-font-size-xxl: 2.4rem;

    /* === SPACING === */
    --hw-space-xs: 4px;
    --hw-space-sm: 8px;
    --hw-space-md: 16px;
    --hw-space-lg: 24px;
    --hw-space-xl: 32px;
    --hw-space-xxl: 48px;

    /* === BORDERS & RADIUS === */
    --hw-border-color: #2a2a36;
    --hw-border-radius-sm: 4px;
    --hw-border-radius-md: 8px;
    --hw-border-radius-lg: 12px;

    /* === EFFECTS === */
    --hw-shadow-card: 0 2px 12px rgba(0, 0, 0, 0.4);
    --hw-shadow-glow: 0 0 20px rgba(201, 168, 76, 0.15);
    --hw-transition-fast: 150ms ease;
    --hw-transition-normal: 300ms ease;

    /* === BRANDING === */
    --hw-brand-name: "Static Hum Studio";
    --hw-product-name: "HumWatch";
}
```

### 7.2 Static Hum Studio Default Theme

The default theme follows the established Static Hum Studio aesthetic:

- **Void black backgrounds** with very subtle noise texture overlay (CSS `background-image` with inline SVG noise)
- **Gold/amber primary accents** (`#c9a84c`) for headings, active nav items, gauge highlights
- **Bioluminescent teal** (`#4ecdc4`) for secondary data, status-ok indicators
- **Bioluminescent green** (`#5bff8f`) for highlights, active pulses, connection indicators
- **JetBrains Mono** for all data/numeric displays — gives it that "terminal readout" feel
- **Subtle glow effects** on active elements — not overdone, just enough to feel like something ancient and luminous is tracking your hardware
- **Card-based layout** with very subtle borders, slight inner shadow, feels like stone tablets with glowing inscriptions
- A small **Static Hum Studio** wordmark in the sidebar footer, styled as `font-variant: small-caps` with a subtle gold glow

### 7.3 Re-Theming Guide

Include a `THEMING.md` in the repo:

1. Copy `static/css/theme.css` → `static/css/theme-custom.css`
2. Edit the custom properties
3. Set `"theme_override": "theme-custom.css"` in `config.json`
4. Restart HumWatch

Provide two example alternate themes in `static/css/themes/`:
- `theme-light.css` — Clean light theme (white bg, dark text, blue accents)
- `theme-terminal.css` — Classic green-on-black terminal aesthetic

---

## 8. Configuration

### 8.1 config.json

Located next to the agent executable. All fields optional with sensible defaults.

```json
{
    "port": 9100,
    "collection_interval_seconds": 10,
    "retention_days": 7,
    "db_path": "./humwatch.db",
    "theme_override": null,
    "alert_thresholds": {
        "cpu_temp_warn": 85,
        "cpu_temp_critical": 95,
        "gpu_temp_warn": 80,
        "gpu_temp_critical": 90,
        "ram_percent_warn": 85,
        "ram_percent_critical": 95,
        "disk_percent_warn": 85,
        "disk_percent_critical": 95,
        "battery_low_warn": 20,
        "battery_low_critical": 10
    },
    "process_snapshot_count": 10,
    "enable_categories": ["cpu", "gpu", "memory", "disk", "network", "fan", "battery", "system"]
}
```

### 8.2 Environment Variable Overrides

- `HUMWATCH_PORT` → overrides `config.json` port
- `HUMWATCH_DB` → overrides `config.json` db_path
- `HUMWATCH_INTERVAL` → overrides collection interval

---

## 9. Project Structure

```
HumWatch/
├── README.md
├── THEMING.md
├── LICENSE                          # MIT
├── requirements.txt
├── config.json                      # Default configuration
├── install-service.ps1              # PowerShell script to install via nssm
├── uninstall-service.ps1            # PowerShell script to remove service
│
├── agent/
│   ├── __init__.py
│   ├── main.py                      # Entry point: FastAPI app, startup, shutdown
│   ├── config.py                    # Configuration loading (config.json + env vars)
│   ├── database.py                  # SQLite connection, schema init, WAL mode setup
│   ├── collector.py                 # Main collection loop (asyncio background task)
│   ├── sensors/
│   │   ├── __init__.py
│   │   ├── base.py                  # Abstract sensor interface
│   │   ├── cpu.py                   # CPU metrics (psutil + LHM)
│   │   ├── gpu.py                   # GPU metrics (LHM)
│   │   ├── memory.py                # RAM/swap metrics (psutil)
│   │   ├── disk.py                  # Disk I/O, usage, temps (psutil + LHM)
│   │   ├── network.py               # Network throughput (psutil)
│   │   ├── fan.py                   # Fan speeds (LHM)
│   │   ├── battery.py               # Battery metrics (psutil + LHM)
│   │   └── system.py                # Uptime, boot time (psutil)
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── info.py                  # /api/info
│   │   ├── current.py               # /api/current
│   │   ├── history.py               # /api/history, /api/history/multi
│   │   ├── processes.py             # /api/processes
│   │   ├── sse.py                   # /api/sse (Server-Sent Events)
│   │   ├── health.py                # /api/health
│   │   └── config_route.py          # /api/config
│   └── services/
│       ├── __init__.py
│       ├── retention.py             # Hourly cleanup job
│       ├── machine_info.py          # Populate/update machine_info table
│       └── downsampler.py           # Query-time downsampling logic for history API
│
├── static/
│   ├── index.html                   # SPA shell
│   ├── css/
│   │   ├── theme.css                # Default Static Hum theme (all custom properties)
│   │   ├── layout.css               # Grid, responsive rules
│   │   ├── components.css           # Cards, gauges, tables, nav
│   │   └── themes/
│   │       ├── theme-light.css      # Light alternate theme
│   │       └── theme-terminal.css   # Green terminal alternate theme
│   ├── js/
│   │   ├── app.js                   # SPA router, page initialization
│   │   ├── api.js                   # API client (fetch wrapper)
│   │   ├── sse.js                   # SSE connection manager with auto-reconnect
│   │   ├── charts.js                # Chart.js configuration factory
│   │   ├── gauges.js                # Circular gauge rendering (canvas-based)
│   │   ├── pages/
│   │   │   ├── overview.js          # Home/overview page logic
│   │   │   ├── cpu.js
│   │   │   ├── gpu.js
│   │   │   ├── memory.js
│   │   │   ├── disk.js
│   │   │   ├── network.js
│   │   │   ├── battery.js
│   │   │   ├── processes.js
│   │   │   ├── machines.js          # Multi-machine view
│   │   │   └── settings.js          # Settings page
│   │   └── utils/
│   │       ├── format.js            # Number formatting, unit display
│   │       ├── time.js              # Time range helpers, relative time
│   │       └── theme.js             # Theme switching logic
│   └── assets/
│       ├── favicon.svg              # HumWatch icon
│       └── logo.svg                 # Static Hum Studio wordmark (small, for footer)
│
├── lib/
│   └── LibreHardwareMonitorLib.dll  # Bundled LHM library
│   └── HidSharp.dll                 # LHM dependency
│
└── scripts/
    ├── install-service.ps1
    ├── uninstall-service.ps1
    └── download-lhm.ps1            # Helper to download LibreHardwareMonitorLib
```

---

## 10. Installation & Deployment

### 10.1 Prerequisites

- Windows 10/11
- Python 3.11+
- Admin privileges (required for hardware sensor access)
- Network connectivity (LAN, Tailscale, ZeroTier, WireGuard, etc.)

### 10.2 Quick Start

```powershell
# Clone the repo
git clone https://github.com/StaticHumStudio/HumWatch.git
cd HumWatch

# Install Python dependencies
pip install -r requirements.txt

# Download LibreHardwareMonitorLib (if not bundled)
python scripts/download-lhm.py

# Run (must be elevated / admin)
python -m agent.main
```

Access at `http://localhost:9100` or `http://<network-ip>:9100`.

### 10.3 Install as Windows Service

```powershell
# Run as Administrator
.\scripts\install-service.ps1

# This uses nssm to:
# 1. Create a service named "HumWatch"
# 2. Set it to auto-start
# 3. Run with SYSTEM account (has admin access for sensors)
# 4. Configure stdout/stderr logging to ./logs/
```

### 10.4 requirements.txt

```
fastapi>=0.110.0
uvicorn[standard]>=0.27.0
psutil>=5.9.0
pythonnet>=3.0.3
aiosqlite>=0.19.0
pydantic>=2.0.0
```

---

## 11. Key Implementation Notes

### 11.1 LibreHardwareMonitor Integration

```python
# Pseudocode for LHM initialization
import clr
clr.AddReference('./lib/LibreHardwareMonitorLib')
from LibreHardwareMonitor.Hardware import Computer, HardwareType, SensorType

computer = Computer()
computer.IsCpuEnabled = True
computer.IsGpuEnabled = True
computer.IsMemoryEnabled = True
computer.IsStorageEnabled = True
computer.IsBatteryEnabled = True
computer.IsControllerEnabled = True
computer.Open()

# Each collection tick:
for hardware in computer.Hardware:
    hardware.Update()
    for sensor in hardware.Sensors:
        # sensor.SensorType: Temperature, Load, Clock, Voltage, Power, Fan, etc.
        # sensor.Value: float or None
        # sensor.Name: human-readable label
        pass
```

**Important:** LHM's `Computer` object must be created and used in the same thread. Use a dedicated thread for sensor collection, push results to the async event loop via `asyncio.run_coroutine_threadsafe` or a thread-safe queue.

### 11.2 Rate Calculation for Disk & Network

`psutil` gives cumulative byte counters. To get rates:

```python
# Store previous reading
# rate = (current_bytes - previous_bytes) / interval_seconds
# Convert to MB/s
```

Compute this in the collector, store the computed rate (not raw counters).

### 11.3 SSE Reconnection

The frontend SSE client should:
- Use `EventSource` with automatic reconnection
- Show a "Reconnecting..." indicator if the connection drops
- On reconnect, fetch `/api/current` once to fill any gap, then resume SSE

### 11.4 Downsampling Strategy

For historical queries spanning large time ranges, the API automatically downsamples:

| Range | Resolution | Method |
|-------|-----------|--------|
| < 1 hour | 10s (raw) | No downsampling |
| 1–6 hours | 60s | AVG per bucket |
| 6–24 hours | 300s (5min) | AVG per bucket |
| 1–7 days | 900s (15min) | AVG per bucket |

The `resolution` query param can override this for custom requests.

### 11.5 Multi-Machine CORS

Since each machine serves its own API, the multi-machine view on Machine A fetching data from Machine B is a cross-origin request. Configure FastAPI CORS middleware to allow all origins from private/overlay network IP ranges:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Safe because only accessible on local/overlay network
    allow_methods=["GET"],
    allow_headers=["*"],
)
```

This is safe because HumWatch is only accessible within the local or overlay network — there's no public exposure.

---

## 12. README.md Content Guide

The README should include:

1. **Hero section** with logo and tagline: *"What hums beneath the shell."*
2. **Screenshot/GIF** of the dashboard in action
3. **Feature list** — what it monitors
4. **Quick start** — 4 commands to get running
5. **Installation as service** instructions
6. **Multi-machine setup** guide
7. **Theming** — link to THEMING.md
8. **Configuration** reference
9. **API documentation** — brief overview with link to full spec
10. **Tech stack** summary
11. **Contributing** section
12. **License** (MIT)
13. **Footer:** *"A Static Hum Studio Production"*

---

## 13. Branding Footer

Every page of the dashboard includes a subtle footer in the sidebar (desktop) or at the bottom of the settings page (mobile):

```
─── A Static Hum Studio Production ───
```

Styled in small-caps, `--hw-text-tertiary` color, with a very subtle gold glow on hover that links to `https://statichum.studio` (or whatever the current URL is).

---

## 14. Future Considerations (Not in V1)

These are explicitly **out of scope** for the initial build but noted for potential future versions:

- Alert notifications (push, email, webhook)
- Linux agent support
- Historical data export (CSV, JSON)
- Custom dashboard layouts / widget arrangement
- Docker container deployment option
- Prometheus/Grafana metric export endpoint
- Per-process historical tracking (beyond top 10 snapshots)
- Dark/light mode auto-detection via `prefers-color-scheme`

---

*End of specification. This document should be sufficient for Claude Code to build the complete HumWatch application.*
