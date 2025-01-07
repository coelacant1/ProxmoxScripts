#!/bin/bash
#
# TestUtilityFunctions.sh
#
# A sample script to demonstrate usage of the various functions from UtilityFunctions.sh.
# It sources UtilityFunctions.sh, tests each utility function, and prints results.
#
# Usage:
#   1. Place this script in the same directory as UtilityFunctions.sh (or adjust the path).
#   2. Run it as root on a Proxmox node:
#       sudo ./TestUtilityFunctions.sh
#
# Note:
#   - This script may install packages if they are not already present (e.g., 'zip').
#   - At the end, it will prompt you whether to keep or remove any packages installed
#     during this session.
#

set -e

# Source the utility functions
source ./Utilities.sh

echo "=== Testing check_proxmox_and_root ==="
check_proxmox_and_root
echo "Success: We are root on a Proxmox node."

echo
echo "=== Testing install_or_prompt (example with 'zip') ==="
install_or_prompt "zip"
echo "Success: 'zip' is installed or user agreed to install it."

echo
echo "=== Testing get_remote_node_ips ==="
readarray -t REMOTE_NODES < <( get_remote_node_ips )
if [[ ${#REMOTE_NODES[@]} -gt 0 ]]; then
  echo "Remote node IPs: ${REMOTE_NODES[@]}"
else
  echo "No remote nodes found, or this node is not in a cluster."
fi

echo
echo "=== Testing check_cluster_membership ==="
# This will exit if not in a cluster.
# If the node is not in a cluster, comment this out to continue other tests.
check_cluster_membership
echo "Success: Node is in a cluster."

echo
echo "=== Testing IP conversion functions (ip_to_int and int_to_ip) ==="
EXAMPLE_IP="172.20.83.21"
IP_INT=$(ip_to_int "$EXAMPLE_IP")
echo "Converted $EXAMPLE_IP to integer: $IP_INT"

BACK_TO_IP=$(int_to_ip "$IP_INT")
echo "Converted integer $IP_INT back to IP: $BACK_TO_IP"

echo
echo "=== Testing get_cluster_lxc ==="
readarray -t CLUSTER_LXC < <( get_cluster_lxc )
if [[ ${#CLUSTER_LXC[@]} -gt 0 ]]; then
  echo "Cluster LXC VMIDs: ${CLUSTER_LXC[@]}"
else
  echo "No LXC containers found in the cluster."
fi

echo
echo "=== Testing get_server_lxc (on 'local' node) ==="
readarray -t LOCAL_LXC < <( get_server_lxc "local" )
if [[ ${#LOCAL_LXC[@]} -gt 0 ]]; then
  echo "Local LXC VMIDs: ${LOCAL_LXC[@]}"
else
  echo "No LXC containers found on local node."
fi

# You can also test specifying a particular hostname or IP if you have another node:
# readarray -t OTHER_NODE_LXC < <( get_server_lxc "172.20.83.22" )
# echo "Other node LXC VMIDs: ${OTHER_NODE_LXC[@]}"

echo
echo "=== Testing get_cluster_vms ==="
readarray -t CLUSTER_VMS < <( get_cluster_vms )
if [[ ${#CLUSTER_VMS[@]} -gt 0 ]]; then
  echo "Cluster VMIDs: ${CLUSTER_VMS[@]}"
else
  echo "No QEMU VMs found in the cluster."
fi

echo
echo "=== Testing get_server_vms (on 'local' node) ==="
readarray -t LOCAL_VMS < <( get_server_vms "local" )
if [[ ${#LOCAL_VMS[@]} -gt 0 ]]; then
  echo "Local VMIDs: ${LOCAL_VMS[@]}"
else
  echo "No QEMU VMs found on local node."
fi

# You can also test specifying a particular hostname or IP:
# readarray -t OTHER_NODE_VMS < <( get_server_vms "172.20.83.22" )
# echo "Other node VMIDs: ${OTHER_NODE_VMS[@]}"

echo
echo "=== Testing prompt_keep_installed_packages ==="
# This will prompt to remove any packages installed via install_or_prompt in this session.
prompt_keep_installed_packages

echo
echo "=== Test Script Complete ==="
