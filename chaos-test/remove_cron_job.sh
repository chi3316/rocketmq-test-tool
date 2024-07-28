#!/bin/sh

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <script_path>"
  exit 1
fi

SCRIPT_PATH=$1

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Error: Script $SCRIPT_PATH does not exist."
  exit 1
fi

# Remove lines containing the script path
crontab -l | grep -v "$SCRIPT_PATH" | crontab -

echo "Cron job for $SCRIPT_PATH removed."

