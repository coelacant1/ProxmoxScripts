#!/bin/bash
#
# CreateHAGroup.sh
#
# This script creates a High Availability (HA) group in the Proxmox VE cluster
# and assigns the specified nodes to that group.
#
# Usage:
#   ./CreateHAGroup.sh <group_name> <node_name_1> [<node_name_2> ... <node_name_n>]
#
# Example:
#   # Creates a group named 'Primary' and adds nodes 'pve01' and 'pve02'
#   ./CreateHAGroup.sh Primary pve01 pve02
#
# Notes:
#   - You must be root or run via sudo.
#   - This script assumes you have a working Proxmox VE cluster.
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
    echo "Usage: ${0} <group_name> <node_name_1> [<node_name_2> ... <node_name_n>]"
    exit 1
fi

declare GROUP_NAME="$1"
shift
declare -a NODES=("$@")

# Convert the array of nodes into a comma-separated string
declare NODES_STRING
NODES_STRING="$(IFS=,; echo "${NODES[*]}")"

echo "Creating HA group: '${GROUP_NAME}' with the following node(s): '${NODES_STRING}'..."

if ! pvesh create /cluster/ha/groups \
       --group "${GROUP_NAME}" \
       --nodes "${NODES_STRING}" \
       --comment "HA group created by script"; then
    echo "Error: Failed to create HA group: '${GROUP_NAME}'"
    exit 1
fi

echo "HA group '${GROUP_NAME}' created successfully."
echo "=== HA group setup process completed! ==="

###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
