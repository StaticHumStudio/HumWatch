# OOGA BOOGA COMPUTER GO BRRR

### The "My Toddler Could Do This" Guide to HumWatch

> You know how your computer makes that little hum? We're going to watch it. That's it. That's the app.

---

## Table of Contents

1. [What Even IS This Thing?](#what-even-is-this-thing)
2. [What You Need (The Shopping List)](#what-you-need-the-shopping-list)
3. [Step 1: Get The Code](#step-1-get-the-code)
4. [Step 2: Run The Magic Setup Script](#step-2-run-the-magic-setup-script)
5. [Step 3: Start It Up](#step-3-start-it-up)
6. [Step 4: Look At The Pretty Pictures](#step-4-look-at-the-pretty-pictures)
7. [How To See Your Computer From Another Computer](#how-to-see-your-computer-from-another-computer)
8. [Make It Run Forever (Like A Toddler)](#make-it-run-forever-like-a-toddler)
9. [The "What Does All This Stuff Mean" Section](#the-what-does-all-this-stuff-mean-section)
10. [It's Not Working And I'm Going To Cry](#its-not-working-and-im-going-to-cry)
11. [The Fancy Settings Nobody Asked About](#the-fancy-settings-nobody-asked-about)
12. [Themes (Make It Pretty)](#themes-make-it-pretty)

---

## What Even IS This Thing?

HumWatch is a little program that sits on your Windows PC and watches what your computer is doing. Think of it like a Fitbit, but for your computer.

It tracks:

- **CPU** — How hard your brain-chip is thinking
- **GPU** — How hard your graphics card is sweating (if you have one)
- **RAM** — How much stuff your computer is juggling at once
- **Disks** — How full your hard drives are (yes, you should delete some things)
- **Network** — How much internet juice is flowing in and out
- **Fans** — How fast the little spinny boys are going
- **Battery** — How much life your laptop has left (if it's a laptop)
- **Temperature** — Is your computer on fire? Let's find out!

It keeps 7 days of history, so you can look back and say "ah yes, Tuesday at 3am, my CPU was at 95 degrees because I had 400 Chrome tabs open."

### How It Works (The Dumbed-Down Version)

```
Your PC
  │
  ├── HumWatch wakes up every 10 seconds
  │     └── "Hey computer, what are your temps? How's your RAM? You good?"
  │
  ├── Saves the answers in a tiny database
  │
  └── Shows you a pretty dashboard in your browser
        └── http://localhost:9100  (that's the magic address)
```

That's literally it. It asks your computer how it's doing, writes it down, and shows you a dashboard. A toddler could understand this. You are the toddler.

---

## What You Need (The Shopping List)

Before we start, make sure you have these things. If you don't have them, we'll tell you how to get them.

| Thing | Why | How To Get It |
|-------|-----|---------------|
| **Windows 10 or 11** | This only works on Windows. Sorry, Mac and Linux people. | You probably already have this. |
| **Python 3.10 or newer** | The programming language HumWatch is written in. | Go to [python.org](https://www.python.org/downloads/), download, install. **CHECK THE BOX THAT SAYS "Add Python to PATH"**. Seriously. Check it. |
| **A web browser** | To look at the dashboard. | You're reading this, so you have one. |
| **Tailscale** *(optional)* | Only if you want to see this PC from another PC. | [tailscale.com](https://tailscale.com/) — it's free for personal use. |

### How To Check If You Have Python

1. Press `Win + R` on your keyboard (the Windows key and the R key at the same time)
2. Type `cmd` and press Enter
3. A black window appears. Type this and press Enter:
   ```
   python --version
   ```
4. If it says something like `Python 3.11.5` — you're golden.
5. If it says `'python' is not recognized` — you need to install Python. Go back to the table above.

---

## Step 1: Get The Code

You need to get HumWatch onto your computer. Pick ONE of these methods:

### Option A: Download the ZIP (Easiest)

1. Go to the HumWatch repository
2. Click the big green **"Code"** button
3. Click **"Download ZIP"**
4. Find the ZIP in your Downloads folder
5. Right-click it → **"Extract All..."**
6. Put it somewhere you'll remember. Like `C:\HumWatch` or your Desktop. Doesn't matter.

### Option B: Git Clone (If You Know What Git Is)

If you don't know what Git is, use Option A. Seriously.

```bash
git clone <the-repo-url> C:\HumWatch
```

---

## Step 2: Run The Magic Setup Script

This is the part where the computer does all the work for you.

1. Open the folder where you put HumWatch
2. Find the file called **`setup.bat`**
3. **Double-click it**

That's it. Go get a snack. The script will:

- Create a safe little bubble for Python (called a "virtual environment" — don't worry about it)
- Download and install all the things HumWatch needs
- Download the LibreHardwareMonitor files (the thing that reads your temperatures)
- Ask if you want to install it as a service (more on this later — you can say No for now)

When it's done, it'll tell you it's done. If it yells at you in red text, skip to the [troubleshooting section](#its-not-working-and-im-going-to-cry).

### What If setup.bat Doesn't Work?

Fine, we'll do it the manual way:

1. Open a command prompt (Win + R → type `cmd` → Enter)
2. Navigate to the HumWatch folder:
   ```
   cd C:\HumWatch
   ```
   (Replace `C:\HumWatch` with wherever you actually put it)
3. Create the virtual environment:
   ```
   python -m venv venv
   ```
4. Activate it:
   ```
   venv\Scripts\activate
   ```
5. Install the dependencies:
   ```
   pip install -r requirements.txt
   ```
6. Done. You're a hacker now.

---

## Step 3: Start It Up

### The Easy Way (Double-Click)

1. Find **`run.bat`** in the HumWatch folder
2. **Double-click it**
3. A window will pop up asking for admin permission — **click Yes**
   - (It needs admin access to read your hardware sensors. It's not installing a virus. Probably.)
4. You'll see a terminal window with some text scrolling. That means it's working. **Don't close this window.**

### The "I Don't Want To Give Admin Access" Way

Use **`run-no-admin.bat`** instead. You'll get less sensor data (no temperatures, no fan speeds, no GPU details), but the basics (CPU load, RAM, disk, network) will still work.

### The Manual Way

```
cd C:\HumWatch
venv\Scripts\activate
python -m agent.main
```

### How Do I Know It's Working?

The terminal will show something like:

```
2026-03-02 14:30:00 [humwatch] INFO: HumWatch v0.9.5 starting...
2026-03-02 14:30:01 [humwatch] INFO: Database initialized
2026-03-02 14:30:01 [humwatch] INFO: LibreHardwareMonitor loaded successfully
2026-03-02 14:30:02 [humwatch] INFO: Uvicorn running on http://0.0.0.0:9100
```

When you see that last line, you're in business.

---

## Step 4: Look At The Pretty Pictures

1. Open your web browser (Chrome, Firefox, Edge, whatever — we don't judge)
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
| **Overview** | The big picture — CPU load, GPU load, RAM usage, temps, battery. Like a health check-up summary. |
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

- **Green "Live"** — Everything's connected and updating in real time
- **Amber "Reconnecting..."** — It lost connection and is trying to get it back (just wait)
- **Gray "Disconnected"** — Something's wrong. Is the terminal window still open?

---

## How To See Your Computer From Another Computer

This is where it gets cool. You can check on your desktop from your laptop, your laptop from your phone, your work PC from your couch — as long as they're all on the same Tailscale network.

### What Is Tailscale? (30-Second Explanation)

Tailscale connects your devices into a private network. It's like they're all plugged into the same router, even if one is at home and one is at work. It's free for personal use and takes about 2 minutes to set up.

### Setup (One Time Per Computer)

1. Go to [tailscale.com](https://tailscale.com/) and create an account
2. Download and install Tailscale on **every computer** you want to connect
3. Sign in on each one
4. That's it. They can now see each other.

### Install HumWatch On Each PC You Want To Monitor

Every computer you want to watch needs its own copy of HumWatch running. Just repeat Steps 1–3 from above on each PC.

### View Machine A From Machine B

1. On **Machine A** (the one being monitored), find its Tailscale IP:
   - Click the Tailscale icon in your system tray (bottom-right of your screen)
   - It'll show an IP address like `100.64.x.x` — that's the one
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

If all your machines are on Tailscale and running HumWatch on port 9100, the app will try to automatically find them. Check the **Machines** page — they might already be listed.

---

## Make It Run Forever (Like A Toddler)

Right now, HumWatch only runs while that terminal window is open. Close the window, it stops. That's annoying.

Let's make it start automatically when Windows boots up, run in the background, and restart itself if it crashes.

### Install As A Windows Service

1. Open **PowerShell as Administrator**:
   - Press `Win`, type `PowerShell`
   - Right-click **"Windows PowerShell"**
   - Click **"Run as administrator"**
   - Click **Yes** on the permission popup

2. Navigate to the HumWatch folder:
   ```powershell
   cd C:\HumWatch
   ```

3. Run the install script:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1
   ```

4. It will:
   - Download NSSM (a helper tool for Windows services) if needed
   - Register HumWatch as a Windows service
   - Set it to start automatically on boot
   - Start it right now

5. That's it. Close everything. HumWatch is now running in the background, forever, like that one song stuck in your head.

### Managing The Service

Once installed, you can control it like this (in an admin PowerShell):

| What You Want | Command |
|---------------|---------|
| Check if it's running | `nssm status HumWatch` |
| Stop it | `nssm stop HumWatch` |
| Start it | `nssm start HumWatch` |
| Restart it | `nssm restart HumWatch` |
| Uninstall the service | `powershell -ExecutionPolicy Bypass -File scripts\install-service.ps1 -Uninstall` |

---

## The "What Does All This Stuff Mean" Section

Here's a cheat sheet for the metrics. Clip and save.

### CPU

| Metric | What It Means | When To Worry |
|--------|--------------|---------------|
| **Load** | How busy your CPU is (0–100%) | Sustained 90%+ means something's hogging it |
| **Temperature** | How hot the chip is | 85°C+ = warm. 95°C+ = that's bad. |
| **Clock Speed** | How fast it's running (in GHz) | If it drops way below normal, it might be thermal throttling |
| **Power** | How many watts it's using | Just informational, don't stress about it |

### GPU

| Metric | What It Means | When To Worry |
|--------|--------------|---------------|
| **Load** | How busy your graphics card is | 99% while gaming = normal. 99% while idle = not normal. |
| **Temperature** | How hot the GPU is | 80°C+ = warm. 90°C+ = yikes. |
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
| **Temperature** | How hot the drive is | SSDs: 70°C+ is warm. HDDs: 50°C+ is warm. |

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

### "Python is not recognized"

You didn't add Python to your PATH during installation. Either:
- Reinstall Python and **CHECK THE "Add Python to PATH" BOX** this time
- Or add it manually: Search "Environment Variables" in Windows, edit PATH, add `C:\Users\YourName\AppData\Local\Programs\Python\Python311\` (adjust the version number)

### "I can't open localhost:9100"

- Is the terminal window still open and running? If you closed it, HumWatch stopped.
- Is something else using port 9100? Try changing the port in `config.json`:
  ```json
  { "port": 9200 }
  ```
  Then go to `http://localhost:9200` instead.

### "I don't see temperatures or fan speeds"

You're either:
- Not running as admin (use `run.bat`, not `run-no-admin.bat`)
- Missing LibreHardwareMonitor DLLs. Re-run `setup.bat` or manually run:
  ```powershell
  powershell -ExecutionPolicy Bypass -File scripts\download-lhm.ps1
  ```

### "The GPU section doesn't show up"

You either don't have a dedicated GPU (integrated graphics don't count for most sensors), or LibreHardwareMonitor can't detect it. This is normal for some laptops.

### "The Battery section doesn't show up"

You're on a desktop. Desktops don't have batteries. This is working as intended.

### "I can't see Machine A from Machine B"

Checklist:
1. Is Tailscale running on **both** machines?
2. Is HumWatch running on Machine A?
3. Can you ping Machine A's Tailscale IP from Machine B? (Open cmd, type `ping 100.64.x.x`)
4. Is Windows Firewall blocking port 9100? Try adding a firewall rule:
   ```powershell
   netsh advfirewall firewall add rule name="HumWatch" dir=in action=allow protocol=TCP localport=9100
   ```

### "The dashboard says 'Disconnected'"

The browser lost its real-time connection. This usually fixes itself in a few seconds. If it doesn't:
- Check if HumWatch is still running (is the terminal window open? Is the service running?)
- Hard-refresh the browser: `Ctrl + Shift + R`

### "Everything is slow / the database is huge"

The database keeps 7 days of data. If it's getting too big, you can reduce retention in `config.json`:
```json
{ "retention_days": 3 }
```

---

## The Fancy Settings Nobody Asked About

HumWatch has a config file at `config.json` in the root folder. You don't need to touch it — the defaults are fine. But if you want to tinker:

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

1. Go to `static/css/themes/`
2. Copy `theme-light.css` and rename it to something cool like `theme-bubblegum.css`
3. Change the color values (they're all CSS variables starting with `--hw-`)
4. Register it in `static/js/utils/theme.js`
5. Refresh the dashboard and select it in Settings

---

## The End

You did it. You installed a thing. Your computer is being watched. In a good way.

If something is still broken, re-read this guide. Slowly. Out loud. With a juice box.

---

*A Static Hum Studio Production — "What hums beneath the shell."*

*Licensed under [GPL-3.0](LICENSE)*
