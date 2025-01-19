#!/bin/bash
#
# BulkChangeIP.sh
#
# This script automates changing the IP addresses of a range of existing LXC containers on Proxmox VE.
# Instead of specifying how many containers to update, you provide a start and end container ID.
# It then assigns sequential IP addresses based on a starting IP/CIDR. An optional gateway can also be set.
#
# Usage:
#   ./BulkChangeIP.sh <start_ct_id> <end_ct_id> <start_ip/cidr> <bridge> [gateway]
#
# Example:
#   # Updates containers 400..404 with IPs 192.168.1.50..54/24 on vmbr0, gateway 192.168.1.1
#   ./BulkChangeIP.sh 400 404 192.168.1.50/24 vmbr0 192.168.1.1
#
#   # Same as above, but does not set a gateway.
#   ./BulkChangeIP.sh 400 404 192.168.1.50/24 vmbr0
#
# Notes:
#   - Must be run as root on a Proxmox node.
#   - 'pct' is part of the standard Proxmox LXC utilities.
#   - IP increment logic uses the __ip_to_int__ and __int_to_ip__ functions from the sourced Utilities.
#

source "${UTILITYPATH}/Conversion.sh"
source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# MAIN
###############################################################################

# Parse and validate arguments
if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <start_ct_id> <end_ct_id> <start_ip/cidr> <bridge> [gateway]"
  echo "Example:"
  echo "  $0 400 404 192.168.1.50/24 vmbr0 192.168.1.1"
  exit 1
fi

START_CT_ID="$1"
END_CT_ID="$2"
START_IP_CIDR="$3"
BRIDGE="$4"
GATEWAY="${5:-}"

# Ensure we are root and on a Proxmox node
__check_root__
__check_proxmox__

# Split IP and subnet
IFS='/' read -r START_IP SUBNET_MASK <<< "$START_IP_CIDR"
if [[ -z "$START_IP" || -z "$SUBNET_MASK" ]]; then
  echo "Error: Unable to parse start_ip/cidr: \"$START_IP_CIDR\". Format must be X.X.X.X/XX."
  exit 1
fi

# Convert start IP to integer
START_IP_INT="$(__ip_to_int__ "$START_IP")"

# Summary
echo "=== Starting IP update for containers from \"$START_CT_ID\" to \"$END_CT_ID\" ==="
echo " - Starting IP: \"$START_IP/$SUBNET_MASK\""
if [[ -n "$GATEWAY" ]]; then
  echo " - Gateway: \"$GATEWAY\""
else
  echo " - No gateway specified"
fi

# Update IPs for each container in the specified range
for (( ctId=START_CT_ID; ctId<=END_CT_ID; ctId++ )); do
  offset=$(( ctId - START_CT_ID ))
  currentIpInt=$(( START_IP_INT + offset ))
  newIp="$(__int_to_ip__ "$currentIpInt")"

  if pct config "$ctId" &>/dev/null; then
    echo "Updating IP for container \"$ctId\" to \"$newIp/$SUBNET_MASK\" on \"$BRIDGE\"..."
    if [[ -z "$GATEWAY" ]]; then
      pct set "$ctId" -net0 name=eth0,bridge="$BRIDGE",ip="$newIp/$SUBNET_MASK"
    else
      pct set "$ctId" -net0 name=eth0,bridge="$BRIDGE",ip="$newIp/$SUBNET_MASK",gw="$GATEWAY"
    fi

    if [[ $? -eq 0 ]]; then
      echo " - Successfully updated container \"$ctId\"."
    else
      echo " - Failed to update container \"$ctId\"."
    fi
  else
    echo " - Container \"$ctId\" does not exist. Skipping."
  fi
done

echo "=== Bulk IP change process complete! ==="
echo "If containers are running, consider restarting them or reapplying networking."
