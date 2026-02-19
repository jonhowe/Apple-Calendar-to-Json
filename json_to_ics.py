#!/usr/bin/env python3
"""
Convert caldump JSON output (exchange.json) to an ICS file for Home Assistant.

Input schema expected:
{
  "events": [
    {
      "id": "...",
      "title": "...",
      "start": "2026-02-19T14:00:00.000Z",
      "end": "2026-02-19T14:15:00.000Z",
      "allDay": false,
      "location": "...",
      "notes": "..."
    },
    ...
  ]
}

Outputs a basic VCALENDAR with VEVENT entries.

Usage:
  python3 json_to_ics.py exchange.json exchange.ics
Optional:
  TZ=America/New_York python3 json_to_ics.py exchange.json exchange.ics
"""

import json
import os
import sys
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo


def parse_iso8601(s: str) -> datetime:
    # Handles "Z" and offsets
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)


def to_utc_z(dt: datetime) -> str:
    # Ensure UTC and format like 20260219T140000Z
    dt_utc = dt.astimezone(timezone.utc)
    return dt_utc.strftime("%Y%m%dT%H%M%SZ")


def escape_ics_text(s: str) -> str:
    # RFC5545 text escaping
    s = s.replace("\\", "\\\\")
    s = s.replace("\n", "\\n")
    s = s.replace(";", r"\;")
    s = s.replace(",", r"\,")
    return s


def fold_ics_line(line: str, limit: int = 75) -> str:
    # Soft fold at ~75 characters. (Technically 75 octets; this is fine for ASCII.)
    if len(line) <= limit:
        return line
    out = []
    while len(line) > limit:
        out.append(line[:limit])
        line = " " + line[limit:]
    out.append(line)
    return "\r\n".join(out)


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 json_to_ics.py <input.json> <output.ics>", file=sys.stderr)
        sys.exit(2)

    in_path = sys.argv[1]
    out_path = sys.argv[2]

    tz_name = os.environ.get("TZ", "America/New_York")
    tz = ZoneInfo(tz_name)

    with open(in_path, "r", encoding="utf-8") as f:
        payload = json.load(f)

    events = payload.get("events", [])
    now = datetime.now(timezone.utc)

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Apple-Calendar-to-Json//caldump-json-to-ics//EN",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
    ]

    for e in events:
        title = (e.get("title") or "").strip() or "(No Title)"
        uid = (e.get("id") or "").strip() or f"no-id-{abs(hash((title, e.get('start'), e.get('end'))))}"
        all_day = bool(e.get("allDay", False))

        start_raw = e.get("start")
        end_raw = e.get("end")
        if not start_raw or not end_raw:
            continue

        start_dt = parse_iso8601(start_raw)
        end_dt = parse_iso8601(end_raw)

        # Normalize to aware datetimes (should already be from JSON)
        if start_dt.tzinfo is None:
            start_dt = start_dt.replace(tzinfo=timezone.utc)
        if end_dt.tzinfo is None:
            end_dt = end_dt.replace(tzinfo=timezone.utc)

        vevent = ["BEGIN:VEVENT"]

        vevent.append(f"UID:{escape_ics_text(uid)}")
        vevent.append(f"DTSTAMP:{to_utc_z(now)}")

        if all_day:
            # Home Assistant generally expects all-day events as DATE values where DTEND is exclusive (next day)
            start_local_date = start_dt.astimezone(tz).date()
            end_local_date = end_dt.astimezone(tz).date()

            # If export gives same-day end for all-day, enforce exclusive end = start+1
            if end_local_date <= start_local_date:
                end_local_date = start_local_date + timedelta(days=1)

            vevent.append(f"DTSTART;VALUE=DATE:{start_local_date.strftime('%Y%m%d')}")
            vevent.append(f"DTEND;VALUE=DATE:{end_local_date.strftime('%Y%m%d')}")
        else:
            vevent.append(f"DTSTART:{to_utc_z(start_dt)}")
            vevent.append(f"DTEND:{to_utc_z(end_dt)}")

        vevent.append(f"SUMMARY:{escape_ics_text(title)}")

        location = (e.get("location") or "").strip()
        if location:
            vevent.append(f"LOCATION:{escape_ics_text(location)}")

        notes = (e.get("notes") or "").strip()
        if notes:
            vevent.append(f"DESCRIPTION:{escape_ics_text(notes)}")

        vevent.append("END:VEVENT")

        # fold lines
        for line in vevent:
            lines.append(fold_ics_line(line))

    lines.append("END:VCALENDAR")

    with open(out_path, "w", encoding="utf-8", newline="") as f:
        f.write("\r\n".join(lines) + "\r\n")

    print(f"OK: wrote ICS to {out_path} (events: {len(events)})")


if __name__ == "__main__":
    main()