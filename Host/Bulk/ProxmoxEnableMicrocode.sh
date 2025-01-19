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

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Preliminary Checks
###############################################################################
__check_root__
__check_proxmox__
__check_cluster_membership__

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
readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )

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
__prompt_keep_installed_packages__

echo "Microcode updates have been enabled on all nodes!"


###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
