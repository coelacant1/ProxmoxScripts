#!/bin/bash
#
# FindMacAddress.sh
#
# This script retrieves the network configuration details for all virtual machines (VMs) across
# all nodes in a Proxmox cluster. It outputs the MAC addresses associated with each VM, helping
# in network configuration audits or inventory management.
#
# Usage:
#   ./FindMacAddress.sh
#
# Example:
#   # Simply run this script on a Proxmox host within a cluster
#   ./FindMacAddress.sh
#
# The script uses 'pvesh' to fetch JSON data and parses it with 'jq'.
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Pre-flight checks
###############################################################################
__check_root__
__check_proxmox__
__install_or_prompt__ "jq"
__check_cluster_membership__

###############################################################################
# Main Logic
###############################################################################
nodes="$(pvesh get /nodes --output-format=json | jq -r '.[] | .node')"

for node in $nodes; do
  echo "Checking node: \"$node\""
  vmIds="$(pvesh get /nodes/"$node"/qemu --output-format=json | jq -r '.[] | .vmid')"
  
  for vmId in $vmIds; do
    echo "VMID: \"$vmId\" on Node: \"$node\""
    pvesh get /nodes/"$node"/qemu/"$vmId"/config \
      | grep -i 'net' \
      | grep -i 'macaddr'
  done
done
