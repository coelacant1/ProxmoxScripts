#!/bin/bash
#
# DisableHAClusterWide.sh
#
# This script disables High Availability (HA) cluster-wide by:
#   1. Removing all HA resources found in the cluster (pvesh /cluster/ha/resources).
#   2. Stopping and disabling the HA services (pve-ha-crm and pve-ha-lrm) on every node.
#
# Usage:
#   ./DisableHAClusterWide.sh
#
# Example:
#   ./DisableHAClusterWide.sh
#
# Notes:
#   - This script can only run on a Proxmox node that is part of a cluster.
#   - This script expects passwordless SSH or valid root credentials for all nodes.
#   - Once completed, no node in the cluster will run HA services, and no HA
#     resource definitions will remain.
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# MAIN
###############################################################################

# 0. Basic checks
__check_root__
__check_proxmox__
__check_cluster_membership__

# 1. Ensure required commands are installed
# 'jq' is not installed by default on Proxmox 8
__install_or_prompt__ "jq"

echo "=== Disabling HA on the entire cluster ==="

# 2. Retrieve and remove all HA resources from the cluster
echo "=== Retrieving all HA resources ==="
ALL_RESOURCES="$(pvesh get /cluster/ha/resources --output-format json | jq -r '.[].sid')"

if [[ -z "${ALL_RESOURCES}" ]]; then
  echo " - No HA resources found in the cluster."
else
  echo " - The following HA resources will be removed:"
  echo "${ALL_RESOURCES}"
  echo

  for RES in ${ALL_RESOURCES}; do
    echo "Removing HA resource: ${RES} ..."
    if pvesh delete "/cluster/ha/resources/${RES}"; then
      echo " - Successfully removed: ${RES}"
    else
      echo " - Failed to remove: ${RES}"
    fi
    echo
  done
fi

# 3. Stop and disable HA services on every node in the cluster using IPs
echo "=== Disabling HA services (CRM, LRM) on all nodes ==="
readarray -t REMOTE_NODE_IPS < <( __get_remote_node_ips__ )

for NODE_IP in "${REMOTE_NODE_IPS[@]}"; do
  echo " - Processing node with IP: ${NODE_IP}"
  echo "   Stopping pve-ha-crm and pve-ha-lrm..."
  ssh "root@${NODE_IP}" "systemctl stop pve-ha-crm pve-ha-lrm"

  echo "   Disabling pve-ha-crm and pve-ha-lrm on startup..."
  ssh "root@${NODE_IP}" "systemctl disable pve-ha-crm pve-ha-lrm"

  echo "   Done for node: ${NODE_IP}"
  echo
done

echo "=== HA has been disabled on all nodes in the cluster. ==="
echo "No HA resources remain, and HA services are stopped & disabled cluster-wide."

# 4. Prompt to remove any packages installed during this session
__prompt_keep_installed_packages__
