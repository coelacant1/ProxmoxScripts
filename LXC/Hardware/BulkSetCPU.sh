#!/bin/bash
#
# BulkSetCPU.sh
#
# This script sets the CPU type and core count for a range of LXC containers.
#
# Usage:
#   ./BulkSetCPU.sh <start_ct_id> <end_ct_id> <cpu_type> <core_count> [sockets]
#
# Example:
#   # Sets containers 400..402 to CPU type=host and 4 cores
#   ./BulkSetCPU.sh 400 402 host 4
#
#   # Sets containers 400..402 to CPU type=host, 4 cores, 2 sockets
#   ./BulkSetCPU.sh 400 402 host 4 2
#
# Notes:
#   - Must be run as root on a Proxmox node.
#   - 'pct' is required (part of the PVE/LXC utilities).
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# MAIN
###############################################################################
# --- Parse arguments -------------------------------------------------------
if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <start_ct_id> <end_ct_id> <cpu_type> <core_count> [sockets]"
  echo "Example:"
  echo "  $0 400 402 host 4"
  echo "  (Sets containers 400..402 to CPU type=host, 4 cores)"
  echo "  $0 400 402 host 4 2"
  echo "  (Sets containers 400..402 to CPU type=host, 4 cores, 2 sockets)"
  exit 1
fi

START_CT_ID="$1"
END_CT_ID="$2"
CPU_TYPE="$3"
CORE_COUNT="$4"
SOCKETS="${5:-1}"  # Default to 1 socket if not provided

# --- Basic checks ----------------------------------------------------------
__check_root__
__check_proxmox__
__check_cluster_membership__

# --- Display summary -------------------------------------------------------
echo "=== Starting CPU config update for containers from $START_CT_ID to $END_CT_ID ==="
echo " - CPU Type: \"$CPU_TYPE\""
echo " - Core Count: \"$CORE_COUNT\""
echo " - Sockets: \"$SOCKETS\""

# --- Main Loop -------------------------------------------------------------
for (( ctId=START_CT_ID; ctId<=END_CT_ID; ctId++ )); do
  if pct config "$ctId" &>/dev/null; then
    echo "Updating CPU for container \"$ctId\"..."
    if pct set "$ctId" -cpu "$CPU_TYPE" -cores "$CORE_COUNT" -sockets "$SOCKETS"; then
      echo " - Successfully updated CPU settings for CT \"$ctId\"."
    else
      echo " - Failed to update CPU settings for CT \"$ctId\"."
    fi
  else
    echo " - Container \"$ctId\" does not exist. Skipping."
  fi
done

echo "=== Bulk CPU config change process complete! ==="
