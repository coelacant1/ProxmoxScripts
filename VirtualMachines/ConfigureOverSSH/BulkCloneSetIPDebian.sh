#!/bin/bash
#
# BulkCloneSetIPDebian.sh
#
# Clones a Debian-based VM multiple times, updates each clone's IP/network,
# sets a default gateway, and restarts networking. Uses SSH with username/password.
# Minimal comments, name prefix added for the cloned VMs.
#
# Usage:
#   ./BulkCloneSetIPDebian.sh <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId> <sshUsername> <sshPassword> <vmNamePrefix>
#
# Example:
#   # Clones VM ID 100 five times, starting IP at 172.20.83.100 with mask /24,
#   # gateway 172.20.83.1, base VM ID 200, SSH login root:pass123, prefix "CLOUD-"
#   ./BulkCloneSetIPDebian.sh 172.20.83.22 172.20.83.100/24 172.20.83.1 5 100 200 root pass123 CLOUD-
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/SSH.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Argument Parsing
###############################################################################
if [ "$#" -lt 9 ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId> <sshUsername> <sshPassword> <vmNamePrefix>"
  exit 1
fi

templateIpAddr="$1"
startIpCidr="$2"
newGateway="$3"
instanceCount="$4"
templateId="$5"
baseVmId="$6"
sshUsername="$7"
sshPassword="$8"
vmNamePrefix="$9"

IFS='/' read -r startIpAddrOnly startMask <<<"$startIpCidr"
ipInt="$(__ip_to_int__ "$startIpAddrOnly")"

###############################################################################
# Main Logic
###############################################################################
for ((i=0; i<instanceCount; i++)); do
  currentVmId=$((baseVmId + i))
  currentIp="$(__int_to_ip__ "$ipInt")"
  currentIpCidr="$currentIp/$startMask"

  echo "Cloning VM ID \"$templateId\" to new VM ID \"$currentVmId\" with IP \"$currentIpCidr\"..."
  qm clone "$templateId" "$currentVmId" --name "${vmNamePrefix}${currentVmId}"
  qm start "$currentVmId"

  __wait_for_ssh__ "$templateIpAddr" "$sshUsername" "$sshPassword"

  sshpass -p "$sshPassword" ssh -o StrictHostKeyChecking=no "$sshUsername@$templateIpAddr" bash -s <<EOF
sed -i '/\bgateway\b/d' /etc/network/interfaces
sed -i "s#${templateIpAddr}/[0-9]\\+#${currentIpCidr}#g" /etc/network/interfaces
sed -i "\#address ${currentIpCidr}#a gateway ${newGateway}" /etc/network/interfaces
TAB="\$(printf '\\t')"
sed -i "s|^[[:space:]]*gateway\\(.*\\)|\${TAB}gateway\\1|" /etc/network/interfaces
EOF

  sshpass -p "$sshPassword" ssh -o StrictHostKeyChecking=no "$sshUsername@$templateIpAddr" \
    "nohup sh -c 'sleep 2; systemctl restart networking' >/dev/null 2>&1 &"
  
  __wait_for_ssh__ "$currentIp" "$sshUsername" "$sshPassword"
  ipInt=$((ipInt + 1))
done

###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
