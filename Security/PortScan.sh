#!/bin/bash
#
# PortScan.sh
#
# A script to scan one or multiple Proxmox hosts (or all in a cluster) to identify
# which TCP ports are open. This script uses nmap (installing it if missing), then
# optionally removes it when finished.
#
# Usage:
#   ./PortScan.sh <target-host> [<additional-hosts> ...]
#   ./PortScan.sh all
#
# Examples:
#   # Scans a single host at 192.168.1.50 for open TCP ports.
#   ./PortScan.sh 192.168.1.50
#
#   # Scans multiple specified hosts for open TCP ports.
#   ./PortScan.sh 192.168.1.50 192.168.1.51 192.168.1.52
#
#   # Discovers all cluster nodes from the Proxmox cluster configuration
#   # and runs the open port scan on each node.
#   ./PortScan.sh all
#
# Note: Use responsibly and only with explicit permission.
#       Unauthorized port scanning may be illegal.
#
# Function Index:
#   - usage_info
#

source "$UTILITIES"

###############################################################################
# Preliminary Checks
###############################################################################
check_root
check_proxmox

###############################################################################
# Usage Information
###############################################################################
function usage_info() {
  echo "Usage:"
  echo "  $0 <target-host> [<additional-hosts> ...]"
  echo "  $0 all"
  echo
  echo "Examples:"
  echo "  # Scans a single host at 192.168.1.50 for open TCP ports."
  echo "  $0 192.168.1.50"
  echo
  echo "  # Scans multiple specified hosts for open TCP ports."
  echo "  $0 192.168.1.50 192.168.1.51 192.168.1.52"
  echo
  echo "  # Discovers all cluster nodes from the Proxmox cluster configuration,"
  echo "  # then runs the open port scan on each node."
  echo "  $0 all"
  exit 1
}

###############################################################################
# Main Script Logic
###############################################################################
if [[ $# -lt 1 ]]; then
  usage_info
fi

install_or_prompt "nmap"

if [[ "$1" == "all" ]]; then
  check_cluster_membership
  readarray -t discoveredHosts < <( get_remote_node_ips )
  
  if [[ ${#discoveredHosts[@]} -eq 0 ]]; then
    echo "Error: No hosts discovered in the cluster. Exiting."
    exit 2
  fi
  
  echo "[*] Discovered the following cluster node IPs:"
  for ip in "${discoveredHosts[@]}"; do
    echo "$ip"
  done
  echo
  
  targets=("${discoveredHosts[@]}")
else
  targets=("$@")
fi

for host in "${targets[@]}"; do
  echo "======================================================================="
  echo "[*] Scanning open TCP ports for host: \"${host}\""
  echo "======================================================================="
  nmap -p- --open -n "${host}"
  echo "======================================================================="
  echo "[*] Finished scanning \"${host}\""
  echo "======================================================================="
  echo
done

prompt_keep_installed_packages
