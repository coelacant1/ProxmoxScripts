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
#     this script from (apt-get install expect).

set -e

# --- Ensure we are root on the cluster node ---------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (sudo) on the cluster node."
  exit 1
fi

# --- Parse and validate arguments -------------------------------------------
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
    echo "You have ${#NODES[@]} new nodes, so you need at least ${#NODES[@]} link1 addresses."
    exit 1
  fi
  for ((i=0; i<${#NODES[@]}; i++)); do
    LINK1+=("$1")
    shift
  done
fi

# --- Prompt once for the new nodes' root password ---------------------------
# This password is used to SSH into each new node and run 'pvecm add'.
echo -n "Enter the 'root' SSH password for the NEW node(s): "
# -s => silent, -r => raw input (no escape sequences processed)
read -s NODE_PASSWORD
echo

# --- Preliminary Checks on cluster side -------------------------------------
if ! command -v pvecm >/dev/null 2>&1; then
  echo "Error: 'pvecm' not found on this cluster node. Are you sure this is a Proxmox cluster node?"
  exit 2
fi

if ! command -v expect >/dev/null 2>&1; then
  echo "Error: 'expect' is required to supply passwords automatically. Please install it:"
  echo "       apt-get update && apt-get install -y expect"
  exit 3
fi

# --- Add each node to the cluster -------------------------------------------
COUNTER=0
for NODE_IP in "${NODES[@]}"; do
  echo "------------------------------------------------------------"
  echo "Adding new node: $NODE_IP"
  
  # Build the 'pvecm add' command to run on the NEW node
  #    pvecm add <CLUSTER_IP> --link0 <NODE_IP> [--link1 <LINK1_IP>]
  CMD="pvecm add $CLUSTER_IP --link0 $NODE_IP"
  if $USE_LINK1; then
    CMD+=" --link1 ${LINK1[$COUNTER]}"
    echo "  Using link1: ${LINK1[$COUNTER]}"
  fi

  # Use an inline expect script to SSH and run the command on the new node.
  # This will prompt for the 'root' password of the new node, which we supply.
  echo "  SSHing into $NODE_IP and executing: $CMD"
  
  /usr/bin/expect <<EOF
    set timeout -1
    # Do not echo expect commands to screen
    log_user 0

    spawn ssh -o StrictHostKeyChecking=no root@${NODE_IP} "$CMD"
    
    # If first connection, we might see "Are you sure you want to continue connecting?"
    expect {
      -re ".*continue connecting.*" {
        send "yes\r"
        exp_continue
      }
      # Now expect password prompt
      -re ".*assword:.*" {
        send "${NODE_PASSWORD}\r"
      }
    }

    # Once we send the password, let's allow the command to fully run
    # until we see either an EOF or a pvecm success message
    expect {
      eof
    }
EOF

  # Increment the node count
  ((COUNTER++))

  echo "Node $NODE_IP add procedure completed (check for any errors above)."
  echo
done

echo "=== All nodes processed. ==="
echo "You can verify cluster status for each node by logging into it and running:"
echo "  pvecm status"
echo "Or from this cluster node, you can check:
  pvecm status
"
