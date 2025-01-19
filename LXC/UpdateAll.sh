#!/bin/bash
#
# UpdateAll.sh
#
# A script to apply package updates to all Linux containers (LXC) on every host
# in a Proxmox cluster. Requires root privileges and passwordless SSH between nodes.
#
# Usage:
#   ./UpdateAll.sh
#
# Example:
#   ./UpdateAll.sh
#
# Description:
#   1. Checks if this script is run as root (__check_root__).
#   2. Verifies this node is a Proxmox node (__check_proxmox__).
#   3. Installs 'ssh' if missing (__install_or_prompt__ "ssh").
#   4. Ensures the node is part of a Proxmox cluster (__check_cluster_membership__).
#   5. Finds the local node IP and remote node IPs.
#   6. Iterates over all nodes (local + remote), enumerates their LXC containers,
#      and applies package updates inside each container.
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Preliminary Checks via Utilities
###############################################################################
__check_root__
__check_proxmox__
__check_cluster_membership__

###############################################################################
# Gather Node IP Addresses
###############################################################################
LOCAL_NODE_IP="$(hostname -I | awk '{print $1}')"

# Gather remote node IPs (excludes the local node)
readarray -t REMOTE_NODE_IPS < <( __get_remote_node_ips__ )

# Combine local + remote IPs
ALL_NODE_IPS=("$LOCAL_NODE_IP" "${REMOTE_NODE_IPS[@]}")

###############################################################################
# Main Script Logic
###############################################################################
echo "Updating LXC containers on all nodes in the cluster..."

# Iterate over all node IPs
for nodeIp in "${ALL_NODE_IPS[@]}"; do
  echo "--------------------------------------------------"
  echo "Processing LXC containers on node: \"${nodeIp}\""

  # 'pct list' header is removed by tail -n +2
  containers="$(ssh "root@${nodeIp}" "pct list | tail -n +2 | awk '{print \$1}'" 2>/dev/null)"

  if [[ -z "$containers" ]]; then
    echo "  No LXC containers found on \"${nodeIp}\""
    continue
  fi

  # Update each container
  while read -r containerId; do
    [[ -z "$containerId" ]] && continue
    echo "  Updating container CTID: \"${containerId}\" on node \"${nodeIp}\"..."
    if ssh "root@${nodeIp}" "pct exec ${containerId} -- apt-get update && apt-get upgrade -y"; then
      echo "    Update complete for CTID: \"${containerId}\""
    else
      echo "    Update failed for CTID: \"${containerId}\""
    fi
  done <<< "$containers"
done

echo "All LXC containers have been updated across the cluster."
