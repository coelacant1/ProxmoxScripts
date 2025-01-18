#!/bin/bash
#
# _ExampleScript.sh
#
# Demonstrates usage of the included spinner and message functions.
#
# Usage:
#   ./_ExampleScript.sh <text1> <text2>
#
#
# This script simulates a process, updates its status, and then shows success and error messages.
#

source "$UTILITIES"

###############################################################################
# Initial Checks
###############################################################################
check_root
check_proxmox

###############################################################################
# Parse Arguments
###############################################################################
if [ $# -lt 2 ]; then
  echo "Error: Insufficient arguments."
  echo "Usage: ./_ExampleScript.sh <text1> <text2>"
  exit 1
fi

###############################################################################
# MAIN
###############################################################################
info "Simulating an error scenario..."
sleep 2
err "A simulated error has occurred!"

info "Starting a simulated process..."
sleep 2
update "Process is halfway..."
sleep 2
ok "Process completed successfully."
