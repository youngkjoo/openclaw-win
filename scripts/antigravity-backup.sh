#!/bin/bash

# Antigravity Daily Snapshot Backup Script
# Creates a timestamped archive of ~/.gemini/antigravity/conversations and uploads to Google Drive via rclone

# Configuration
SOURCE_DIR="/Users/dfadmin/.gemini/antigravity/conversations"
REMOTE_NAME="agent-drive"
REMOTE_PATH="antigravity-backups/snapshots"
TIMESTAMP=$(date +%Y%m%d)
BACKUP_FILE="/tmp/antigravity-snapshot-${TIMESTAMP}.tar.gz"
LOG_FILE="/Users/dfadmin/.openclaw/logs/antigravity-backup.log"

# Ensure we have access to the rclone config
export PATH="/opt/homebrew/bin:/usr/bin:/usr/local/bin:$PATH"

echo "--- Backup started at $(date) ---" > "$LOG_FILE"

# 1. Create the archive
echo "Creating archive: $BACKUP_FILE" >> "$LOG_FILE"
/opt/homebrew/bin/gtar -czf "$BACKUP_FILE" \
    --transform 's,^conversations,antigravity-backup,' \
    -C /Users/dfadmin/.gemini/antigravity conversations 2>> "$LOG_FILE"

if [ $? -ne 0 ]; then
    echo "ERROR: Tar command failed. Check permissions." >> "$LOG_FILE"
    exit 1
fi

# 2. Upload to Google Drive
echo "Uploading to $REMOTE_NAME:$REMOTE_PATH" >> "$LOG_FILE"
/opt/homebrew/bin/rclone copy "$BACKUP_FILE" "$REMOTE_NAME:$REMOTE_PATH" --log-file="$LOG_FILE" --log-level INFO

if [ $? -eq 0 ]; then
    echo "SUCCESS: Backup uploaded successfully." >> "$LOG_FILE"
    # Update last success timestamp
    date +%s > "/Users/dfadmin/.gemini/antigravity/last_backup_success"
else
    echo "ERROR: Rclone upload failed." >> "$LOG_FILE"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# 3. Cleanup local file
rm -f "$BACKUP_FILE"
echo "--- Backup completed at $(date) ---" >> "$LOG_FILE"
