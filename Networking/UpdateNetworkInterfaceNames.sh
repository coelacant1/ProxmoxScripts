#!/bin/bash
#
# UpdateInterfaceNames.sh
#
# This script updates /etc/network/interfaces to match new network interface names as found in `ip a`.
# It creates a backup, attempts to map old names to new names, and handles multiple occurrences
# of the same interface (e.g., bond-slaves).
#
# Usage:
#   ./UpdateInterfaceNames.sh
#
# No arguments are required.
#
# Function Index:
#   - updateInterfaceNames
#
source "$UTILITIES"

###############################################################################
# PRE-CHECKS
###############################################################################

check_root
check_proxmox

###############################################################################
# CONFIG / CONSTANTS
###############################################################################

CONFIG_FILE="/etc/network/interfaces"
BACKUP_FILE="/etc/network/interfaces.bak-$(date +%Y%m%d%H%M%S)"

###############################################################################
# BACKUP ORIGINAL FILE
###############################################################################

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: \"$CONFIG_FILE\" not found. Exiting."
  exit 1
fi

cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "Backed up \"$CONFIG_FILE\" to \"$BACKUP_FILE\"."

###############################################################################
# HELPER FUNCTIONS
###############################################################################

updateInterfaceNames() {
  local oldName="$1"
  local newName="$2"

  if grep -q "\b${oldName}\b" "$CONFIG_FILE"; then
    sed -i "s/\b${oldName}\b/${newName}/g" "$CONFIG_FILE"
    echo " - Updated interface name: \"$oldName\" => \"$newName\""
  else
    echo " - Skipping: \"$oldName\" not found in \"$CONFIG_FILE\""
  fi
}

###############################################################################
# MAIN LOGIC
###############################################################################

declare -A INTERFACE_MAP
declare -A BASE_NAME_COUNT

echo
echo "=== Scanning current interfaces via 'ip a' ==="

while read -r ipLine; do
  if [[ $ipLine =~ ^[0-9]+:\ ([^:]+): ]]; then
    interface="${BASH_REMATCH[1]}"

    # Skip loopback, tunnels, or other special interfaces
    if [[ "$interface" == "lo" ]] || [[ "$interface" == *"tap"* ]] || [[ "$interface" == *"veth"* ]]; then
      continue
    fi

    # Derive base name from the new interface name (example logic)
    baseName=$(echo "$interface" | sed -E 's/^en?p[0-9]//; s/[0-9]+$//')

    if [ -n "$baseName" ]; then
      if [ -z "${INTERFACE_MAP[$baseName]}" ]; then
        INTERFACE_MAP[$baseName]="$interface"
        BASE_NAME_COUNT[$baseName]=1
      else
        count="${BASE_NAME_COUNT[$baseName]}"
        newCount=$((count + 1))
        BASE_NAME_COUNT[$baseName]="$newCount"
        echo "WARNING: Multiple new interfaces share the base name \"$baseName\" => \"$interface\" and \"${INTERFACE_MAP[$baseName]}\""
      fi
    fi
  fi
done < <(ip a)

if [ ${#INTERFACE_MAP[@]} -eq 0 ]; then
  echo "No usable network interfaces found via 'ip a' (excluding lo/tap/veth). Exiting."
  exit 0
fi

echo
echo "=== Updating \"$CONFIG_FILE\" based on derived mappings ==="

for baseName in "${!INTERFACE_MAP[@]}"; do
  oldName="$baseName"
  newName="${INTERFACE_MAP[$baseName]}"

  if [ "$oldName" == "$newName" ]; then
    continue
  fi
  updateInterfaceNames "$oldName" "$newName"
done

echo
echo "=== Done! ==="
echo "Your network interfaces file has been updated."
echo "Original backup: \"$BACKUP_FILE\""
echo "Please review \"$CONFIG_FILE\" for correctness, then manually restart networking."
echo
