# OOGA BOOGA COMPUTER GO BRRR

### The "My Toddler Could Do This" Guide to HumWatch

> You know how your computer makes that little hum? We're going to watch it. That's it. That's the app.

---

## Table of Contents

1. [What Even IS This Thing?](#what-even-is-this-thing)
2. [What You Need (The Shopping List)](#what-you-need-the-shopping-list)
3. [Step 1: Download the Installer](#step-1-download-the-installer)
4. [Step 2: Run the Installer](#step-2-run-the-installer)
5. [Step 3: Look At The Pretty Pictures](#step-3-look-at-the-pretty-pictures)
6. [How To See Your Computer From Another Computer](#how-to-see-your-computer-from-another-computer)
7. [Managing the Service](#managing-the-service)
8. [The "What Does All This Stuff Mean" Section](#the-what-does-all-this-stuff-mean-section)
9. [It's Not Working And I'm Going To Cry](#its-not-working-and-im-going-to-cry)
10. [The Fancy Settings Nobody Asked About](#the-fancy-settings-nobody-asked-about)
11. [Themes (Make It Pretty)](#themes-make-it-pretty)

---

## What Even IS This Thing?

HumWatch is a little program that sits on your Windows PC and watches what your computer is doing. Think of it like a Fitbit, but for your computer.

It tracks:

- **CPU** - How hard your brain-chip is thinking
- **GPU** - How hard your graphics card is sweating (if you have one)
- **RAM** - How much stuff your computer is juggling at once
- **Disks** - How full your hard drives are (yes, you should delete some things)
- **Network** - How much internet juice is flowing in and out
- **Fans** - How fast the little spinny boys are going
- **Battery** - How much life your laptop has left (if it's a laptop)
- **Temperature** - Is your computer on fire? Let's find out!

It keeps 7 days of history, so you can look back and say "ah yes, Tuesday at 3am, my CPU was at 95 degrees because I had 400 Chrome tabs open."

### How It Works (The Dumbed-Down Version)

```
Your PC
  |
  +-- HumWatch wakes up every 10 seconds
  |     +-- "Hey computer, what are your temps? How's your RAM? You good?"
  |
  +-- Saves the answers in a tiny database
  |
  +-- Shows you a pretty dashboard in your browser
        +-- http://localhost:9100  (that's the magic address)
```

That's literally it. It asks your computer how it's doing, writes it down, and shows you a dashboard. A toddler could understand this. You are the toddler.

---

## What You Need (The Shopping List)

Not much, actually.

| Thing | Why | How To Get It |
|-------|-----|---------------|
| **Windows 10 or 11** | This only works on Windows. Sorry, Mac and Linux people. | You probably already have this. |
| **A web browser** | To look at the dashboard. | You're reading this, so you have one. |
| **Tailscale** *(optional)* | Only if you want to see this PC from another PC. | [tailscale.com](https://tailscale.com/) - it's free for personal use. |

That's it. No Python to install. No packages to wrangle. The installer handles all of that for you.

---

## Step 1: Download the Installer

1. Go to the [HumWatch releases page](https://github.com/StaticHumStudio/HumWatch/releases)
2. Under the latest release, find **`HumWatch-Setup-vX.X.X.exe`** and click it to download
3. Your browser might warn you that it's from an "unknown publisher" -- this is normal for self-signed software. Click **Keep** (or **Keep anyway** if it asks twice)

That's it for Step 1. You have a `.exe`. That's the whole thing.

---

## Step 2: Run the Installer

1. **Double-click** `HumWatch-Setup-vX.X.X.exe`
2. Windows will ask "Do you want to allow this app to make changes to your device?" -- click **Yes**
   - (It needs admin access to install a Windows service. It's not installing a virus. Probably.)
3. Follow the installer -- click Next a couple of times, choose where to install (the default `C:\HumWatch` is fine), click Install
4. The installer will:
   - Install HumWatch to `C:\HumWatch`
   - Install Python 3.12 inside that folder (completely self-contained -- it won't touch your system Python if you have one)
   - Install all required Python packages
   - Set up LibreHardwareMonitor (the thing that reads your temperatures and fan speeds)
   - Register HumWatch as a Windows service that starts automatically on boot
   - Start the service right now, immediately
   - Add a firewall rule so other machines on your network can reach it
5. Click **Finish**

HumWatch is now running in the background. You don't need to do anything else -- it will start automatically every time Windows boots.

---

## Step 3: Look At The Pretty Pictures

1. Open your web browser (Chrome, Firefox, Edge, whatever -- we don't judge)
2. Type this in the address bar:
   ```
   http://localhost:9100
   ```
3. Press Enter
4. Behold. Your computer's vital signs. In real time. Updating every 10 seconds.

### What You'll See

The dashboard has a sidebar on the left (or a bottom bar on your phone) with these pages:

| Page | What It Shows |
|------|--------------|
| **Overview** | The big picture -- CPU load, GPU load, RAM usage, temps, battery. Like a health check-up summary. |
| **CPU** | Everything about your processor. Load per core, temperatures, clock speeds, power draw. |
| **GPU** | Your graphics card stats. Temperature, load, VRAM usage, fan speed. *Only shows up if you have a dedicated GPU.* |
| **Memory** | RAM and swap usage over time. Also shows which programs are hogging the most memory (looking at you, Chrome). |
| **Disk** | Read/write speeds, how full each drive is, drive temperatures. |
| **Network** | Upload and download speeds, total data transferred. |
| **Battery** | Charge level, whether it's plugged in, charge rate, battery health. *Only shows up on laptops.* |
| **Processes** | The top 10 programs eating your resources, updated live. |
| **Machines** | See other computers running HumWatch (the multi-machine view). |
| **Settings** | Themes, alert thresholds, and other tweaks. |

### The Little Green Dot

In the sidebar, you'll see a connection indicator:

- **Green "Live"** -- Everything's connected and updating in real time
- **Amber "Reconnecting..."** -- It lost connection and is trying to get it back (just wait)
- **Gray "Disconnected"** -- Something's wrong. Is the service still running? See [Managing the Service](#managing-the-service).

---

## How To See Your Computer From Another Computer

This is where it gets cool. You can check on your desktop from your laptop, your laptop from your phone, your work PC from your couch -- as long as they're all on the same Tailscale network.

### What Is Tailscale? (30-Second Explanation)

Tailscale connects your devices into a private network. It's like they're all plugged into the same router, even if one is at home and one is at work. It's free for personal use and takes about 2 minutes to set up.

### Setup (One Time Per Computer)

1. Go to [tailscale.com](https://tailscale.com/) and create an account
2. Download and install Tailscale on **every computer** you want to connect
3. Sign in on each one
4. That's it. They can now see each other.

### Install HumWatch On Each PC You Want To Monitor

Every computer you want to watch needs its own copy of HumWatch running. Just run the installer on each PC -- same two steps as above.

### View Machine A From Machine B

1. On **Machine A** (the one being monitored), find its Tailscale IP:
   - Click the Tailscale icon in your system tray (bottom-right of your screen)
   - It'll show an IP address like `100.64.x.x` -- that's the one
2. On **Machine B** (the one you're sitting at), open your browser and go to:
   ```
   http://100.64.x.x:9100
   ```
   (Replace `100.64.x.x` with Machine A's actual Tailscale IP)
3. You're now looking at Machine A's dashboard from Machine B.

### The Multi-Machine Dashboard

Don't want to juggle a bunch of browser tabs? Use the Machines page:

1. Open your local HumWatch dashboard (`http://localhost:9100`)
2. Click **"Machines"** in the sidebar
3. Add the Tailscale IPs of your other computers
4. Now you can see all your machines in one view with status cards showing if they're online, their CPU/RAM usage, and more
5. Click any machine card to open its full dashboard

The IPs are saved in your browser, so you only have to enter them once.

### Automatic Discovery

If all your machines are on Tailscale and running HumWatch on port 9100, the app will try to automatically find them. Check the **Machines** page -- they might already be listed.

---

## Managing the Service

HumWatch runs as a Windows service in the background. You generally never need to touch it -- it starts on boot and stays running. But if you need to manage it:

Open **PowerShell as Administrator** (search "PowerShell" in the Start menu, right-click, "Run as administrator"), then use these commands:

| What You Want | Command |
|---------------|---------|
| Check if it's running | `nssm status HumWatch` |
| Stop it | `nssm stop HumWatch` |
| Start it | `nssm start HumWatch` |
| Restart it | `nssm restart HumWatch` |

NSSM lives at `C:\HumWatch\tools\nssm.exe`. If it's not in your PATH, use the full path: `C:\HumWatch\tools\nssm.exe status HumWatch`.

### Uninstalling

Use **Windows Settings > Apps** (or the classic **Control Panel > Programs and Features**) and uninstall "HumWatch" like any other application. The uninstaller will stop and remove the service cleanly before deleting the files.

---

## The "What Does All This Stuff Mean" Section

Here's a cheat sheet for the metrics. Clip and save.

### CPU

| Metric | What It Means | When To Worry |
|--------|--------------|---------------|
| **Load** | How busy your CPU is (0-100%) | Sustained 90%+ means something's hogging it |
| **Temperature** | How hot the chip is | 85C+ = warm. 95C+ = that's bad. |
| **Clock Speed** | How fast it's running (in GHz) | If it drops way below normal, it might be thermal throttling |
| **Power** | How many watts it's using | Just informational, don't stress about it |

### GPU

| Metric | What It Means | When To Worry |
|--------|--------------|---------------|
| **Load** | How busy your graphics card is | 99% while gaming = normal. 99% while idle = not normal. |
| **Temperature** | How hot the GPU is | 80C+ = warm. 90C+ = yikes. |
| **VRAM** | Video memory usage | If it maxes out, games/apps will stutter |
| **Fan Speed** | How fast the GPU fan is spinning | Loud fan = hot GPU = maybe clean the dust? |

### Memory (RAM)

| Metric | What It Means | When To Worry |
|--------|--------------|---------------|
| **Usage %** | How much RAM is in use | 85%+ means you might need to close some stuff (or buy more RAM) |
| **Swap** | "Overflow" memory on your hard drive | If swap is high, your PC is using the hard drive as fake RAM, which is slow |

### Disk

| Metric | What It Means | When To Worry |
|--------|--------------|---------------|
| **Read/Write Rate** | How fast data is moving to/from the drive | High sustained rates might mean something's copying a lot of data |
| **Usage** | How full the drive is | 85%+ = time to clean up. 95%+ = you're living dangerously. |
| **Temperature** | How hot the drive is | SSDs: 70C+ is warm. HDDs: 50C+ is warm. |

### Network

| Metric | What It Means | When To Worry |
|--------|--------------|---------------|
| **Upload/Download Rate** | How much data is flowing right now | Unexpectedly high = something might be uploading/downloading in the background |
| **Total Transferred** | Cumulative data since last boot | Useful for monitoring data caps |

### Battery

| Metric | What It Means | When To Worry |
|--------|--------------|---------------|
| **Charge %** | How much juice is left | Below 20% = plug it in |
| **Wear Level** | How degraded the battery is | Above 20% wear = battery is getting old |
| **Cycle Count** | How many charge cycles it's been through | 500+ cycles = battery is aging |

---

## It's Not Working And I'm Going To Cry

Don't cry. We'll fix it.

### "I can't open localhost:9100"

- Is the service running? Open PowerShell and run `nssm status HumWatch`. If it says anything other than `SERVICE_RUNNING`, run `nssm start HumWatch`.
- Is something else using port 9100? Edit `C:\HumWatch\config.json` and change the port:
  ```json
  { "port": 9200 }
  ```
  Restart the service (`nssm restart HumWatch`) and go to `http://localhost:9200` instead.

### "I don't see temperatures or fan speeds"

The installer sets up LibreHardwareMonitor automatically, so this shouldn't happen -- but if it does:
- Some hardware isn't supported by LibreHardwareMonitor (certain laptops, some integrated graphics)
- Try restarting the service: `nssm restart HumWatch`
- Check the service log at `C:\HumWatch\logs\humwatch.log` for any LHM errors

### "The GPU section doesn't show up"

You either don't have a dedicated GPU (integrated graphics don't count for most sensors), or LibreHardwareMonitor can't detect it. This is normal for some laptops.

### "The Battery section doesn't show up"

You're on a desktop. Desktops don't have batteries. This is working as intended.

### "I can't see Machine A from Machine B"

Checklist:
1. Is Tailscale running on **both** machines?
2. Is HumWatch running on Machine A? (`nssm status HumWatch` on Machine A)
3. Can you ping Machine A's Tailscale IP from Machine B? (Open PowerShell, type `ping 100.64.x.x`)
4. Is Windows Firewall blocking port 9100? The installer adds a firewall rule, but if something removed it:
   ```powershell
   netsh advfirewall firewall add rule name="HumWatch" dir=in action=allow protocol=TCP localport=9100
   ```

### "The dashboard says 'Disconnected'"

The browser lost its real-time connection. This usually fixes itself in a few seconds. If it doesn't:
- Is the service still running? `nssm status HumWatch`
- Hard-refresh the browser: `Ctrl + Shift + R`

### "Everything is slow / the database is huge"

The database keeps 7 days of data. Reduce retention in `C:\HumWatch\config.json`:
```json
{ "retention_days": 3 }
```
Then restart the service: `nssm restart HumWatch`

---

## The Fancy Settings Nobody Asked About

HumWatch has a config file at `C:\HumWatch\config.json`. You don't need to touch it -- the defaults are fine. But if you want to tinker:

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

| Setting | What It Does | Default |
|---------|-------------|---------|
| `port` | Which port the dashboard runs on | `9100` |
| `collection_interval_seconds` | How often it checks your hardware (in seconds) | `10` |
| `retention_days` | How many days of history to keep | `7` |
| `db_path` | Where to put the database file | `./humwatch.db` |
| `theme_override` | Force a specific theme for all viewers | `null` (user picks) |
| `alert_thresholds` | When to show warning/critical colors | See above |
| `process_snapshot_count` | How many top processes to track | `10` |
| `enable_categories` | Which sensor groups to collect | All of them |

You can also override some settings with environment variables:

| Variable | Overrides |
|----------|-----------|
| `HUMWATCH_PORT` | `port` |
| `HUMWATCH_DB` | `db_path` |
| `HUMWATCH_INTERVAL` | `collection_interval_seconds` |

After editing `config.json`, restart the service: `nssm restart HumWatch`

---

## Themes (Make It Pretty)

HumWatch comes with three themes:

| Theme | Vibe |
|-------|------|
| **Default** | Dark void with gold and teal accents. Moody. |
| **Light** | Clean and bright. For people who don't fear the sun. |
| **Terminal** | Green-on-black with scanlines. Hacker cosplay. |

Switch themes from the **Settings** page in the dashboard. Your choice is saved per-browser.

### Making Your Own Theme

1. Go to `C:\HumWatch\static\css\themes\`
2. Copy `theme-light.css` and rename it to something cool like `theme-bubblegum.css`
3. Change the color values (they're all CSS variables starting with `--hw-`)
4. Register it in `C:\HumWatch\static\js\utils\theme.js`
5. Restart the service (`nssm restart HumWatch`), refresh the dashboard, and select it in Settings

---

## The End

You did it. You installed a thing. Your computer is being watched. In a good way.

If something is still broken, re-read this guide. Slowly. Out loud. With a juice box.

---

*A Static Hum Studio Production -- "What hums beneath the shell."*

*Licensed under [GPL-3.0](LICENSE)*
