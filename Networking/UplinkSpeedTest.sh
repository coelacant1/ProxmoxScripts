#!/bin/bash
#
# UplinkSpeedTest.sh
#
# A script to check internet speed on a Proxmox node (local)
# or sequentially across all nodes in the cluster, then report the results.
#
# Usage:
#   ./UplinkSpeedTest.sh [all|<node1> <node2> ...]
#
# Examples:
#   # Run speed test on the local node
#   ./UplinkSpeedTest.sh
#
#   # Run speed test on all nodes in the cluster
#   ./UplinkSpeedTest.sh all
#
#   # Run speed test on specific remote nodes (by name or IP)
#   ./UplinkSpeedTest.sh IHK02 172.20.83.23
#
# This script requires:
#   - 'speedtest' (or 'speedtest-cli') on each node
#   - 'ssh' access to remote nodes (root@<IP>)
#   - A Proxmox environment (pvecm, etc.) if using cluster features
#
# Function Index:
#   - usage
#   - run_speedtest_on_node
#   - resolve_node_argument_to_ip
#

source "$UTILITIES"

###############################################################################
# Global Variables
###############################################################################
LOCAL_NODE_NAME="$(hostname)"    # OS-level hostname
LOCAL_NODE_IP=""                 # Populated after init_node_mappings

###############################################################################
# Usage Display
###############################################################################
usage() {
  echo "Usage: $0 [all|<node1> <node2> ...]"
  echo
  echo "Examples:"
  echo "  # Test speed locally only"
  echo "  $0"
  echo
  echo "  # Test speed on all nodes in the cluster"
  echo "  $0 all"
  echo
  echo "  # Test speed on specific nodes (by name or IP)"
  echo "  $0 IHK02 172.20.83.23"
  exit 1
}

###############################################################################
# Verify 'speedtest' is Installed (Prompt to Install if Missing)
###############################################################################
install_or_prompt "speedtest-cli"

###############################################################################
# Run Speedtest on Single Node (Local or Remote)
# Parameters:
#   1 -> IP Address of the Node
###############################################################################
run_speedtest_on_node() {
  local nodeIp="$1"

  # If the node IP matches our local IP, run locally
  if [[ "$nodeIp" == "$LOCAL_NODE_IP" ]]; then
    echo "Running speed test locally on IP: \"$nodeIp\""
    speedtest
  else
    echo "Running speed test on remote node with IP: \"$nodeIp\""
    ssh "root@$nodeIp" "speedtest"
  fi
}

###############################################################################
# Resolve a Node Argument to an IP
# - If the argument is already an IP, return it
# - Otherwise, attempt to resolve via get_ip_from_name
###############################################################################
resolve_node_argument_to_ip() {
  local arg="$1"

  # Simple check if arg looks like an IPv4 address
  if [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$arg"
  else
    # Attempt to resolve name -> IP
    get_ip_from_name "$arg"
  fi
}

###############################################################################
# Main Script Logic
###############################################################################
check_root          # Ensure running as root
check_proxmox       # Ensure running on a Proxmox node

# Make sure speedtest is installed locally (remote nodes also need it)
verify_speedtest_installed

# If user asked for help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage
fi

# If no arguments, test speed on local node only
if [[ $# -eq 0 ]]; then
  # Initialize node mappings to find local node IP
  init_node_mappings
  LOCAL_NODE_IP="$(get_ip_from_name "$LOCAL_NODE_NAME")" || {
    echo "Error: Could not determine IP for local node \"$LOCAL_NODE_NAME\"."
    exit 1
  }
  run_speedtest_on_node "$LOCAL_NODE_IP"
  exit 0
fi

# If "all" was specified, we run on local + remote cluster nodes
if [[ "$1" == "all" ]]; then
  check_cluster_membership
  init_node_mappings

  # Get local IP from name
  LOCAL_NODE_IP="$(get_ip_from_name "$LOCAL_NODE_NAME")" || {
    echo "Error: Could not determine IP for local node \"$LOCAL_NODE_NAME\"."
    exit 1
  }

  # Run local test first
  echo "Running speed test on local node..."
  run_speedtest_on_node "$LOCAL_NODE_IP"
  echo "-----------------------------------------------------"

  # Then run on remote nodes
  echo "Gathering remote node IPs..."
  readarray -t REMOTE_NODES < <( get_remote_node_ips )
  for nodeIp in "${REMOTE_NODES[@]}"; do
    run_speedtest_on_node "$nodeIp"
    echo "-----------------------------------------------------"
  done
  exit 0
fi

# Otherwise, treat each argument as a node name or IP
init_node_mappings
LOCAL_NODE_IP="$(get_ip_from_name "$LOCAL_NODE_NAME")" || {
  echo "Error: Could not determine IP for local node \"$LOCAL_NODE_NAME\"."
  exit 1
}

for arg in "$@"; do
  nodeIp="$(resolve_node_argument_to_ip "$arg")" || {
    echo "Error: Could not resolve \"$arg\" to an IP. Exiting."
    exit 1
  }
  run_speedtest_on_node "$nodeIp"
  echo "-----------------------------------------------------"
done

prompt_keep_installed_packages
