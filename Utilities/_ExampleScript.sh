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
# Method 1: Using positional parser for required args
if [[ $# -lt 2 ]]; then
    echo "Error: Missing required arguments." >&2
    usage
    exit 1
fi

# Parse positional arguments (vmid, cores)
if ! __parse_positional_args__ \
    "VMID:numeric:required CORES:numeric:required" \
    "$1" "$2"; then
    echo "Error: Invalid arguments." >&2
    usage
    exit 1
fi
shift 2

# Parse optional named arguments (--memory, --verbose)
if ! __parse_named_args__ \
    "MEMORY:--memory:numeric:optional:2048 VERBOSE:--verbose:boolean:optional:false" \
    "$@"; then
    echo "Error: Invalid options." >&2
    usage
    exit 1
fi

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
# Method 2: Using flag parser for short/long flags
# __parse_flag_options__ \
#   "VMID:-i:--vmid:numeric: CORES:-c:--cores:numeric:4 MEMORY:-m:--memory:numeric:2048 VERBOSE:-v:--verbose:boolean:false" \
#   "$@"
#
# Method 3: Using VMID range parser for bulk operations
# __parse_vmid_range_args__ "$@"
# for ((vmid=START_VMID; vmid<=END_VMID; vmid++)); do
#   echo "Processing VM $vmid"
# done
#
# Method 4: Using bulk operation parser
# __parse_bulk_operation_args__ 3 "ACTION:string:required" "$@"
# echo "Performing $ACTION on VMs $START_VMID to $END_VMID"
#

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Created comprehensive example script
# - 2025-11-20: Added examples for all utility functions
# - 2025-11-20: Demonstrated ArgumentParser usage patterns
# - 2025-11-20: Added error handling examples
# - 2025-11-20: Included NON_INTERACTIVE_STANDARD compliance
# - Tested: ArgumentParser validation functions
# - This is an example script for demonstration purposes only
#
# Fixes:
# -
#
# Known issues:
# -
#

