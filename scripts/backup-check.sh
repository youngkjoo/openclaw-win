#!/bin/bash

# OpenClaw Backup Catch-Up Checker
# Checks if the last successful backup was more than 24 hours ago.
# If so, triggers a new backup.

SUCCESS_MARKER="/home/young/.openclaw/last_backup_success"
BACKUP_SCRIPT="/home/young/openclaw-win/scripts/openclaw-backup.sh"

# If the marker doesn't exist, run the backup
if [ ! -f "$SUCCESS_MARKER" ]; then
    echo "No previous backup record found. Initializing..."
    "$BACKUP_SCRIPT"
    exit $?
fi

# Get the last success timestamp
LAST_SUCCESS=$(cat "$SUCCESS_MARKER")
CURRENT_TIME=$(date +%s)
ONE_DAY_SECONDS=86400

# Calculate time difference
DIFF=$((CURRENT_TIME - LAST_SUCCESS))

if [ "$DIFF" -ge "$ONE_DAY_SECONDS" ]; then
    echo "Last backup was more than 24 hours ago. Running catch-up..."
    "$BACKUP_SCRIPT"
else
    echo "Backup for the last 24 hours already exists. Skipping."
fi
