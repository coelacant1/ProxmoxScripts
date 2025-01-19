#!/bin/bash
#
# BulkChangeDNS.sh
#
# Updates the DNS search domain and DNS server for a range of VMs within a Proxmox VE environment.
# It sets new DNS settings and regenerates the Cloud-Init image to apply changes.
#
# Usage:
#   ./BulkChangeDNS.sh <start_vm_id> <end_vm_id> <dns_server> <dns_search_domain>
#
# Example:
#   ./BulkChangeDNS.sh 400 430 8.8.8.8 example.com
#

source "${UTILITYPATH}/Prompts.sh"

__check_root__
__check_proxmox__

###############################################################################
# Argument Checking
###############################################################################
if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <start_vm_id> <end_vm_id> <dns_server> <dns_search_domain>"
  exit 1
fi

START_VMID="$1"
END_VMID="$2"
DNS_SERVER="$3"
DNS_SEARCHDOMAIN="$4"

###############################################################################
# Main
###############################################################################
for (( vmid=START_VMID; vmid<=END_VMID; vmid++ )); do
  if qm status "$vmid" &>/dev/null; then
    echo "Updating DNS settings for VM ID: $vmid"
    qm set "$vmid" --nameserver "$DNS_SERVER" --searchdomain "$DNS_SEARCHDOMAIN"
    qm cloudinit dump "$vmid"
    echo " - Cloud-Init DNS settings updated for VM ID: $vmid."
  else
    echo "VM ID: $vmid does not exist. Skipping..."
  fi
done

echo "Cloud-Init DNS update process completed!"
