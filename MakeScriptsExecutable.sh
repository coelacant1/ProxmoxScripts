#!/bin/bash
#
# MakeScriptsExecutable.sh
#
# Adds execute permissions to all .sh files in current and subdirectories.
#
# Usage:
#   ./MakeScriptsExecutable.sh
#
# Examples:
#   ./MakeScriptsExecutable.sh
#

set -euo pipefail

# Find and make executable
find . -type f -name "*.sh" -exec chmod +x {} \;

echo "All .sh files are now executable"
