#!/bin/bash
#
# StartStoppedOSDs.sh
#
# This script starts all stopped Ceph OSDs in a Proxmox VE environment.
#
# Usage:
#   ./StartStoppedOSDs.sh
#
# This script:
#  - Checks for root privileges.
#  - Verifies it is running in a Proxmox environment.
#  - Checks or installs the 'ceph' package if needed.
#  - Lists all OSDs that are down and attempts to start them.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Main Logic
###############################################################################
STOPPED_OSDS="$(ceph osd tree | awk '/down/ {print $4}')"

if [ -z "$STOPPED_OSDS" ]; then
  echo "No OSD is reported as down. Exiting."
  exit 0
fi

for osdId in $STOPPED_OSDS; do
  echo "Starting OSD ID: $osdId"
  ceph osd start "osd.${osdId}"
  if [ $? -eq 0 ]; then
    echo " - OSD ID: $osdId started successfully."
  else
    echo " - Failed to start OSD ID: $osdId."
  fi
done

echo "OSD start process completed!"
