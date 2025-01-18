#!/bin/bash
#
# PenetrationTest.sh
#
# A script to conduct a basic vulnerability assessment (pentest) on one or multiple Proxmox hosts.
#
# Usage:
#   ./PenetrationTest.sh <target-host> [<additional-hosts> ...]
#   ./PenetrationTest.sh all
#
# Examples:
#   ./PenetrationTest.sh 192.168.1.50
#       Conducts a pentest on a single host at "192.168.1.50".
#
#   ./PenetrationTest.sh 192.168.1.50 192.168.1.51 192.168.1.52
#       Conducts a pentest on multiple specified hosts.
#
#   ./PenetrationTest.sh all
#       Discovers all cluster nodes from the Proxmox cluster configuration,
#       then runs nmap-based checks on each node.
#
# Note: This script performs a non-exhaustive scan and should be used
# only with explicit permission. Pentesting without permission is illegal.
#
# Function Index:
#   - usage
#
source "$UTILITIES"

###############################################################################
# Preliminary Checks
###############################################################################
check_root
check_proxmox

###############################################################################
# Usage
###############################################################################
usage() {
  echo "Usage: $0 <target-host> [<additional-hosts> ...]"
  echo "       $0 all"
  echo
  echo "Examples:"
  echo "  $0 192.168.1.50"
  echo "  $0 192.168.1.50 192.168.1.51 192.168.1.52"
  echo "  $0 all"
  exit 1
}

###############################################################################
# Main Script Logic
###############################################################################
install_or_prompt "nmap"

if [[ $# -lt 1 ]]; then
  usage
fi

if [[ "$1" == "all" ]]; then
  echo "[*] Discovering all remote nodes in the Proxmox cluster..."
  readarray -t REMOTE_NODES < <( get_remote_node_ips )
  if [[ "${#REMOTE_NODES[@]}" -eq 0 ]]; then
    echo "Error: No remote nodes discovered. Are you sure this node is part of a cluster?"
    exit 2
  fi
  TARGETS=("${REMOTE_NODES[@]}")
else
  TARGETS=("$@")
fi

for host in "${TARGETS[@]}"; do
  echo "======================================================================="
  echo "[*] Starting vulnerability scan for host: \"$host\""
  echo "======================================================================="
  nmap -sV --script vuln "$host"
  echo "======================================================================="
  echo "[*] Finished scanning \"$host\""
  echo "======================================================================="
  echo
done

prompt_keep_installed_packages

###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node