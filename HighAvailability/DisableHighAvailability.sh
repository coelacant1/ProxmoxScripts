#!/bin/bash
#
# DisableHAOnNode.sh
#
# This script disables High Availability (HA) on a single Proxmox node by:
#   1. Disabling or removing any HA resources tied to this node.
#   2. Stopping and disabling the HA services (pve-ha-crm, pve-ha-lrm) on the node.
#
# Usage:
#   ./DisableHAOnNode.sh <node_name>
#
# Example:
#   ./DisableHAOnNode.sh pve-node2
#
# Notes:
#   - If you're using a multi-node cluster, ensure that no critical HA resources rely on this node.
#   - A single-node "cluster" does not benefit from HA, so this script effectively cleans up HA configs.
#   - This script expects passwordless SSH or valid root credentials for the target node.
#   - You must run this script as root on a Proxmox node that is part of the same cluster as <node_name>.
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# MAIN
###############################################################################

# 1. Validate input
if [[ -z "$1" ]]; then
  echo "Usage: $0 <node_name>"
  echo "Example: $0 pve-node2"
  exit 1
fi

targetNodeName="$1"

# 2. Basic checks
__check_root__
__check_proxmox__
__check_cluster_membership__

# 3. Ensure 'jq' is installed (not included by default in Proxmox 8)
__install_or_prompt__ "jq"

echo "=== Disabling HA on node: \"$targetNodeName\" ==="

# 4. Convert node name to IP for SSH calls
echo "=== Resolving IP address for node \"$targetNodeName\" ==="
declare nodeIp
if ! nodeIp="$(__get_ip_from_name__ "$targetNodeName")"; then
  echo "Error: Could not resolve node name \"$targetNodeName\" to an IP."
  exit 1
fi
echo " - Node \"$targetNodeName\" resolved to IP: \"$nodeIp\""
echo

# 5. Identify HA resources referencing this node by name
echo "=== Checking for HA resources on node \"$targetNodeName\"... ==="

haResources="$(pvesh get /cluster/ha/resources --output-format json \
              | jq -r '.[] | select(.statePath | contains("'"$targetNodeName"'")) | .sid')"

if [[ -z "$haResources" ]]; then
  echo " - No HA resources found referencing node \"$targetNodeName\"."
else
  echo " - Found HA resources referencing node \"$targetNodeName\":"
  echo "$haResources"
  echo

  # Remove these HA resources
  declare res
  for res in $haResources; do
    echo "Removing HA resource \"$res\" ..."
    if pvesh delete "/cluster/ha/resources/${res}"; then
      echo " - Successfully removed HA resource: \"$res\""
    else
      echo " - Failed to remove HA resource: \"$res\""
    fi
    echo
  done
fi

# 6. Stop and disable HA services on the target node
echo "=== Stopping and disabling HA services on node \"$targetNodeName\" ==="
echo "Stopping pve-ha-crm and pve-ha-lrm on IP: \"$nodeIp\" ..."
ssh "root@${nodeIp}" "systemctl stop pve-ha-crm pve-ha-lrm"

echo "Disabling pve-ha-crm and pve-ha-lrm on IP: \"$nodeIp\" ..."
ssh "root@${nodeIp}" "systemctl disable pve-ha-crm pve-ha-lrm"

echo "=== HA has been disabled on node: \"$targetNodeName\" (IP: \"$nodeIp\") ==="
echo "You can verify via: ssh root@${nodeIp} 'systemctl status pve-ha-crm pve-ha-lrm'"
echo

# 7. Prompt to remove any packages installed during this session
__prompt_keep_installed_packages__
