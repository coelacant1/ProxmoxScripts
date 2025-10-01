#!/bin/bash
#
# _ExampleScript.sh
#
# Minimal script template matching ProxmoxScripts repository conventions.
# Copy this file and adapt for new scripts.
#
# Usage:
#   ./_ExampleScript.sh <required-arg>
#
# Example:
#   ./_ExampleScript.sh foo
#
# Function Index:
#   - usage
#   - cleanup
#   - main
#

###############################################################################
# Setup / Globals
###############################################################################
# Assumes UTILITYPATH already exported by GUI.sh (or caller). Do not auto-discover
# to avoid duplicating logic or mis-resolving paths when invoked from GUI.

# Source shared helpers (keep minimal; don't duplicate functionality)
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Communication.sh"

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
Usage: ${0##*/} <required-arg> [optional-arg]

Examples:
  ${0##*/} foo
USAGE
}

###############################################################################
# Parse Arguments
###############################################################################
if [[ $# -lt 1 ]]; then
  echo "Error: Missing required arguments." >&2
  usage
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

  # Example work
  __update__ "Working on ${1}..."
  sleep 1

  if false; then
    __err__ "An example error occurred"
    exit 1
  fi

  __ok__ "Finished: ${0##*/}"
}

main "$@"

###############################################################################
# Testing status
###############################################################################
# Tested: none
