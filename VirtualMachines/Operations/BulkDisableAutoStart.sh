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
#   BulkDisableAutoStart.sh 200 210 root passw0rd
#
# Arguments:
#   start_vmid      - Starting VMID (inclusive)
#   end_vmid        - Ending VMID (inclusive)
#   ssh_username    - SSH username for nested Proxmox host
#   ssh_password    - SSH password for nested Proxmox host
#
# Notes:
#   - Must be run as root on the outer Proxmox host.
#   - Requires 'qm' with guest agent responding for reliable IP detection.
#   - SSH password auth is used (non-interactive). Keys can be adapted if desired.
#   - Only modifies autostart flags (onboot=0) within nested environment; no reboots performed.
#
# Function Index:
#   - process_vmid
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/SSH.sh
source "${UTILITYPATH}/SSH.sh"
# shellcheck source=Utilities/Discovery.sh
source "${UTILITYPATH}/Discovery.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__check_root__
__check_proxmox__
__ensure_dependencies__ jq sshpass

###############################################################################
# Helpers
###############################################################################
# IP retrieval uses utility: __get_ip_from_vmid__ (from Cluster.sh)
# SSH reachability waits via: __wait_for_ssh__ (from SSH.sh)

# disable_autostart_inner <host>
# Runs inside nested host: disable autostart for qm + pct resources.
read -r -d '' disableAutostartScript <<'EOF' || true
#!/bin/bash
set -euo pipefail

if ! command -v qm &>/dev/null; then
  echo "Not a Proxmox environment (qm missing)." >&2
  exit 1
fi

mapfile -t vms < <(qm list | awk 'NR>1 {print $1}')
for id in "${vms[@]}"; do
  if qm config "$id" | grep -q '^onboot: *1'; then
    qm set "$id" -onboot 0 >/dev/null 2>&1 || true
    echo "VM $id: onboot -> 0"
  else
    echo "VM $id: already 0 or no onboot flag"
  fi
done

if command -v pct &>/dev/null; then
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
echo "Autostart disabled for all resources."
EOF

###############################################################################
# Process a single VMID
###############################################################################
process_vmid() {
    local vmId="$1"
    local user="$2"
    local pass="$3"

    echo "========================================="
    echo "Processing VMID: $vmId"
    echo "========================================="

    local ip
    ip="$(__get_ip_from_vmid__ "$vmId" || echo "")"
    if [[ -z "$ip" ]]; then
        __warn__ "Could not get IP for VMID $vmId. Skipping."
        return
    fi
    echo "Detected IP: $ip"

    if ! __wait_for_ssh__ "$ip" 300; then
        __warn__ "SSH not reachable at $ip for VMID $vmId. Skipping."
        return
    fi

    __info__ "Disabling autostart on nested Proxmox at $ip..."
    if __ssh_exec_script__ "$ip" "$user" "$pass" "$disableAutostartScript"; then
        __ok__ "Successfully disabled autostart on VMID $vmId ($ip)."
    else
        __err__ "Failed to disable autostart on VMID $vmId ($ip)."
    fi
}

###############################################################################
# Main
###############################################################################
main() {
    # Parse arguments using ArgumentParser
    __parse_args__ "start_vmid:vmid end_vmid:vmid ssh_username:string ssh_password:string" "$@"

    __info__ "Bulk disable autostart for nested Proxmox VMs: ${START_VMID}-${END_VMID}"
    __info__ "SSH User: ${SSH_USERNAME}"

    if ! __prompt_user_yn__ "Disable autostart for VMs ${START_VMID}-${END_VMID}?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    local failed=0
    for ((vmid = START_VMID; vmid <= END_VMID; vmid++)); do
        if ! process_vmid "$vmid" "$SSH_USERNAME" "$SSH_PASSWORD"; then
            ((failed++))
        fi
    done

    echo ""
    echo "========================================="
    echo "Summary"
    echo "========================================="
    local total=$((END_VMID - START_VMID + 1))
    local success=$((total - failed))
    echo "Total VMs processed: $total"
    echo "Success: $success"
    echo "Failed: $failed"

    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
    __ok__ "All operations completed successfully"
}

main "$@"

# Testing status:
#   - 2025-11-04: Refactored to use ArgumentParser.sh declarative parsing
#   - Removed manual usage() function
#   - Removed manual argument parsing
#   - Now uses __parse_args__ with automatic validation
