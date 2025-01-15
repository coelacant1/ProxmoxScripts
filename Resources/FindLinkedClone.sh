#!/bin/bash
#
# FindLinkedClone.sh
#
# Scans all relevant Proxmox VM or LXC configuration files in the cluster
# for any child instances derived from a specified base VM or CT ID.
#
# Usage:
#   ./FindLinkedClone.sh <BASE_VMID>
#
# Example:
#   # Find children of base VM or CT 1005
#   ./FindLinkedClone.sh 1005
#
# This script determines whether the specified <BASE_VMID> corresponds to
# a QEMU VM or LXC container, then looks for any config that references
# the storage base image named "base-<BASE_VMID>-..." within the relevant
# directory (/etc/pve/nodes/*/qemu-server/ or /etc/pve/nodes/*/lxc/).
#

source "$UTILITIES"

###############################################################################
# Check prerequisites
###############################################################################
check_root
check_proxmox
check_cluster_membership

###############################################################################
# Validate input
###############################################################################
BASE_VMID="$1"
if [ -z "$BASE_VMID" ]; then
  err "Error: No base VM ID provided. Usage: $0 <BASE_VMID>"
  exit 1
fi

###############################################################################
# Determine if BASE_VMID is a QEMU VM or LXC
###############################################################################
info "Checking if \"${BASE_VMID}\" is a QEMU VM or an LXC container..."

# We'll search for .conf files matching BASE_VMID in qemu-server and lxc
shopt -s nullglob
qemuConfigFiles=( /etc/pve/nodes/*/qemu-server/"${BASE_VMID}".conf )
lxcConfigFiles=( /etc/pve/nodes/*/lxc/"${BASE_VMID}".conf )
shopt -u nullglob

VM_TYPE=""
if [ ${#qemuConfigFiles[@]} -gt 0 ]; then
  VM_TYPE="qemu"
elif [ ${#lxcConfigFiles[@]} -gt 0 ]; then
  VM_TYPE="lxc"
else
  err "Error: Could not find VM or LXC with ID \"${BASE_VMID}\" in the cluster."
  exit 1
fi

ok "Detected base ${VM_TYPE^^} with ID \"${BASE_VMID}\"."

case "${VM_TYPE}" in
  "qemu") CFG_DIR="qemu-server" ;;
  "lxc")  CFG_DIR="lxc" ;;
esac

###############################################################################
# Collect config files across the cluster
###############################################################################
shopt -s nullglob
declare -a CONF_FILE_LIST=()
NODES=( /etc/pve/nodes/* )
info "Scanning for config files of type \"${VM_TYPE}\" on all nodes..."

for nodePath in "${NODES[@]}"; do
  [ -d "${nodePath}/${CFG_DIR}" ] || continue
  for confFile in "${nodePath}/${CFG_DIR}"/*.conf; do
    [ -e "$confFile" ] || continue
    update "Found config file: \"${confFile}\""
    CONF_FILE_LIST+=( "$confFile" )
  done
done
shopt -u nullglob

ok "Done scanning for config files."

###############################################################################
# Scan for child VMs or CTs
###############################################################################
info "Scanning for child instances from base ID \"${BASE_VMID}\"..."

declare -a CHILDREN=()
currentIndex=0
totalConfigs=${#CONF_FILE_LIST[@]}

for confFile in "${CONF_FILE_LIST[@]}"; do
  ((currentIndex=currentIndex+1))
  vmId="$(basename "$confFile" .conf)"
  nodeName="$(basename "$(dirname "$confFile")")"

  update "Scanning ${VM_TYPE^^} ${currentIndex} of ${totalConfigs} \
(on \"${nodeName}\", ID: \"${vmId}\")"

  # Skip if this instance is the same as the base
  if [ "${vmId}" == "${BASE_VMID}" ]; then
    continue
  fi

  # Look for a reference to "base-<BASE_VMID>-" in the conf file
  if grep -q "base-${BASE_VMID}-" "${confFile}"; then
    CHILDREN+=( "${vmId}" )
  fi
done

stop_spin

###############################################################################
# Report results
###############################################################################
if [ "${#CHILDREN[@]}" -eq 0 ]; then
  err "No child ${VM_TYPE^^}s found for base ID \"${BASE_VMID}\"."
  exit 0
fi

echo "Child ${VM_TYPE^^}s derived from base ID \"${BASE_VMID}\":"
for childId in "${CHILDREN[@]}"; do
  echo "\"${childId}\""
done

ok "Scan complete. Found ${#CHILDREN[@]} child ${VM_TYPE^^}(s)."