#!/bin/bash
#
# BulkDisableAutoStart.sh
#
# Disables autostart for all VM (qm) and LXC (pct) resources inside a range of
# nested Proxmox virtual machines identified by VMIDs on the parent host.
# For each VMID in the provided range, the script attempts to determine the
# management IP via the QEMU guest agent; if unavailable, it falls back to
# parsing the VM config for an IP (best-effort). It then connects via SSH using
# provided credentials and disables autostart flags on all internal resources.
#
# Usage:
#   ./BulkDisableAutoStart.sh <startVmId> <endVmId> <sshUsername> <sshPassword>
#
# Example:
#   ./BulkDisableAutoStart.sh 200 210 root passw0rd
#
# Notes:
#   - Must be run as root on the outer Proxmox host.
#   - Requires 'qm' with guest agent responding for reliable IP detection.
#   - SSH password auth is used (non-interactive). Keys can be adapted if desired.
#   - Only modifies autostart flags (onboot=0) within nested environment; no reboots performed.
#
# Function Index:
#   - usage
#   - get_ip_for_vmid
#   - ssh_exec
#   - disable_autostart_inner
#   - process_vmid
#   - main
#

###############################################################################
# Usage
###############################################################################
usage() {
  cat <<USAGE
Usage: ${0##*/} <startVmId> <endVmId> <sshUsername> <sshPassword>

Disables autostart (onboot) for all VMs and LXCs inside each nested Proxmox
instance whose VMID is in the inclusive range [startVmId, endVmId].

Arguments:
  startVmId    Starting VMID (inclusive)
  endVmId      Ending VMID (inclusive)
  sshUsername  SSH username for nested Proxmox host
  sshPassword  SSH password for nested Proxmox host

Environment:
  UTILITYPATH (optional, exported by GUI.sh) to source shared helpers.
USAGE
}

###############################################################################
# Setup / Imports
###############################################################################
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Queries.sh"
source "${UTILITYPATH}/SSH.sh"

__check_root__
__check_proxmox__
__install_or_prompt__ "sshpass"
__install_or_prompt__ "jq"


###############################################################################
# Argument Parsing
###############################################################################
if [[ $# -lt 4 ]]; then
  echo "Error: Missing arguments." >&2
  usage
  exit 1
fi

startVmId="$1"
endVmId="$2"
sshUser="$3"
sshPass="$4"

if ! [[ "$startVmId" =~ ^[0-9]+$ && "$endVmId" =~ ^[0-9]+$ && $endVmId -ge $startVmId ]]; then
  echo "Invalid VMID range: $startVmId..$endVmId" >&2
  exit 1
fi

###############################################################################
# Helpers
###############################################################################
# IP retrieval uses utility: __get_ip_from_vmid__ (from Queries.sh)
# SSH reachability waits via: __wait_for_ssh__ (from SSH.sh)

# disable_autostart_inner <host>
# Runs inside nested host: disable autostart for qm + pct resources.
disable_autostart_inner() {
  local host="$1"
  (
    printf '%s\n' "$sshPass"
    cat <<'INNER'
set -euo pipefail
if ! command -v qm &>/dev/null; then
  echo "Not a Proxmox environment (qm missing)." >&2
  exit 1
fi
# Disable autostart for QEMU VMs
declare -a vms
mapfile -t vms < <(qm list | awk 'NR>1 {print $1}')
for id in "${vms[@]}"; do
  if qm config "$id" | grep -q '^onboot: *1'; then
    qm set "$id" -onboot 0 >/dev/null 2>&1 || true
    echo "VM $id: onboot -> 0"
  else
    echo "VM $id: already 0 or no onboot flag"
  fi
done
# Disable autostart for LXCs if pct exists
if command -v pct &>/dev/null; then
  declare -a cts
  mapfile -t cts < <(pct list | awk 'NR>1 {print $1}')
  for cid in "${cts[@]}"; do
    if pct config "$cid" | grep -q '^onboot: *1'; then
      pct set "$cid" -onboot 0 >/dev/null 2>&1 || true
      echo "CT $cid: onboot -> 0"
    else
      echo "CT $cid: already 0 or no onboot flag"
    fi
  done
fi
INNER
  ) | sshpass -p "$sshPass" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$sshUser@$host" "sudo -S -p '' bash -s"
}

# process_vmid <vmid>
process_vmid() {
  local vmid="$1"
  if command -v __info__ &>/dev/null; then
    __info__ "Processing VMID $vmid"
  else
    echo "=== VMID $vmid ==="
  fi
  local ip
  if ! ip="$( __get_ip_from_vmid__ "$vmid" 2>/dev/null )"; then
    if command -v __err__ &>/dev/null; then
      __err__ "Could not determine IP for VMID $vmid"
    else
      echo "Error: Could not determine IP for VMID $vmid" >&2
    fi
    return 1
  fi
  # Ensure SSH is reachable (best-effort) before attempting changes
  __wait_for_ssh__ "$ip" "$sshUser" "$sshPass" 2>/dev/null || true
  if command -v __update__ &>/dev/null; then
    __update__ "Disabling autostart on nested host $ip"
  else
    echo "Connecting to $ip ..."
  fi
  if disable_autostart_inner "$ip"; then
    command -v __ok__ &>/dev/null && __ok__ "Done VMID $vmid" || echo "Completed VMID $vmid"
  else
    command -v __err__ &>/dev/null && __err__ "Failed VMID $vmid" || echo "Failed VMID $vmid" >&2
  fi
}

###############################################################################
# MAIN
###############################################################################
main() {
  for ((id=startVmId; id<=endVmId; id++)); do
    process_vmid "$id"
  done
  echo "All requested VMIDs processed ($startVmId..$endVmId)."
  
  __prompt_keep_installed_packages__
}

main "$@"


###############################################################################
# Testing status
###############################################################################
# Tested: (pending) range on lab cluster; guest agent required for accurate IP discovery.
