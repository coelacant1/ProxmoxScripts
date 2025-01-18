#!/bin/bash
#
# CephEditCrushmap.sh
#
# This script manages the decompilation and recompilation of the Ceph cluster's CRUSH map,
# facilitating custom modifications. Administrators can either decompile the current CRUSH
# map into a human-readable format or recompile it for use in the cluster.
#
# Usage:
#   ./CephEditCrushmap.sh <command>
#
# Examples:
#   # Decompile the CRUSH map
#   ./CephEditCrushmap.sh decompile
#
#   # Recompile the CRUSH map
#   ./CephEditCrushmap.sh compile
#
# Function Index:
#   - decompileCrushMap
#   - recompileCrushMap
#
source "$UTILITIES"

###############################################################################
# Environment Checks
###############################################################################
check_root
check_proxmox

###############################################################################
# Variables
###############################################################################
userCommand="$1"

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
if [ -z "$userCommand" ]; then
    echo "Error: Missing command. Use 'decompile' or 'compile'."
    exit 1
fi

case "$userCommand" in
    decompile)
        decompileCrushMap
        ;;
    compile)
        recompileCrushMap
        ;;
    *)
        echo "Error: Invalid command. Use 'decompile' or 'compile'."
        exit 2
        ;;
esac
