#!/bin/bash
# Script to synchronize sensor reports with the central server using rsync.

# --- Configuration ---
# Ensure the remote user has write permissions in DEST_DIR
# and that SSH authentication (preferably with a public key) is configured.
SOURCE_DIR="./reports/"
REMOTE_USER="user"
REMOTE_HOST="ip_of_mini_pc"
DEST_DIR="/path/to/autonomous_brewing/central_server/incoming_reports/"

echo "Starting report synchronization..."

# Infinite loop to synchronize and then clean up the already sent files
while true; do
  # The --remove-source-files flag deletes source files after a successful transfer.
  rsync -avz --remove-source-files "$SOURCE_DIR"*.json "$REMOTE_USER@$REMOTE_HOST:$DEST_DIR"
  
  if [ $? -eq 0 ]; then
    echo "Synchronization successful at $(date)."
  else
    echo "Synchronization error at $(date)."
  fi
  
  sleep 30 # Attempt to sync every 30 seconds
done
