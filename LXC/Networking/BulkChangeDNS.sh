#!/bin/bash
#
# BulkChangeDNS.sh
#
# This script updates DNS nameservers for a series of LXC containers, from a specified
# start ID to a specified end ID (inclusive).
#
# Usage:
#   ./BulkChangeDNS.sh <start_ct_id> <end_ct_id> <dns1> [<dns2> <dns3> ...]
#
# Example:
#   ./BulkChangeDNS.sh 400 402 8.8.8.8 1.1.1.1
#   This updates containers 400, 401, and 402 to use DNS servers 8.8.8.8 and 1.1.1.1
#
# Note:
#   - You can pass more than two DNS servers if desired. They get appended.
#   - If you want to specify a single DNS server, omit the rest.
#   - Must be run as root on a Proxmox node.
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# MAIN
###############################################################################

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <start_ct_id> <end_ct_id> <dns1> [<dns2> <dns3> ...]"
  exit 1
fi

START_CT_ID="$1"
END_CT_ID="$2"
shift 2
DNS_SERVERS="$*"

echo "DNS servers to set: \"$DNS_SERVERS\""
echo "=== Starting DNS update for containers in range ${START_CT_ID}..${END_CT_ID} ==="

__check_root__
__check_proxmox__
# If a cluster check is required, uncomment:
# __check_cluster_membership__

for (( CT_ID=START_CT_ID; CT_ID<=END_CT_ID; CT_ID++ )); do
  if pct config "$CT_ID" &>/dev/null; then
    echo "Updating DNS for container $CT_ID to: \"$DNS_SERVERS\""
    if pct set "$CT_ID" -nameserver "$DNS_SERVERS"; then
      echo " - Successfully updated DNS for CT $CT_ID."
    else
      echo " - Failed to update DNS for CT $CT_ID."
    fi
  else
    echo " - Container $CT_ID does not exist. Skipping."
  fi
done

echo "=== Bulk DNS change process complete! ==="
