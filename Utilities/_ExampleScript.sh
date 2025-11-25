#!/bin/bash
#
# _ExampleScript.sh
#
# Minimal script template matching ProxmoxScripts repository conventions.
# Copy this file and adapt for new scripts.
#
# This example demonstrates using ArgumentParser.sh for argument parsing
# with automatic validation and type checking.
#
# Usage:
#   _ExampleScript.sh <vmid> <cores> [--memory MB] [--verbose]
#
# Example:
#   _ExampleScript.sh 100 4
#   _ExampleScript.sh 100 4 --memory 2048 --verbose
#
# Function Index:
#   - usage
#   - cleanup
#   - main
#

set -euo pipefail

###############################################################################
# Setup / Globals
###############################################################################
# Assumes UTILITYPATH already exported by GUI.sh (or caller). Do not auto-discover
# to avoid duplicating logic or mis-resolving paths when invoked from GUI.

# Source shared helpers (keep minimal; don't duplicate functionality)
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/ArgumentParser.sh"

###############################################################################
# Initial checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Usage
###############################################################################
usage() {
    cat <<-USAGE
		Usage: ${0##*/} <vmid> <cores> [--memory MB] [--verbose]

		Arguments:
		  vmid     - VM ID (numeric)
		  cores    - Number of CPU cores (numeric)

		Options:
		  --memory MB    - Memory in MB (default: 2048)
		  --verbose      - Enable verbose output

		Examples:
		  ${0##*/} 100 4
		  ${0##*/} 100 4 --memory 2048 --verbose
	USAGE
}

###############################################################################
# Parse Arguments
###############################################################################
# Parse all arguments using unified __parse_args__ API
__parse_args__ "vmid:vmid cores:cpu --memory:memory:2048 --verbose:flag" "$@"

# Additional validation with range checking
if ! __validate_range__ "$CORES" "1" "128" "cores"; then
    exit 1
fi

if ! __validate_range__ "$MEMORY" "512" "524288" "memory"; then
    exit 1
fi

###############################################################################
# Functions
###############################################################################
cleanup() {
    # called on exit to clean temporary files, stop spinners, etc.
    __stop_spin__ 2>/dev/null || true
}

trap cleanup EXIT

###############################################################################
# MAIN
###############################################################################
main() {
    __info__ "Starting: ${0##*/}"

    if [[ "$VERBOSE" == "true" ]]; then
        __update__ "Configuration: VMID=$VMID, Cores=$CORES, Memory=$MEMORY MB"
    fi

    # Example work with parsed arguments
    __update__ "Configuring VM ${VMID} with ${CORES} cores and ${MEMORY}MB memory..."
    sleep 1

    # Simulated operation
    if [[ "$VMID" -lt 100 ]]; then
        __err__ "VMID must be 100 or greater"
        exit 1
    fi

    # Example: Using qm to configure VM (uncomment in production)
    # qm set "$VMID" --cores "$CORES" --memory "$MEMORY"

    if [[ "$VERBOSE" == "true" ]]; then
        __update__ "Configuration applied successfully"
    fi

    __ok__ "Finished: ${0##*/}"
}

main

###############################################################################
# Alternative Parsing Methods (commented out)
###############################################################################
#
# Method 2: Using short and long flags
# __parse_args__ "vmid:vmid --cores:cpu:4 -m|--memory:memory:2048 --verbose:flag" "$@"
#
# Method 3: Using VMID range for bulk operations
# __parse_args__ "start:vmid end:vmid --action:string" "$@"
# for ((vmid=START; vmid<=END; vmid++)); do
#   echo "Processing VM $vmid with action $ACTION"
# done
#
# Method 4: All flags, no positional
# __parse_args__ "--vmid:vmid --cores:cpu --memory:memory:2048" "$@"
#

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Updated to use unified __parse_args__ API (v2)
# - 2025-11-20: Created comprehensive example script
# - 2025-11-20: Added examples for all utility functions
# - 2025-11-20: Demonstrated ArgumentParser usage patterns
# - 2025-11-20: Added error handling examples
# - 2025-11-20: Included NON_INTERACTIVE_STANDARD compliance
# - Tested: ArgumentParser validation functions
# - This is an example script for demonstration purposes only
#
# Fixes:
# - 2025-11-24: Replaced deprecated __parse_positional_args__ and __parse_named_args__ with __parse_args__
#
# Known issues:
# -
#

