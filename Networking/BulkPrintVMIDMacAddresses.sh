#!/bin/bash
#
# This script retrieves the network configuration details for all virtual machines (VMs) across all nodes in a Proxmox cluster.
# It outputs the MAC addresses associated with each VM, helping in network configuration audits or inventory management.
# The script utilizes the Proxmox VE command-line tool pvesh to fetch information in JSON format and parses it using jq.
#
# Usage:
# Simply run this script on a Proxmox cluster host that has permissions to access the Proxmox VE API:
# ./BulkPrintVMIDMacAddresses.sh
#

# Source utility scripts (adjust UTILITYPATH as needed)
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Pre-flight checks
###############################################################################
check_root
check_proxmox
install_or_prompt "jq"
check_cluster_membership

# Print header for CSV output
echo "Nodename, CTID/VMID, VM or CT, Mac Address"

###############################################################################
# Main Logic: Iterate locally through /etc/pve/nodes/<node>/qemu-server and /lxc
###############################################################################

# Loop over each node directory in /etc/pve/nodes
for nodeDir in /etc/pve/nodes/*; do
  if [ -d "$nodeDir" ]; then
    nodeName=$(basename "$nodeDir")
    
    # Process QEMU virtual machine configuration files
    qemuDir="$nodeDir/qemu-server"
    if [ -d "$qemuDir" ]; then
      for configFile in "$qemuDir"/*.conf; do
        if [ -f "$configFile" ]; then
          vmid=$(basename "$configFile" .conf)
          # Look for lines starting with "net" and extract MAC addresses (format: XX:XX:XX:XX:XX:XX)
          macs=$(grep -E '^net[0-9]+:' "$configFile" \
                  | grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' \
                  | tr '\n' ' ' \
                  | sed 's/ *$//')
          [ -z "$macs" ] && macs="None"
          echo "$nodeName, $vmid, VM, $macs"
        fi
      done
    fi

    # Process LXC container configuration files
    lxcDir="$nodeDir/lxc"
    if [ -d "$lxcDir" ]; then
      for configFile in "$lxcDir"/*.conf; do
        if [ -f "$configFile" ]; then
          ctid=$(basename "$configFile" .conf)
          macs=$(grep -E '^net[0-9]+:' "$configFile" \
                  | grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' \
                  | tr '\n' ' ' \
                  | sed 's/ *$//')
          [ -z "$macs" ] && macs="None"
          echo "$nodeName, $ctid, CT, $macs"
        fi
      done
    fi

  fi
done