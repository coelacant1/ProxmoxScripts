#!/bin/bash
#
# AddResourcesToHAGroup.sh
#
# This script adds LXC containers or VMs (found anywhere in the cluster) to a
# specified High Availability (HA) group in a Proxmox VE cluster.
#
# Usage:
#   ./AddResourcesToHAGroup.sh <group_name> <resource_id_1> [<resource_id_2> ... <resource_id_n>]
#
# Example:
#   # Adds VM/LXC IDs 100, 101, and 200 to the 'Primary' HA group
#   # even if they are located on different nodes
#   ./AddResourcesToHAGroup.sh Primary 100 101 200
#
# Notes:
#   - You must be root or run via sudo.
#   - This script assumes you have a working Proxmox VE cluster.
#   - Group names must not be purely numeric (e.g., '123').
#   - The script relies on utility functions that must be sourced elsewhere.
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# MAIN
###############################################################################

__check_root__
__check_proxmox__
__check_cluster_membership__

if [[ "$#" -lt 2 ]]; then
    echo "Usage: \"$0\" <group_name> <resource_id_1> [<resource_id_2> ... <resource_id_n>]"
    exit 1
fi

declare GROUP_NAME="$1"
shift
declare -a RESOURCE_IDS=("$@")

# Make sure the group name is not purely numeric,
# because Proxmox HA groups cannot be numeric only.
if [[ "$GROUP_NAME" =~ ^[0-9]+$ ]]; then
    echo "Error: The group name \"${GROUP_NAME}\" is invalid; it cannot be purely numeric."
    exit 1
fi

# Gather all LXC and VM IDs across the entire cluster
readarray -t ALL_CLUSTER_LXC < <( __get_cluster_lxc__ )
readarray -t ALL_CLUSTER_VMS < <( __get_cluster_vms__ )

for resourceId in "${RESOURCE_IDS[@]}"; do
    # Determine if this resource ID belongs to an LXC or a VM
    if [[ " ${ALL_CLUSTER_LXC[*]} " == *" ${resourceId} "* ]]; then
        resourceType="ct"
    elif [[ " ${ALL_CLUSTER_VMS[*]} " == *" ${resourceId} "* ]]; then
        resourceType="vm"
    else
        echo "Error: Resource ID \"${resourceId}\" not found in the cluster as a VM or LXC container."
        continue
    fi

    echo "Adding resource \"${resourceType}:${resourceId}\" to HA group \"${GROUP_NAME}\"..."
    if pvesh create /cluster/ha/resources --sid "${resourceType}:${resourceId}" --group "${GROUP_NAME}"; then
        echo " - Successfully added \"${resourceType}:${resourceId}\" to HA group \"${GROUP_NAME}\"."
    else
        echo " - Failed to add \"${resourceType}:${resourceId}\" to HA group \"${GROUP_NAME}\"."
    fi
done

echo "=== HA resource addition process completed! ==="

###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
