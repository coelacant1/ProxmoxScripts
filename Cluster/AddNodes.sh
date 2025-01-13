#!/bin/bash
#
# AddMultipleNodes.sh
#
# A script to add multiple new Proxmox nodes to an existing cluster. Run this
# script **on an existing cluster node** that is already part of the cluster.
#
# Usage:
#   ./AddMultipleNodes.sh <CLUSTER_IP> <NEW_NODE_1> [<NEW_NODE_2> ...] [--link1 <LINK1_ADDR_1> [<LINK1_ADDR_2> ...]]
#
# Example 1 (no link1):
#   ./AddMultipleNodes.sh 172.20.120.65 172.20.120.66 172.20.120.67
#
# Example 2 (with link1):
#   ./AddMultipleNodes.sh 172.20.120.65 172.20.120.66 172.20.120.67 --link1 10.10.10.66 10.10.10.67
#
# Explanation:
#   - <CLUSTER_IP>   : The main IP of the cluster (the IP that new nodes should join).
#   - <NEW_NODE_*>   : One or more new node IPs to be added to the cluster.
#   - --link1        : Optional flag indicating you want to configure a second link.
#                      The number of addresses after --link1 must match the number
#                      of new nodes specified.
#
# How it works:
#   1) Prompts for the 'root' SSH password for each NEW node (not the cluster).
#   2) SSHes into each new node and runs 'pvecm add <CLUSTER_IP>' with --link0 set to
#      that node's IP, and optionally --link1 if you've provided link1 addresses.
#   3) Uses an embedded 'expect' script to pass the password automatically. 
#      The password is never echoed to the terminal.
#

set +e

source "$UTILITIES"

###############################################################################
# Preliminary Checks
###############################################################################
check_root              # Ensure we're running as root
check_proxmox           # Ensure we're on a valid Proxmox node
check_cluster_membership     # Ensure this node is part of a cluster

###############################################################################
# Argument Parsing
###############################################################################
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <CLUSTER_IP> <NEW_NODE_1> [<NEW_NODE_2> ...] [--link1 <LINK1_1> <LINK1_2> ...]"
  exit 1
fi

CLUSTER_IP="$1"
shift

declare -a NODES=()
USE_LINK1=false
declare -a LINK1=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --link1)
      USE_LINK1=true
      shift
      break
      ;;
    *)
      NODES+=("$1")
      shift
      ;;
  esac
done

if $USE_LINK1; then
  if [[ $# -lt ${#NODES[@]} ]]; then
    echo "Error: You specified --link1 but did not provide enough addresses."
    echo "       You have ${#NODES[@]} new node(s), so you need at least ${#NODES[@]} link1 address(es)."
    exit 1
  fi
  for ((i=0; i<${#NODES[@]}; i++)); do
    LINK1+=("$1")
    shift
  done
fi

echo "DEBUG: CLUSTER_IP = '$CLUSTER_IP'"
echo "DEBUG: NODES = ${NODES[*]}"

###############################################################################
# Main Logic
###############################################################################

COUNTER=0
for NODE_IP in "${NODES[@]}"; do
  echo "-----------------------------------------------------------------"
  echo "Adding new node: \"$NODE_IP\""

  CMD="pvecm add \"$CLUSTER_IP\" --link0 \"$NODE_IP\""
  if [ "$USE_LINK1" = "true" ]; then
    CMD+=" --link1 \"${LINK1[$COUNTER]}\""
    echo "  Using link1: \"${LINK1[$COUNTER]}\""
  fi

  echo "  SSHing into \"$NODE_IP\" and executing: $CMD"
  
  (ssh -t -o StrictHostKeyChecking=no root@${NODE_IP} $CMD) || true
  
  COUNTER=$((COUNTER + 1))
  echo "Node \"$NODE_IP\" add procedure completed."
  echo
done

echo "=== All new nodes have been processed. ==="
echo "You can verify cluster status on each node by running: pvecm status"
echo "Or from this cluster node, check: pvecm status"


###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
