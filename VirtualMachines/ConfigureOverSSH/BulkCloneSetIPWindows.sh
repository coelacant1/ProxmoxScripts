#!/bin/bash
#
# BulkCloneSetIPWindows.sh
#
# Clones a Windows VM multiple times on a Proxmox server, updates each clone's
# IPv4 address (including CIDR notation), sets a new default gateway, and
# restarts networking on the Windows VM via PowerShell commands over OpenSSH.
#
# The script:
#   1) Clones the template VM a specified number of times using qm clone.
#   2) Starts each cloned VM.
#   3) SSHs into the template VM (assumes the same template IP for each iteration).
#   4) Detects which network interface is assigned the template IP.
#   5) Removes the old IP from that interface.
#   6) Sets the new IP, prefix length, and default gateway.
#
# Requirements/Assumptions:
#   1) Proxmox 8 environment.
#   2) Script is run as root on Proxmox.
#   3) The template Windows VM has OpenSSH server installed and running.
#   4) The Windows VM has PowerShell available (default on modern Windows).
#   5) The user can SSH in as 'Administrator' (or equivalent) without prompting
#      for an interactive password (e.g., via key-based auth).
#
# Usage:
#   ./BulkCloneSetIPWindows.sh <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId>
#
# Arguments:
#   templateIp    : The current (template) Windows VM’s IP address (e.g. 192.168.1.50).
#   startIpCIDR   : The first clone’s new IP in CIDR format (e.g. 192.168.1.10/24).
#   newGateway    : The default gateway for the cloned VMs (e.g. 192.168.1.1).
#   count         : Number of clones to create.
#   templateId    : The template VM ID to clone from.
#   baseVmId      : The first new VM ID to assign; subsequent clones increment this.
#
# Example:
#   # Clones VM ID 9000 five times, starting at VM ID 9010.
#   # The template IP is 192.168.1.50, the first cloned IP is 192.168.1.10/24,
#   # the gateway is 192.168.1.1, and subsequent clones increment the final octet by 1.
#   ./BulkCloneSetIPWindows.sh 192.168.1.50 192.168.1.10/24 192.168.1.1 5 9000 9010
#
# Another Example:
#   ./BulkCloneSetIPWindows.sh 192.168.10.50 192.168.10.100/24 192.168.10.1 3 800 810
#

source "${UTILITYPATH}/Conversion.sh"
source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Check prerequisites and parse arguments
###############################################################################
__check_root__
__check_proxmox__

if [ $# -lt 6 ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId>"
  exit 1
fi

TEMPLATE_IP="$1"
START_IP_CIDR="$2"
NEW_GATEWAY="$3"
INSTANCE_COUNT="$4"
TEMPLATE_ID="$5"
BASE_VM_ID="$6"

# Split the starting IP and CIDR (e.g. 192.168.1.10/24 -> 192.168.1.10 and 24)
IFS='/' read -r startIpAddrOnly startMask <<< "$START_IP_CIDR"

# Convert the starting IP to an integer for incrementing
ipInt="$( __ip_to_int__ "$startIpAddrOnly" )"

###############################################################################
# Main logic
###############################################################################
for (( i=0; i<INSTANCE_COUNT; i++ )); do
  currentVmId=$(( BASE_VM_ID + i ))
  currentIp="$( __int_to_ip__ "$ipInt" )"
  currentIpCidr="$currentIp/$startMask"

  echo "Cloning VM ID \"$TEMPLATE_ID\" to new VM ID \"$currentVmId\" with IP \"$currentIpCidr\"..."
  qm clone "$TEMPLATE_ID" "$currentVmId" --name "cloned-$currentVmId"
  qm start "$currentVmId"

  echo "Configuring VM ID \"$currentVmId\" to use IP \"$currentIpCidr\" (gateway \"$NEW_GATEWAY\") on Windows..."
  # Instruct Windows via PowerShell over SSH:
  #  1) Identify the interface with the TEMPLATE_IP.
  #  2) Remove that IP from the interface.
  #  3) Assign the new IP/mask/gateway.
  ssh "Administrator@${TEMPLATE_IP}" powershell -Command "
    \$iface = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { \$_.IPAddress -eq '$TEMPLATE_IP' }
    if (-not \$iface) {
      Write-Error 'Error: Could not find the interface with IP $TEMPLATE_IP on the Windows VM.'
      exit 1
    }
    Remove-NetIPAddress -InterfaceAlias \$iface.InterfaceAlias -IPAddress \$iface.IPAddress -Confirm:\$false
    New-NetIPAddress -InterfaceAlias \$iface.InterfaceAlias -IPAddress '$currentIp' -PrefixLength $startMask -DefaultGateway '$NEW_GATEWAY' -AddressFamily IPv4
  "

  # Increment IP for the next clone
  ipInt=$(( ipInt + 1 ))
done
