#!/bin/bash
#
# BulkReconfigureMacAddresses.sh
#
# Reconfigures MAC address prefixes for nested Proxmox VE instances (Proxmox-in-VM).
# For each target VM (assumed to be a Proxmox VE instance), this script:
# 1. Computes a unique MAC prefix based on the VMID using __vmid_to_mac_prefix__
# 2. Updates the inner PVE's datacenter.cfg with the new mac_prefix
# 3. Rewrites existing VM/CT MAC addresses in /etc/pve/qemu-server/*.conf and /etc/pve/lxc/*.conf
# 4. Reloads pvedaemon to apply changes
#
# Usage:
#   BulkReconfigureMacAddresses.sh <start_vmid> <end_vmid> <ssh_username> <ssh_password_or_dash> [ssh_key_path]
#
# Arguments:
#   start_vmid            - Starting VMID (outer Proxmox host)
#   end_vmid              - Ending VMID (outer Proxmox host)
#   ssh_username          - SSH username for nested Proxmox instances
#   ssh_password_or_dash  - SSH password, or '-' to use SSH key
#   ssh_key_path          - Path to SSH private key (required if password is '-')
#
# Examples:
#   # Using password:
#   BulkReconfigureMacAddresses.sh 1300 1310 root 'Sup3rSecret!'
#
#   # Using SSH key (pass '-' for password):
#   BulkReconfigureMacAddresses.sh 1300 1310 root - /root/.ssh/id_rsa
#
# Function Index:
#   - rewrite_file_mac_prefix
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/SSH.sh
source "${UTILITYPATH}/SSH.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Conversion.sh
source "${UTILITYPATH}/Conversion.sh"
# shellcheck source=Utilities/Discovery.sh
source "${UTILITYPATH}/Discovery.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Hybrid parsing: complex SSH auth pattern
if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <startVMID> <endVMID> <sshUser> <sshPasswordOrDash> [sshKeyPath]" >&2
    exit 64
fi

START_VMID="$1"
END_VMID="$2"
SSH_USER="$3"
SSH_PASS="$4"
SSH_KEY="${5:-}"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Helpers
###############################################################################
if [[ "$SSH_PASS" == "-" ]]; then
    if [[ -z "$SSH_KEY" ]]; then
        echo "Error: SSH key path required when password is '-'" >&2
        exit 1
    fi
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "Error: SSH key '$SSH_KEY' not found." >&2
        exit 1
    fi
    __ensure_dependencies__ jq
else
    __ensure_dependencies__ jq sshpass
fi

read -r -d '' macUpdateScript <<'EOF' || true
#!/bin/bash
set -euo pipefail

NEW_PREFIX="$1"

if [[ ! "$NEW_PREFIX" =~ ^([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2}):([0-9A-Fa-f]{2})$ ]]; then
  echo "Invalid prefix: $NEW_PREFIX" >&2
  exit 1
fi

UPREFIX="$(echo "$NEW_PREFIX" | tr '[:lower:]' '[:upper:]')"
echo "Setting datacenter mac_prefix to $UPREFIX ..."

if [[ ! -d /etc/pve ]]; then
  echo "/etc/pve not found; is this a Proxmox VE system?" >&2
  exit 1
fi

DCFG="/etc/pve/datacenter.cfg"
touch "$DCFG"
if grep -q '^mac_prefix:' "$DCFG"; then
  sed -i -E "s|^mac_prefix:.*$|mac_prefix: $UPREFIX|" "$DCFG"
else
  printf "\nmac_prefix: %s\n" "$UPREFIX" >> "$DCFG"
fi

rewrite_file_mac_prefix() {
  local file="$1"
  sed -i -E \
    "s/(net[0-9]+:[[:space:]]*[^=]+=)[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})/\1$UPREFIX:\2/g" \
    "$file"

  sed -i -E \
    "s/(hwaddr=)[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})/\1$UPREFIX:\2/g" \
    "$file"
}

echo "Rewriting existing VM/LXC MAC prefixes to $UPREFIX ..."
shopt -s nullglob
for f in /etc/pve/qemu-server/*.conf; do
  rewrite_file_mac_prefix "$f"
done
for f in /etc/pve/lxc/*.conf; do
  rewrite_file_mac_prefix "$f"
done

echo "Reloading pvedaemon to reflect datacenter changes ..."
systemctl reload pvedaemon 2>/dev/null || true

echo "Done on this node."
EOF

###############################################################################
# Pre-flight
###############################################################################

###############################################################################
# Main loop
###############################################################################
for ((VMID = START_VMID; VMID <= END_VMID; VMID++)); do
    echo "=== Processing outer VMID $VMID ==="

    echo "Starting VM $VMID..."
    qm start "$VMID" >/dev/null || true

    echo "Waiting for QEMU Guest Agent & IP..."
    if ! IP="$(__get_ip_from_guest_agent__ --vmid "$VMID" --retries 60 --delay 2)"; then
        echo "Failed to get IP for VMID $VMID"
        continue
    fi
    echo "Inner Proxmox IP: $IP"

    NEW_PREFIX="$(__vmid_to_mac_prefix__ --vmid "$VMID")"
    echo "Computed prefix for VMID $VMID -> $NEW_PREFIX"

    if [[ "$SSH_PASS" != "-" ]]; then
        __wait_for_ssh__ "$IP" "$SSH_USER" "$SSH_PASS" 2>/dev/null || true
    fi

    connection_flags=(--host "$IP" --user "$SSH_USER")
    if [[ "$SSH_PASS" == "-" ]]; then
        connection_flags+=(--identity "$SSH_KEY")
    else
        connection_flags+=(--password "$SSH_PASS")
    fi

    echo "Listing inner VMs on $IP:"
    __ssh_exec__ \
        "${connection_flags[@]}" \
        --sudo \
        --shell bash \
        --command "qm list || true; pct list || true"

    echo "Applying MAC prefix & rewriting inner VM configs on $IP ..."
    __ssh_exec_script__ \
        "${connection_flags[@]}" \
        --sudo \
        --script-content "$macUpdateScript" \
        --arg "$NEW_PREFIX"

    echo "Verification (post-change) on $IP:"
    __ssh_exec__ \
        "${connection_flags[@]}" \
        --sudo \
        --command "grep -H '^mac_prefix' /etc/pve/datacenter.cfg || true"
    __ssh_exec__ \
        "${connection_flags[@]}" \
        --sudo \
        --shell bash \
        --command "qm list | awk 'NR==1 || NR>1{print}'"
    __ssh_exec__ \
        "${connection_flags[@]}" \
        --sudo \
        --command "pct list || true"

    echo "=== Completed outer VMID $VMID ==="
    echo
done

echo "All done."

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Fixed script name in header (was AdaptMacPrefixByVMID.sh)
# - 2025-11-24: Updated header documentation to match actual functionality
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

