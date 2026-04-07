#!/bin/bash

# OpenClaw Daily Snapshot Backup Script
# Creates a timestamped archive of ~/.openclaw and uploads to Google Drive via rclone

# Configuration
SOURCE_DIR="/home/young/.openclaw"
REMOTE_NAME="agent-drive"
REMOTE_PATH="openclaw-backups/snapshots"
TIMESTAMP=$(date +%Y%m%d)
BACKUP_FILE="/tmp/openclaw-snapshot-${TIMESTAMP}.tar.gz"
LOG_FILE="/home/young/.openclaw/backup-last-run.log"

# Ensure we have access to the rclone config
export PATH="/usr/bin:/usr/local/bin:$PATH"

echo "--- Backup started at $(date) ---" > "$LOG_FILE"

# 1. Create the archive
# Excluding config.json for security and .cache/npm if it exists
echo "Creating archive: $BACKUP_FILE" >> "$LOG_FILE"
/usr/bin/tar -czf "$BACKUP_FILE" \
    --exclude='config.json' \
    --exclude='node_modules' \
    --exclude='.npm' \
    --transform 's,^\.openclaw,openclaw-backup,' \
    -C /home/young .openclaw 2>> "$LOG_FILE"

if [ $? -ne 0 ]; then
    echo "ERROR: Tar command failed. Check permissions." >> "$LOG_FILE"
    exit 1
fi

# 2. Upload to Google Drive
echo "Uploading to $REMOTE_NAME:$REMOTE_PATH" >> "$LOG_FILE"
/usr/bin/rclone copy "$BACKUP_FILE" "$REMOTE_NAME:$REMOTE_PATH" --log-file="$LOG_FILE" --log-level INFO

if [ $? -eq 0 ]; then
    echo "SUCCESS: Backup uploaded successfully." >> "$LOG_FILE"
    # Update last success timestamp
    date +%s > "/home/young/.openclaw/last_backup_success"
else
    echo "ERROR: Rclone upload failed." >> "$LOG_FILE"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# 3. Cleanup local file
rm -f "$BACKUP_FILE"
echo "--- Backup completed at $(date) ---" >> "$LOG_FILE"
