#!/bin/bash
#
# This script enables execute permissions (chmod +x) on all scripts in the current folder and its subfolders.
#
# Usage:
# ./MakeScriptsExecutable.sh
#

# Find all files with a .sh extension in the current directory and subdirectories
# and add execute permissions to them.
find . -type f -name "*.sh" -exec chmod +x {} \;

echo "All scripts in the current folder and subfolders are now executable."
