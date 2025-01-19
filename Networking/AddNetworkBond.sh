#!/bin/bash
#
# AddNetworkBond.sh
#
# This script configures network interfaces for bonding and VLAN bridging on a
# Proxmox 8 environment. It checks if the necessary inputs are provided, creates
# configuration entries for a specified bond and VLAN ID, and inserts these
# entries into the network configuration file in a sorted order based on
# interface names. The script ensures that duplicate entries are not added, then
# prompts the user to manually restart the network services to apply changes.
#
# Usage:
#   ./AddNetworkBond.sh <bond_base> <vlan_id>
#
# Examples:
#   # Configure VLAN 10 for bond0
#   ./AddNetworkBond.sh bond0 10
#
#   # Configure VLAN 20 for bond1
#   ./AddNetworkBond.sh bond1 20
#
# Where:
#   bond_base - The base name of the network bond (e.g., "bond0")
#   vlan_id   - The VLAN ID to configure with the bond
#
# Function Index:
#   - insert_sorted_config
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Dependency Checks (if needed for bonding)
###############################################################################
__install_or_prompt__ "ifenslave"

###############################################################################
# Usage Check
###############################################################################
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <bond_base> <vlan_id>"
  exit 1
fi

###############################################################################
# Variable Initialization
###############################################################################
CONFIG_FILE="/etc/network/interfaces"
BOND_BASE="$1"
VLAN_ID="$2"
BOND_NAME="${BOND_BASE}.${VLAN_ID}"
VMBR_NAME="vmbr${VLAN_ID}"

###############################################################################
# Insert Configuration in Sorted Order
###############################################################################
insert_sorted_config() {
  local insertName="$1"
  local insertConfig="$2"
  local configType="$3"

  local pattern="iface ${configType}[0-9]+"
  local configBlock
  configBlock=$(awk "/^auto $pattern/,/^\$/" RS= "$CONFIG_FILE")

  if echo "$configBlock" | grep -q "^auto $insertName\$"; then
    echo "\"$insertName\" already exists in \"$CONFIG_FILE\"."
    return 1
  fi

  local sortedBlock
  sortedBlock=$(echo -e "$configBlock\nauto $insertName\n$insertConfig" | sort -V)

  awk -v pat="^auto $pattern\$" -v sorted="$sortedBlock" '
    /^auto '"$configType"'[0-9]+/,/^$/ {
      if (!p) {
        print sorted
        p=1
      }
      next
    }
    { print }
  ' RS= ORS='\n\n' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"

  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

###############################################################################
# Create Config Blocks
###############################################################################
bondConfig="auto $BOND_NAME
iface $BOND_NAME inet manual
    vlan-raw-device $BOND_BASE"

vmbrConfig="auto $VMBR_NAME
iface $VMBR_NAME inet manual
    bridge_ports $BOND_NAME
    bridge_stp off
    bridge_fd 0"

###############################################################################
# Insert Bond & Bridge Configuration
###############################################################################
insert_sorted_config "$BOND_NAME" "$bondConfig" "$BOND_BASE"
insert_sorted_config "$VMBR_NAME" "$vmbrConfig" "vmbr"

echo "Configuration potentially added to \"$CONFIG_FILE\". Please review for accuracy."
echo "Manually restart networking or the interfaces to apply changes."

__prompt_keep_installed_packages__
