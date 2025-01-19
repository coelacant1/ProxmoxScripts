#!/bin/bash
#
# OnlineMemoryTest.sh
#
# A script to perform an in-memory RAM test on a running Proxmox server without fully shutting down.
# Uses the 'memtester' utility to allocate and test a portion of system memory in gigabytes.
#
# Usage:
#   ./OnlineMemoryTest.sh <size-in-GB>
#
# Examples:
#   ./OnlineMemoryTest.sh 1
#       This command tests 1GB (1024MB) of RAM in a running system.
#
#   ./OnlineMemoryTest.sh 2
#       This command tests 2GB (2048MB) of RAM in a running system.
#
# Note:
#   - Running this script may temporarily reduce available memory for other processes.
#   - For best results, stop or pause non-critical workloads before testing.
#   - This script MUST be run as root and on a Proxmox host.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__

if [[ $# -lt 1 ]]; then
  echo "Error: Missing <size-in-GB> argument."
  echo "Usage: $0 <size-in-GB>"
  exit 1
fi

TEST_SIZE_GB="$1"
re='^[0-9]+$'
if ! [[ "$TEST_SIZE_GB" =~ $re ]]; then
  echo "Error: <size-in-GB> must be a positive integer."
  exit 2
fi

TEST_SIZE_MB=$(( TEST_SIZE_GB * 1024 ))

###############################################################################
# Check for and Possibly Install 'memtester'
###############################################################################
__install_or_prompt__ "memtester"

###############################################################################
# Main Script Logic
###############################################################################
echo "Starting in-memory test for \"${TEST_SIZE_MB}MB\" (\"${TEST_SIZE_GB}GB\")..."
memtester "${TEST_SIZE_MB}M" 1
echo "Memory test completed. Check output above for any errors or failures."

###############################################################################
# Prompt to Keep or Remove Installed Packages
###############################################################################
__prompt_keep_installed_packages__

exit 0
