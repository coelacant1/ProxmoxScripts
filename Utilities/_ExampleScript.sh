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

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Initial Checks
###############################################################################
__check_root__
__check_proxmox__

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
__info__ "Simulating an error scenario..."
sleep 2
__err__ "A simulated error has occurred!"

__info__ "Starting a simulated process..."
sleep 2
__update__ "Process is halfway..."
sleep 2
__ok__ "Process completed successfully."
