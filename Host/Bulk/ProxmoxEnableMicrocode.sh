#!/bin/bash
#
# ProxmoxEnableMicrocode.sh
#
# This script enables microcode updates for all nodes in a Proxmox VE cluster.
#
# Usage:
#   ./ProxmoxEnableMicrocode.sh
#
# Example:
#   ./ProxmoxEnableMicrocode.sh
#
# Description:
#   1. Checks prerequisites (root privileges, Proxmox environment, cluster membership).
#   2. Installs microcode packages on each node (remote + local).
#   3. Prompts to keep or remove installed packages afterward.
#
# Function Index:
#   - enable_microcode
#

source "$UTILITIES"

###############################################################################
# Preliminary Checks
###############################################################################
check_root
check_proxmox
check_cluster_membership

###############################################################################
# Function to enable microcode updates
###############################################################################
enable_microcode() {
    echo "Enabling microcode updates on node: $(hostname)"
    apt-get update
    apt-get install -y intel-microcode amd64-microcode
    echo " - Microcode updates enabled."
}

###############################################################################
# Main Script Logic
###############################################################################
echo "Gathering remote node IPs..."
readarray -t REMOTE_NODES < <( get_remote_node_ips )

if [[ "${#REMOTE_NODES[@]}" -eq 0 ]]; then
    echo " - No remote nodes detected; this might be a single-node cluster."
fi

for nodeIp in "${REMOTE_NODES[@]}"; do
    echo "Connecting to node: \"${nodeIp}\""
    ssh root@"${nodeIp}" "$(declare -f enable_microcode); enable_microcode"
    echo " - Microcode update completed for node: \"${nodeIp}\""
    echo
done

enable_microcode
echo "Microcode updates enabled on the local node."

###############################################################################
# Cleanup Prompt
###############################################################################
prompt_keep_installed_packages

echo "Microcode updates have been enabled on all nodes!"


###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
