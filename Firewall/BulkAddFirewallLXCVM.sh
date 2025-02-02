#!/bin/bash
#
# InsertFirewallSecurityGroup.sh
#
# Inserts a specified datacenter firewall security group into a range of Proxmox
# VMs/LXC containers. It also enables the firewall on each VM/Container and on
# the correct network interface (the one with a gateway for LXC, net0 for VMs).
#
# Usage:
#   ./InsertFirewallSecurityGroup.sh <startVmid> <endVmid> <datacenterGroupName>
#
# Example:
#   # Insert 'MySecurityGroup' for IDs from 100 to 110
#   ./InsertFirewallSecurityGroup.sh 100 110 MySecurityGroup
#
# Function Index:
#   - enable_firewall_on_lxc_gw_iface
#   - enable_firewall_on_vm_net0
#   - enable_firewall_on_resource
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Argument Parsing
###############################################################################
if [ $# -ne 3 ]; then
  echo "Error: Invalid arguments."
  echo "Usage: $0 <startVmid> <endVmid> <datacenterGroupName>"
  exit 1
fi

START_VMID="$1"
END_VMID="$2"
SECURITY_GROUP="$3"

###############################################################################
# Helper Functions
###############################################################################
enable_firewall_on_lxc_gw_iface() {
  local vmid="$1"
  local configLines
  configLines="$(pct config "$vmid" 2>/dev/null)"
  while read -r line; do
    if [[ "$line" =~ ^net([0-9]+):.*gw= ]]; then
      local nicIndex="${BASH_REMATCH[1]}"
      local netLine
      netLine="$(echo "$line" | sed -E 's/^net[0-9]+: //')"
      if [[ "$netLine" =~ firewall= ]]; then
        netLine="$(echo "$netLine" | sed -E 's/,?firewall=[^,]*/,firewall=1/g')"
      else
        netLine="${netLine},firewall=1"
      fi
      pct set "$vmid" -net"${nicIndex}" "$netLine" &>/dev/null
    fi
  done <<< "$configLines"

  # Ensure container-level firewall feature is on
  pct set "$vmid" --features "firewall=1" &>/dev/null
}

enable_firewall_on_vm_net0() {
  local vmid="$1"
  local netLine
  netLine="$(qm config "$vmid" 2>/dev/null | grep '^net0:' | sed -E 's/^net0: //')"
  if [ -n "$netLine" ]; then
    if [[ "$netLine" =~ firewall= ]]; then
      netLine="$(echo "$netLine" | sed -E 's/,?firewall=[^,]*/,firewall=1/g')"
    else
      netLine="${netLine},firewall=1"
    fi
    qm set "$vmid" --net0 "$netLine" &>/dev/null
  fi
}

enable_firewall_on_resource() {
  local vmid="$1"

  if pct config "$vmid" &>/dev/null || qm config "$vmid" &>/dev/null; then
    cat <<EOF >"/etc/pve/firewall/${vmid}.fw"
[OPTIONS]
enable: 1

[RULES]
GROUP ${SECURITY_GROUP}
EOF
    echo "Set firewall configuration for ID '${vmid}' with security group '${SECURITY_GROUP}'."
  else
    echo "Skipping '${vmid}' - not a valid VM or LXC container."
  fi
}

###############################################################################
# Main Logic
###############################################################################
for (( vmid=START_VMID; vmid<=END_VMID; vmid++ )); do
  # Check if this is a LXC container
  if pct status "$vmid" &>/dev/null; then
    enable_firewall_on_lxc_gw_iface "$vmid"

    echo "Enabled firewall LXC net0 interface."

    enable_firewall_on_resource "$vmid"
  # Otherwise check if this is a QEMU VM
  elif qm config "$vmid" &>/dev/null; then
    enable_firewall_on_vm_net0 "$vmid"

    echo "Enabled firewall VM net0 interface."

    enable_firewall_on_resource "$vmid"
  else
    echo "Warning: '$vmid' is neither a valid container nor a VM. Skipping."
  fi

done
