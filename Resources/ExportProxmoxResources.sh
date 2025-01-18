#!/bin/bash
#
# ExportProxmoxResources.sh
#
# Exports Proxmox VM and LXC details from config files in /etc/pve/nodes to a CSV file.
#
# Usage:
#   ./ExportProxmoxResources.sh [lxc|vm|both]
#
# Examples:
#   # Exports only LXC containers
#   ./ExportProxmoxResources.sh lxc
#
#   # Exports only VMs
#   ./ExportProxmoxResources.sh vm
#
#   # Exports both LXC containers and VMs
#   ./ExportProxmoxResources.sh both
#
# Function Index:
#   - parse_config_files
#

source "$UTILITIES"

###############################################################################
# Environment Checks
###############################################################################
check_root
check_proxmox

###############################################################################
# Parse Arguments
###############################################################################
RESOURCE_TYPE="both"
if [[ "$1" == "lxc" || "$1" == "vm" ]]; then
  RESOURCE_TYPE="$1"
elif [[ "$1" == "both" ]]; then
  RESOURCE_TYPE="both"
fi

###############################################################################
# Global Variables
###############################################################################
OUTPUT_FILE="cluster_resources.csv"

###############################################################################
# Initialize CSV Header
###############################################################################
echo "Node,VMID,Name,CPU,Memory(MB),Disk(GB)" > "$OUTPUT_FILE"

###############################################################################
# Function: parse_config_files
#   Parses QEMU (VM) or LXC config files for a given node and appends data to CSV
###############################################################################
parse_config_files() {
  local nodeName="$1"
  local resourceType="$2"
  local configDir
  local configFile
  local vmId
  local vmName
  local cpuCores
  local memoryMb
  local diskGb

  # Parse QEMU VM config if requested
  if [[ "$resourceType" == "both" || "$resourceType" == "vm" ]]; then
    configDir="/etc/pve/nodes/$nodeName/qemu-server"
    if [[ -d "$configDir" ]]; then
      for configFile in "$configDir"/*.conf; do
        [[ -f "$configFile" ]] || continue
        vmId="$(basename "$configFile" .conf)"
        vmName="$(grep -Po '^name: \K.*' "$configFile")"
        cpuCores="$(grep -Po '^cores: \K.*' "$configFile")"
        memoryMb="$(grep -Po '^memory: \K.*' "$configFile")"

        diskGb="$(grep -Po 'size=\K[0-9]+[A-Z]?' "$configFile" | awk '
          {
            if ($1 ~ /G$/) sum += substr($1, 1, length($1)-1)
            else if ($1 ~ /M$/) sum += substr($1, 1, length($1)-1) / 1024
            else if ($1 ~ /K$/) sum += substr($1, 1, length($1)-1) / (1024 * 1024)
            else sum += $1 / (1024 * 1024 * 1024)
          }
          END {print sum}
        ')"

        echo "$nodeName,$vmId,$vmName,$cpuCores,$(( memoryMb / 1024 )),$diskGb" >> "$OUTPUT_FILE"
      done
    fi
  fi

  # Parse LXC config if requested
  if [[ "$resourceType" == "both" || "$resourceType" == "lxc" ]]; then
    configDir="/etc/pve/nodes/$nodeName/lxc"
    if [[ -d "$configDir" ]]; then
      for configFile in "$configDir"/*.conf; do
        [[ -f "$configFile" ]] || continue
        vmId="$(basename "$configFile" .conf)"
        vmName="$(grep -Po '^hostname: \K.*' "$configFile")"
        cpuCores="$(grep -Po '^cores: \K.*' "$configFile")"
        memoryMb="$(grep -Po '^memory: \K.*' "$configFile")"

        diskGb="$(grep -Po 'size=\K[0-9]+[A-Z]?' "$configFile" | awk '
          {
            if ($1 ~ /G$/) sum += substr($1, 1, length($1)-1)
            else if ($1 ~ /M$/) sum += substr($1, 1, length($1)-1) / 1024
            else if ($1 ~ /K$/) sum += substr($1, 1, length($1)-1) / (1024 * 1024)
            else sum += $1 / (1024 * 1024 * 1024)
          }
          END {print sum}
        ')"

        echo "$nodeName,$vmId,$vmName,$cpuCores,$(( memoryMb / 1024 )),$diskGb" >> "$OUTPUT_FILE"
      done
    fi
  fi
}

###############################################################################
# Main Logic
###############################################################################
NODES="$(ls /etc/pve/nodes)"
for node in $NODES; do
  parse_config_files "$node" "$RESOURCE_TYPE"
done

echo "Resource export completed! Output saved to \"$OUTPUT_FILE\"."
