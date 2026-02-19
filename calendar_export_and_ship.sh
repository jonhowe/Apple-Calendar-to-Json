#!/usr/bin/env bash
#
# calendar_export_and_ship.sh
#
# PURPOSE
# -------
# This script performs the full export + distribution pipeline:
#
#   1) Run Swift caldump → generate exchange.json
#   2) Convert exchange.json → exchange.ics (Python)
#   3) Upload JSON to seedbox (consumer process)
#   4) Upload ICS to Home Assistant www directory
#
# It is fully parameterized and safe to use with launchd.
#
# ---------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------
# DEFAULTS (can be overridden via environment variables or CLI flags)
# ---------------------------------------------------------------------

# Directory containing this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repository root (where caldump + json_to_ics live)
REPO_DIR="${REPO_DIR:-$SCRIPT_DIR}"

# Swift binary (compiled from caldump.swift)
CALDUMP_BIN="${CALDUMP_BIN:-$REPO_DIR/caldump}"

# Python converter script
JSON2ICS="${JSON2ICS:-$REPO_DIR/json_to_ics.py}"

# Calendar name as it appears in macOS Calendar
CALENDAR_NAME="${CALENDAR_NAME:-Calendar}"

# Rolling window for export
# Accepts:
#   -N  (N days in past)
#   +N  (N days in future)
#   YYYY-MM-DD
START_SPEC="${START_SPEC:--2}"
END_SPEC="${END_SPEC:-+45}"

# Local output files
OUTFILE="${OUTFILE:-$REPO_DIR/exchange.json}"
ICS_OUTFILE="${ICS_OUTFILE:-$REPO_DIR/exchange.ics}"

# Remote seedbox (JSON destination)
REMOTE_HOST="${REMOTE_HOST:-seedbox}"
REMOTE_PATH="${REMOTE_PATH:-/home/jhowe/git/signal-cli-agent/user-generated/exchange.json}"

# Home Assistant SSH target
HA_HOST="${HA_HOST:-root@homeassistant.home.lan}"
HA_PATH="${HA_PATH:-/config/www/exchange.ics}"

# Build caldump automatically if missing?
DO_BUILD="${DO_BUILD:-1}"

# ---------------------------------------------------------------------
# CLI ARGUMENT PARSING
# ---------------------------------------------------------------------

usage() {
  cat <<EOF
Usage:
  calendar_export_and_ship.sh [options]

Options:
  --repo-dir <dir>
  --calendar <name>
  --start <spec>           (-N, +N, YYYY-MM-DD)
  --end <spec>
  --remote-host <host>
  --remote-path <path>
  --ha-host <ssh-target>
  --ha-path <path>
  --no-build
  -h | --help

All options also configurable via environment variables.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --calendar) CALENDAR_NAME="$2"; shift 2 ;;
    --start) START_SPEC="$2"; shift 2 ;;
    --end) END_SPEC="$2"; shift 2 ;;
    --remote-host) REMOTE_HOST="$2"; shift 2 ;;
    --remote-path) REMOTE_PATH="$2"; shift 2 ;;
    --ha-host) HA_HOST="$2"; shift 2 ;;
    --ha-path) HA_PATH="$2"; shift 2 ;;
    --no-build) DO_BUILD=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------

# Convert -N / +N / YYYY-MM-DD to concrete YYYY-MM-DD
resolve_date() {
  local spec="$1"

  # Relative days
  if [[ "$spec" =~ ^[+-][0-9]+$ ]]; then
    if [[ "$spec" == -* ]]; then
      local n="${spec#-}"
      date -v-"$n"d +%F
    else
      local n="${spec#+}"
      date -v+"$n"d +%F
    fi
  else
    # Absolute date
    echo "$spec"
  fi
}

# Extract directory portion of a remote path
remote_dir_from_path() {
  dirname "$1"
}

# ---------------------------------------------------------------------
# BEGIN PIPELINE
# ---------------------------------------------------------------------

cd "$REPO_DIR"

echo "== Calendar Export Pipeline =="
echo "Repo: $REPO_DIR"
echo "Calendar: $CALENDAR_NAME"

# ---------------------------------------------------------------------
# Step 1 — Ensure caldump exists (build if needed)
# ---------------------------------------------------------------------

if [[ ! -x "$CALDUMP_BIN" ]]; then
  if [[ "$DO_BUILD" == "1" ]]; then
    echo "Building caldump..."
    swiftc "$REPO_DIR/caldump.swift" -o "$CALDUMP_BIN"
  else
    echo "caldump missing and auto-build disabled."
    exit 1
  fi
fi

START_DATE="$(resolve_date "$START_SPEC")"
END_DATE="$(resolve_date "$END_SPEC")"

echo "Export window: $START_DATE → $END_DATE"

# ---------------------------------------------------------------------
# Step 2 — Run Swift → JSON
# ---------------------------------------------------------------------

echo "Generating JSON..."
"$CALDUMP_BIN" \
  --calendar "$CALENDAR_NAME" \
  --start "$START_DATE" \
  --end "$END_DATE" \
  --out "$OUTFILE"

# ---------------------------------------------------------------------
# Step 3 — Convert JSON → ICS
# ---------------------------------------------------------------------

echo "Converting JSON to ICS..."
python3 "$JSON2ICS" "$OUTFILE" "$ICS_OUTFILE"

# ---------------------------------------------------------------------
# Step 4 — Upload JSON to Seedbox
# ---------------------------------------------------------------------

echo "Uploading JSON to $REMOTE_HOST..."
REMOTE_DIR="$(remote_dir_from_path "$REMOTE_PATH")"
ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_DIR'"
scp -q "$OUTFILE" "$REMOTE_HOST:$REMOTE_PATH"

# ---------------------------------------------------------------------
# Step 5 — Upload ICS to Home Assistant
# ---------------------------------------------------------------------

echo "Uploading ICS to Home Assistant..."
HA_DIR="$(remote_dir_from_path "$HA_PATH")"
ssh "$HA_HOST" "mkdir -p '$HA_DIR'"
scp -q "$ICS_OUTFILE" "$HA_HOST:$HA_PATH"

# ---------------------------------------------------------------------
# DONE
# ---------------------------------------------------------------------

echo "--------------------------------------------"
echo "SUCCESS"
echo "JSON → $REMOTE_HOST:$REMOTE_PATH"
echo "ICS  → $HA_HOST:$HA_PATH"
echo "--------------------------------------------"