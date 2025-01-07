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
#   3) Because it needs a password, we use an embedded 'expect' script to pass the
#      password automatically (only once entered by you). The password is never
#      echoed to the terminal.
#
# Requirements:
#   - The 'expect' package must be installed on the cluster node you're running
#     this script from (handled by install_or_prompt "expect" below).
#

set -e

# ---------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# ---------------------------------------------------------------------------
find_utilities_script() {
  # Check current directory first
  if [[ -d "./Utilities" ]]; then
    echo "./Utilities/Utilities.sh"
    return 0
  fi

  local rel_path=""
  for _ in {1..15}; do
    cd ..
    # If rel_path is empty, set it to '..' else prepend '../'
    if [[ -z "$rel_path" ]]; then
      rel_path=".."
    else
      rel_path="../$rel_path"
    fi

    if [[ -d "./Utilities" ]]; then
      echo "$rel_path/Utilities/Utilities.sh"
      return 0
    fi
  done

  echo "Error: Could not find 'Utilities' folder within 15 levels." >&2
  return 1
}

###############################################################################
# Locate and source the Utilities script
###############################################################################
UTILITIES_DIR="$(find_utilities_script)"
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# Preliminary Checks via Utilities
###############################################################################
check_proxmox_and_root         # Ensure we're root on a valid Proxmox node
install_or_prompt "expect"     # Required for automated password entry
check_cluster_membership       # Ensure this node is part of a cluster

# Prompt at script exit to optionally remove any newly installed packages
trap prompt_keep_installed_packages EXIT

###############################################################################
# Argument Parsing
###############################################################################
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <CLUSTER_IP> <NEW_NODE_1> [<NEW_NODE_2> ...] [--link1 <LINK1_1> <LINK1_2> ...]"
  exit 1
fi

CLUSTER_IP="$1"
shift

NODES=()
USE_LINK1=false
LINK1=()

# Collect new node IPs until we hit '--link1' or run out of args
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

# If user specified --link1, parse that many link1 addresses
if $USE_LINK1; then
  if [[ $# -lt ${#NODES[@]} ]]; then
    echo "Error: You specified --link1 but not enough link1 addresses for each node."
    echo "       You have ${#NODES[@]} new nodes, so you need at least ${#NODES[@]} link1 addresses."
    exit 1
  fi
  for ((i=0; i<${#NODES[@]}; i++)); do
    LINK1+=("$1")
    shift
  done
fi

###############################################################################
# Prompt for New Nodes' Root Password
###############################################################################
# This password is used to SSH into each new node and run 'pvecm add'.
echo -n "Enter the 'root' SSH password for the NEW node(s): "
read -s NODE_PASSWORD
echo

###############################################################################
# Main Logic
###############################################################################
COUNTER=0
for NODE_IP in "${NODES[@]}"; do
  echo "-----------------------------------------------------------------"
  echo "Adding new node: $NODE_IP"

  # Build the 'pvecm add' command to run on the NEW node:
  #   pvecm add <CLUSTER_IP> --link0 <NODE_IP> [--link1 <LINK1_IP>]
  CMD="pvecm add ${CLUSTER_IP} --link0 ${NODE_IP}"
  if $USE_LINK1; then
    CMD+=" --link1 ${LINK1[$COUNTER]}"
    echo "  Using link1: ${LINK1[$COUNTER]}"
  fi

  echo "  SSHing into $NODE_IP and executing: $CMD"
  
  /usr/bin/expect <<EOF
    set timeout -1
    log_user 0

    spawn ssh -o StrictHostKeyChecking=no root@${NODE_IP} "$CMD"

    expect {
      -re ".*continue connecting.*" {
        send "yes\r"
        exp_continue
      }
      -re ".*assword:.*" {
        send "${NODE_PASSWORD}\r"
      }
    }

    expect {
      eof
    }
EOF

  ((COUNTER++))
  echo "Node $NODE_IP add procedure completed."
  echo
done

echo "=== All new nodes have been processed. ==="
echo "You can verify cluster status on each node by running: pvecm status"
echo "Or from this cluster node, check: pvecm status"
