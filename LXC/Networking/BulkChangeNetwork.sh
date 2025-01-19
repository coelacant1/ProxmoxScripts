#!/bin/bash
#
# BulkChangeNetwork.sh
#
# This script changes the network interface for a range of LXC containers in Proxmox.
# Typically, this means changing the bridge (e.g., vmbr0 -> vmbr1) and/or the interface name (eth0 -> eth1).
#
# Usage:
#   ./BulkChangeNetwork.sh <start_ct_id> <end_ct_id> <bridge> [interface_name]
#
# Example usage:
#   # This changes containers 400..402 to use net0 => name=eth1,bridge=vmbr1
#   ./BulkChangeNetwork.sh 400 402 vmbr1 eth1
#
#   # This changes containers 400..402 to use net0 => name=eth0,bridge=vmbr1 (default eth0)
#   ./BulkChangeNetwork.sh 400 402 vmbr1
#
# Further explanation:
#   The script takes a starting container ID, an ending container ID, the new bridge name,
#   and optionally a new interface name (defaults to eth0). It loops over the specified range
#   and sets 'net0' with the new configuration if the container exists.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Ensure script is run as root and on a Proxmox node
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Argument Parsing
###############################################################################
if [ $# -lt 3 ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <start_ct_id> <end_ct_id> <bridge> [interface_name]"
  exit 1
fi

START_CT_ID="$1"
END_CT_ID="$2"
BRIDGE="$3"
IF_NAME="${4:-eth0}"

if [[ "${END_CT_ID}" -lt "${START_CT_ID}" ]]; then
  echo "Error: end_ct_id must be greater than or equal to start_ct_id."
  exit 1
fi

###############################################################################
# Main Logic
###############################################################################
echo "=== Starting network interface update ==="
echo " - Container range: \"${START_CT_ID}\" to \"${END_CT_ID}\""
echo " - New bridge: \"${BRIDGE}\""
echo " - Interface name: \"${IF_NAME}\""

for (( ctId="${START_CT_ID}"; ctId<="${END_CT_ID}"; ctId++ )); do
  if pct config "${ctId}" &>/dev/null; then
    echo "Updating network interface for container \"${ctId}\"..."
    pct set "${ctId}" -net0 "name=${IF_NAME},bridge=${BRIDGE}"
    if [ $? -eq 0 ]; then
      echo " - Successfully updated CT \"${ctId}\"."
    else
      echo " - Failed to update CT \"${ctId}\"."
    fi
  else
    echo " - Container \"${ctId}\" does not exist. Skipping."
  fi
done

echo "=== Bulk interface change process complete! ==="
