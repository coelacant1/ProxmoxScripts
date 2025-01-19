#!/bin/bash
#
# BulkClone.sh
#
# This script automates the process of cloning LXC containers within a Proxmox VE environment. 
# It clones a source LXC container into a specified number of new containers, assigning them 
# unique IDs, names based on a user-provided base name, and sets static IP addresses. 
# Adding cloned containers to a designated pool is optional. 
#
# Usage:
#   ./BulkClone.sh <source_ct_id> <base_ct_name> <start_ct_id> <num_cts> <start_ip/cidr> <bridge> [gateway] [pool_name]
#
# Arguments:
#   source_ct_id - The ID of the LXC container that will be cloned.
#   base_ct_name - The base name for the new containers, which will be appended with a numerical index.
#   start_ct_id  - The starting container ID for the first clone.
#   num_cts       - The number of containers to clone.
#   start_ip/cidr - The new IP address and subnet mask of the container (e.g., 192.168.1.50/24).
#   bridge        - The bridge to be used for the network configuration.
#   gateway       - Optional. The gateway for the IP configuration (e.g., 192.168.1.1).
#   pool_name     - Optional. The name of the pool to which the new containers will be added. 
#                   If not provided, containers are not added to any pool.
#
# Examples:
#   # Clones container 110, creating 30 new containers with IPs starting at 192.168.1.50/24 on vmbr0, 
#   # gateway 192.168.1.1, and assigns them to a pool named 'PoolName'.
#   ./BulkClone.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0 192.168.1.1 PoolName
#
#   # Same as above but without specifying a gateway or pool.
#   ./BulkClone.sh 110 Ubuntu-2C-20GB 400 30 192.168.1.50/24 vmbr0
#

source "${UTILITYPATH}/Conversion.sh"
source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Argument Parsing
###############################################################################
if [ "$#" -lt 6 ]; then
  echo "Error: Not enough arguments."
  echo "Usage: $0 <source_ct_id> <base_ct_name> <start_ct_id> <num_cts> <start_ip/cidr> <bridge> [gateway] [pool_name]"
  exit 1
fi

SOURCE_CT_ID="$1"
BASE_CT_NAME="$2"
START_CT_ID="$3"
NUM_CTS="$4"
START_IP_CIDR="$5"
BRIDGE="$6"
GATEWAY="${7:-}"
POOL_NAME="${8:-}"

###############################################################################
# Main
###############################################################################
IFS='/' read -r startIp subnetMask <<< "${START_IP_CIDR}"
startIpInt="$( __ip_to_int__ "${startIp}" )"

for (( i=0; i<NUM_CTS; i++ )); do
  targetCtId=$((START_CT_ID + i))
  nameIndex=$((i + 1))
  ctName="${BASE_CT_NAME}${nameIndex}"

  currentIpInt=$((startIpInt + i))
  newIp="$( __int_to_ip__ "${currentIpInt}" )"

  pct clone "${SOURCE_CT_ID}" "${targetCtId}" --hostname "${ctName}"
  pct set "${targetCtId}" -net0 "name=eth0,bridge=${BRIDGE},ip=${newIp}/${subnetMask},gw=${GATEWAY}"

  if [ -n "${POOL_NAME}" ]; then
    pct set "${targetCtId}" --pool "${POOL_NAME}"
  fi
done

echo "Cloning completed!"
