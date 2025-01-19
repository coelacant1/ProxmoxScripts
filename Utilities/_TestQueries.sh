#!/bin/bash
#
# _TestQueries.sh
#
# Usage:
# ./_TestQueries.sh
#
# A quick test script that sources "Queries.sh" and exercises
# some of its functions to demonstrate usage.
#
# 1) Source the Queries.sh script (assuming it's in the same directory).
#    Adjust the path if it's located elsewhere.
#

if [ -z "${UTILITYPATH}" ]; then
  # UTILITYPATH is unset or empty
  export UTILITYPATH="$(pwd)"
fi

source "${UTILITYPATH}/Queries.sh"


echo "==============================="
echo " TESTING: __check_cluster_membership__"
echo "==============================="
__check_cluster_membership__

echo
echo "==============================="
echo " TESTING: __get_number_of_cluster_nodes__"
echo "==============================="
NUM_NODES="$(__get_number_of_cluster_nodes__)"
echo "Cluster nodes detected: $NUM_NODES"

echo
echo "==============================="
echo " TESTING: __init_node_mappings__ and __get_ip_from_name__, __get_name_from_ip__"
echo "==============================="
__init_node_mappings__
echo "Initialization done. Checking a sample node name/IP..."


if [ -z "${NODE_NAME}" ]; then
read -rp "Enter node name: " NODE_NAME
fi

if [ -z "${NODE_IP}" ]; then
read -rp "Enter node IP: " NODE_IP
fi

# Example usage of node name and IP
echo "Manually checking your provided node name and IP via the node mapping:"
echo "Node '${NODE_NAME}' => IP: $(__get_ip_from_name__ "${NODE_NAME}")"
echo "IP   '${NODE_IP}'   => Node: $(__get_name_from_ip__ "${NODE_IP}")"

echo
echo "==============================="
echo " TESTING: __get_cluster_lxc__"
echo "==============================="
echo "All LXC containers in the cluster:"
readarray -t ALL_CLUSTER_LXC < <( __get_cluster_lxc__ )
printf '  %s\n' "${ALL_CLUSTER_LXC[@]}"

echo
echo "==============================="
echo " TESTING: __get_server_vms__ (QEMU) for 'local'"
echo "==============================="
echo "QEMU VMs on local server:"
readarray -t LOCAL_VMS < <( __get_server_vms__ "local" )
printf '  %s\n' "${LOCAL_VMS[@]}"

echo
echo "Done with tests."
exit 0
