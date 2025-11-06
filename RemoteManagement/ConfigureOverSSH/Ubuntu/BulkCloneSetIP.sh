#!/bin/bash
#
# BulkCloneSetIPUbuntu.sh
#
# Clones a VM multiple times on a Proxmox server, updates each clone's IP address
# (including CIDR notation), sets a new default gateway, and restarts networking
# under Ubuntu’s netplan configuration. It assumes:
#   1) The template VM is accessible via SSH at the provided template IP (no CIDR).
#   2) On the template VM, netplan is used for network configuration. Typically,
#      this means one or more files under /etc/netplan/*.yaml.
#   3) The template VM’s current IP (and gateway, if any) will be replaced with
#      the new IP/gateway lines in the netplan YAML configuration.
#
# Usage:
#   BulkCloneSetIPUbuntu.sh <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId>
#
# Arguments:
#   templateIp   : The template VM’s IP address (e.g. 192.168.1.50).
#   startIpCIDR  : The first clone’s IP in CIDR format (e.g. 192.168.1.10/24).
#   newGateway   : The default gateway for all new clones (e.g. 192.168.1.1).
#   count        : Number of clones to create.
#   templateId   : The template VM ID to clone from.
#   baseVmId     : The first new VM ID to assign; subsequent clones increment this.
#
# Example:
#   # Clones VM ID 9000 five times, starting at VM ID 9010.
#   # The template is at 192.168.1.50, the first cloned IP is 192.168.1.10/24,
#   # the gateway is set to 192.168.1.1, and each subsequent clone increments
#   # the final octet by 1.
#   BulkCloneSetIPUbuntu.sh 192.168.1.50 192.168.1.10/24 192.168.1.1 5 9000 9010
#
# Another Example:
#   BulkCloneSetIPUbuntu.sh 192.168.10.50 192.168.10.100/24 192.168.10.1 3 800 810
#

# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Conversion.sh
source "${UTILITYPATH}/Conversion.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "template_ip:ip start_ip_cidr:string new_gateway:ip count:number template_id:vmid base_vm_id:vmid" "$@"

###############################################################################
# Check prerequisites
###############################################################################
__check_root__
__check_proxmox__

# Split the starting IP and CIDR (e.g., 192.168.1.10/24 -> 192.168.1.10 and 24)
IFS='/' read -r startIpAddrOnly startMask <<< "$START_IP_CIDR"

# Convert the starting IP to an integer for incrementing
ipInt="$( __ip_to_int__ "$startIpAddrOnly" )"

###############################################################################
# Main logic
###############################################################################
for (( i=0; i<instanceCount; i++ )); do
  currentVmId=$(( baseVmId + i ))
  currentIp="$( __int_to_ip__ "$ipInt" )"
  currentIpCidr="$currentIp/$startMask"

  echo "Cloning VM ID \"$TEMPLATE_ID\" to new VM ID \"$currentVmId\" with IP \"$currentIpCidr\"..."
  qm clone "$TEMPLATE_ID" "$currentVmId" --name "cloned-$currentVmId"
  qm start "$currentVmId"

  echo "Configuring VM ID \"$currentVmId\" to use IP \"$currentIpCidr\" and gateway \"$NEW_GATEWAY\"..."
  # Over SSH to the template VM:
  #   1) Remove lines referencing 'gateway4:'
  #   2) Replace lines matching 'addresses: [templateIp/NN]' with the new IP/CIDR
  #   3) Insert the new gateway4 line after the 'addresses:' line
  #   4) Apply netplan changes
  ssh "root@$TEMPLATE_IP" bash -c "'
    sed -i \"/gateway4:/d\" /etc/netplan/*.yaml
    sed -i \"s|addresses: \\[${TEMPLATE_IP}/[0-9]\\+\\]|addresses: [${currentIpCidr}]|g\" /etc/netplan/*.yaml
    sed -i \"/addresses: \\[${currentIpCidr}\\]/a \ \ \ \ gateway4: ${NEW_GATEWAY}\" /etc/netplan/*.yaml
    netplan apply
  '"

  # Increment IP by 1 for the next clone
  ipInt=$(( ipInt + 1 ))
done
