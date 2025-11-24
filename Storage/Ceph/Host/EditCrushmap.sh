#!/bin/bash
#
# EditCrushmap.sh
#
# This script manages the decompilation and recompilation of the Ceph cluster's CRUSH map,
# facilitating custom modifications. Administrators can either decompile the current CRUSH
# map into a human-readable format or recompile it for use in the cluster.
#
# Usage:
#   EditCrushmap.sh <command>
#
# Examples:
#   # Decompile the CRUSH map
#   EditCrushmap.sh decompile
#
#   # Recompile the CRUSH map
#   EditCrushmap.sh compile
#
# Function Index:
#   - decompileCrushMap
#   - recompileCrushMap
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "command:string" "$@"

# Validate command argument
if [[ "$COMMAND" != "decompile" && "$COMMAND" != "compile" ]]; then
    __err__ "Invalid command: $COMMAND (must be: decompile or compile)"
    exit 64
fi

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Functions
###############################################################################
function decompileCrushMap() {
    echo "Getting and decompiling the CRUSH map..."
    ceph osd getcrushmap -o "/tmp/crushmap.comp"
    crushtool -d "/tmp/crushmap.comp" -o "/tmp/crushmap.decomp"
    echo "Decompiled CRUSH map is at /tmp/crushmap.decomp"
}

function recompileCrushMap() {
    echo "Recompiling and setting the CRUSH map..."
    crushtool -c "/tmp/crushmap.decomp" -o "/tmp/crushmap.comp"
    ceph osd setcrushmap -i "/tmp/crushmap.comp"
    echo "CRUSH map has been recompiled and set."
}

###############################################################################
# Main Logic
###############################################################################
case "$COMMAND" in
    decompile)
        decompileCrushMap
        ;;
    compile)
        recompileCrushMap
        ;;
esac

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-21: Migrated to ArgumentParser framework, fixed script name
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-21: Added ArgumentParser for argument validation
# - 2025-11-21: Fixed script name in header (CephEditCrushmap.sh → EditCrushmap.sh)
#
# Known issues:
# -
#

