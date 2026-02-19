# Apple Calendar → JSON → ICS → Home Assistant

## Overview

This project provides a lightweight, automation-friendly way to export events from macOS Apple Calendar (including Exchange calendars), transform them into structured JSON and ICS formats, and publish them to external systems such as:

- Home Assistant
- Other automation pipelines
- Custom scripts or agents
- Notification systems
- Self-hosted services

It is designed for users who:

- Want unattended calendar exports
- Prefer structured data over manual `.ics` exports
- Need a reliable, repeatable export mechanism
- Want to integrate Apple Calendar with external systems

This repository focuses on **one-way export** from macOS to external consumers.

---

## What This Does

The system performs the following pipeline:

1. **Swift (EventKit)** reads events directly from Apple Calendar.
2. Events are written to a structured `exchange.json` file.
3. JSON is converted to a standards-compliant `exchange.ics`.
4. Both files can be uploaded via SSH to:
   - A remote host (JSON consumer)
   - A Home Assistant instance (ICS calendar feed)
5. A `launchd` job schedules this automatically.

The result is a fully automated calendar export pipeline.

---

## Why This Exists

Apple Calendar does not provide:

- A built-in unattended export mechanism
- A JSON export format
- An easy way to integrate with external automation systems

This project fills that gap by:

- Using macOS-native APIs (EventKit)
- Avoiding fragile UI scripting
- Producing machine-readable outputs
- Supporting scheduled execution

---

## Architecture

```
Apple Calendar (Exchange, iCloud, etc.)
            ↓
        caldump.swift
            ↓
       exchange.json
            ↓
       json_to_ics.py
            ↓
       exchange.ics
            ↓
  ┌──────────────┬──────────────┐
  ↓              ↓              ↓
Seedbox      Home Assistant   Other Systems
(JSON)         (/local/)         (optional)
```

---

## Repository Contents

- `caldump.swift`  
  Swift CLI tool using EventKit to export events to JSON.

- `json_to_ics.py`  
  Converts exported JSON into a valid ICS calendar file.

- `calendar_export_and_ship.sh`  
  Orchestrates export, conversion, and SSH uploads.

- `launch_agents/com.example.calendarship.plist`  
  Example `launchd` configuration for scheduled execution.

- `README.md`  
  This document.

---

## Requirements

- macOS
- Swift compiler (`swiftc`)
- Python 3.9+ (for `zoneinfo`)
- SSH access to remote hosts
- Apple Calendar access permission granted to the binary/script

---

## Installation

### 1. Clone Repository

```bash
git clone <repo-url>
cd Apple-Calendar-to-Json
```

---

### 2. Build the Swift Exporter

```bash
swiftc caldump.swift -o caldump
```

This compiles the EventKit-based calendar exporter.

---

### 3. Grant Calendar Permission

Run the script once manually:

```bash
./calendar_export_and_ship.sh
```

macOS will prompt for Calendar access.  
Approve access under:

**System Settings → Privacy & Security → Calendars**

---

## Running the Pipeline Manually

```bash
./calendar_export_and_ship.sh
```

This will:

- Export JSON
- Convert to ICS
- Upload files (if configured)

All behavior is parameterized via environment variables or flags.

Run:

```bash
./calendar_export_and_ship.sh --help
```

for available options.

---

## Scheduling with launchd

This project includes a sample LaunchAgent.

### 1. Copy the Example

Copy the sanitized plist:

```
launch_agents/com.example.calendarship.plist
```

to:

```
~/Library/LaunchAgents/com.yourname.calendarship.plist
```

Edit:

- `REPO_DIR`
- `REMOTE_HOST`
- `REMOTE_PATH`
- `HA_HOST`
- `HA_PATH`

---

### 2. Validate

```bash
plutil -lint ~/Library/LaunchAgents/com.yourname.calendarship.plist
```

You should see:

```
OK
```

---

### 3. Install (Modern macOS)

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.yourname.calendarship.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.yourname.calendarship.plist
launchctl enable gui/$(id -u)/com.yourname.calendarship
launchctl kickstart -k gui/$(id -u)/com.yourname.calendarship
```

---

### 4. Logs

The example plist writes logs to:

```
/tmp/calendarship.out.log
/tmp/calendarship.err.log
```

Adjust paths as needed.

---

## Home Assistant Integration

After the ICS file is uploaded to `/config/www/exchange.ics`, it becomes available in Home Assistant at:

```
http://<home-assistant-host>:8123/local/exchange.ics
```

Add to `configuration.yaml`:

```yaml
calendar:
  - platform: ics
    name: Work Calendar
    url: http://homeassistant.home.lan:8123/local/exchange.ics
```

Restart Home Assistant after configuration changes.

---

## Security Notes

- Uses SSH for file transfer.
- Assumes SSH keys are configured for non-interactive access.
- Does not store credentials in the repository.
- No inbound network exposure required.

---

## Limitations

- One-way export only (no write-back to Apple Calendar).
- Requires macOS for EventKit access.
- Relies on scheduled polling (not event-triggered).

---

## Potential Enhancements

- Change detection to avoid unnecessary uploads
- Atomic remote writes
- rsync instead of scp
- System-wide LaunchDaemon
- Webhook-based push
- Additional output formats (CSV, REST API)

---

## Intended Use Cases

- Integrating Exchange calendars into Home Assistant
- Feeding Apple Calendar data into automation systems
- Bridging macOS calendar data to Linux servers
- Structured archival of calendar events

---

## License

See `LICENSE`.

---

## Contributing

Improvements and refinements are welcome, especially around:

- Error handling
- Retry logic
- Performance tuning
- Multi-calendar support
- Recurrence handling

---

## Summary

This repository provides a practical, automation-ready bridge between Apple Calendar and external systems using native macOS APIs and simple, composable tooling.

It is designed to be understandable, auditable, and adaptable.