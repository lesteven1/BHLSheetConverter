#!/bin/zsh
set -euo pipefail

user_home="$(/usr/bin/python3 -c 'from pathlib import Path; print(Path.home())')"
user_id="$(/usr/bin/id -u)"
launch_agent="$user_home/Library/LaunchAgents/com.bhl.sheetmachine.plist"
installed_app="$user_home/Applications/Sheet Machine.app"
support_dir="$user_home/Library/Application Support/SheetMachine"

/bin/launchctl bootout "gui/$user_id" "$launch_agent" 2>/dev/null || true
/usr/bin/pkill -x SheetMachine 2>/dev/null || true
/bin/rm -f "$launch_agent"
/bin/rm -rf "$installed_app" "$support_dir"

echo "Sheet Machine was uninstalled. Your downloaded and cleaned CSV files were not removed."
