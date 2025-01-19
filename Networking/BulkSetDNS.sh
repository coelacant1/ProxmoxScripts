#!/bin/bash
#
# BulkSetDNS.sh
#
# Sets the DNS servers and search domain for all nodes in the Proxmox VE cluster,
# using the IPs reported from the Proxmox utilities (skipping the local node).
#
# Usage:
#   ./BulkSetDNS.sh <dns_server_1> <dns_server_2> <search_domain>
#
# Example:
#   ./BulkSetDNS.sh 8.8.8.8 8.8.4.4 mydomain.local
#
# Explanation:
#   - Retrieves the IP addresses of remote nodes in the Proxmox cluster.
#   - Uses SSH to overwrite each remote node's /etc/resolv.conf with the specified
#     DNS servers and search domain.
#   - Also applies the same changes to the local node.
#
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Check environment and validate arguments
###############################################################################
__check_root__
__check_proxmox__

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <dns_server_1> <dns_server_2> <search_domain>"
  exit 1
fi

DNS1="$1"
DNS2="$2"
SEARCH_DOMAIN="$3"

###############################################################################
# Get remote node IPs
###############################################################################
readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )

###############################################################################
# Update DNS on each remote node
###############################################################################
for nodeIp in "${REMOTE_NODES[@]}"; do
  echo "-----------------------------------------------------------"
  echo "Setting DNS on remote node IP: \"${nodeIp}\""
  echo "  DNS1=\"${DNS1}\", DNS2=\"${DNS2}\", SEARCH_DOMAIN=\"${SEARCH_DOMAIN}\""

  ssh -o StrictHostKeyChecking=no "root@${nodeIp}" \
    "echo -e 'search ${SEARCH_DOMAIN}\nnameserver ${DNS1}\nnameserver ${DNS2}' > /etc/resolv.conf"
  if [ $? -eq 0 ]; then
    echo "  - DNS configured successfully on \"${nodeIp}\""
  else
    echo "  - Failed to configure DNS on \"${nodeIp}\""
  fi
  echo
done

###############################################################################
# Update DNS on the local node
###############################################################################
echo "-----------------------------------------------------------"
echo "Setting DNS on the local node:"
echo "  DNS1=\"${DNS1}\", DNS2=\"${DNS2}\", SEARCH_DOMAIN=\"${SEARCH_DOMAIN}\""
echo -e "search ${SEARCH_DOMAIN}\nnameserver ${DNS1}\nnameserver ${DNS2}" > /etc/resol
