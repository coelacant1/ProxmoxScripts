#!/bin/bash
#
# BulkUnmountISOs.sh
#
# Unmounts (detaches) all ISO images from every QEMU VM inside a range of nested
# Proxmox virtual machines (outer host VMIDs). For each outer VMID in the range,
# this script determines the nested host's IP, SSHes in, enumerates internal
# VMs (qm list), and removes any attached ISO (cdrom) devices by setting them to
# 'none'. It skips entries already unset. LXC containers are unaffected.
#
# Usage:
#   BulkUnmountISOs.sh <startVmId> <endVmId> <sshUsername> <sshPassword>
#
# Example:
#   BulkUnmountISOs.sh 200 210 root passw0rd
#
# Notes:
#   - Must be run as root on the outer Proxmox host.
#   - Requires guest IP resolvable via __get_ip_from_vmid__ from Queries.sh.
#   - SSH password authentication used for simplicity (adapt to keys if desired).
#   - Only modifies nested QEMU VM configs by clearing ISO from IDE/SCSI cdrom.
#
# Function Index:
#   - usage
#   - unmount_isos_inner
#   - process_vmid
#   - main
#

set -euo pipefail

###############################################################################
# Usage
###############################################################################
usage() {
  cat <<USAGE
Usage:
  ${0##*/} <startVmId> <endVmId> <sshUsername> <sshPassword>

Unmount (detach) all ISO media from every QEMU VM inside each nested Proxmox
instance in the inclusive VMID range.

Arguments:
  startVmId    Starting outer VMID (inclusive)
  endVmId      Ending outer VMID (inclusive)
  sshUsername  SSH username for nested host
  sshPassword  SSH password for nested host

Environment:
  UTILITYPATH must be exported (GUI.sh sets it) to source shared helpers.
USAGE
}

###############################################################################
# Imports / Checks
###############################################################################
trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Queries.sh"
source "${UTILITYPATH}/SSH.sh"

__check_root__
__check_proxmox__
__ensure_dependencies__ jq sshpass

###############################################################################
# Args
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
# Inner operation
###############################################################################
# unmount_isos_inner <host>
read -r -d '' unmountIsosScript <<'EOF' || true
#!/bin/bash
set -euo pipefail

if ! command -v qm &>/dev/null; then
  echo "Not a Proxmox environment (qm missing)." >&2
  exit 1
fi

mapfile -t vms < <(qm list | awk 'NR>1 {print $1}')
if (( ${#vms[@]} == 0 )); then
  echo "No VMs found inside nested host."
  exit 0
fi

for id in "${vms[@]}"; do
  cfg="$(qm config "$id")" || continue
  changed=0

  while IFS= read -r line; do
    bus="${line%%:*}"
    if [[ "$line" =~ iso/.*\.iso ]] || [[ "$line" =~ media=cdrom ]]; then
      echo "Clearing ISO on VM $id ($bus)"
      qm set "$id" -delete "$bus" >/dev/null 2>&1 || true
      qm set "$id" -$bus none,media=cdrom >/dev/null 2>&1 || true
      changed=1
    fi
  done < <(echo "$cfg" | grep -E '^(ide|scsi|sata)[0-9]+:')

  if (( changed == 0 )); then
    echo "VM $id: no ISO attachments to clear"
  fi
done
EOF

unmount_isos_inner() {
  local host="$1"
  __ssh_exec_script__ \
    --host "$host" \
    --user "$sshUser" \
    --password "$sshPass" \
    --sudo \
    --script-content "$unmountIsosScript"
}

###############################################################################
# process_vmid <vmid>
###############################################################################
process_vmid() {
  local vmid="$1"
  if command -v __info__ &>/dev/null; then
    __info__ "Processing VMID $vmid"
  else
    echo "=== VMID $vmid ==="
  fi
  local ip
  if ! ip="$( __get_ip_from_vmid__ "$vmid" 2>/dev/null )"; then
    command -v __err__ &>/dev/null && __err__ "Could not resolve IP for $vmid" || echo "Error: No IP for $vmid" >&2
    return 1
  fi
  __wait_for_ssh__ "$ip" "$sshUser" "$sshPass" 2>/dev/null || true
  command -v __update__ &>/dev/null && __update__ "Unmounting ISOs on $ip" || echo "Unmounting on $ip ..."
  if unmount_isos_inner "$ip"; then
    command -v __ok__ &>/dev/null && __ok__ "Done $vmid" || echo "Completed $vmid"
  else
    command -v __err__ &>/dev/null && __err__ "Failed $vmid" || echo "Failed $vmid" >&2
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
# Tested: (pending) Lab nested cluster; validation requires VMs with ISO attached.
