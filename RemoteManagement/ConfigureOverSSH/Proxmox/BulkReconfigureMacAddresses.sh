#!/bin/bash
#
# BulkReconfigureMacAddresses.sh
#
# Examples:
#   # Using password:
#   ./AdaptMacPrefixByVMID.sh 1300 1310 root 'Sup3rSecret!'
#
#   # Using SSH key (pass '-' for password):
#   ./AdaptMacPrefixByVMID.sh 1300 1310 root - /root/.ssh/id_rsa
#
# Notes:
# - Runs on the OUTER Proxmox host.
# - Each target VM is assumed to be a Proxmox VE instance (nested).
# - We update the inner PVE's default MAC prefix in /etc/pve/datacenter.cfg (key: mac_prefix)
#   and rewrite MACs in /etc/pve/qemu-server/*.conf and /etc/pve/lxc/*.conf.
#
# Usage:
#   ./AdaptMacPrefixByVMID.sh <startVMID> <endVMID> <sshUser> <sshPasswordOrDash> [sshKeyPath]
#

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/SSH.sh"
source "${UTILITYPATH}/Conversion.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Argument Parsing
###############################################################################
if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <startVMID> <endVMID> <sshUser> <sshPasswordOrDash> [sshKeyPath]" >&2
  exit 1
fi

START_VMID="$1"
END_VMID="$2"
SSH_USER="$3"
SSH_PASS="$4"
SSH_KEY="${5:-}"

###############################################################################
# Helpers
###############################################################################
get_vm_ip_via_agent() {
  # Uses qm agent network-get-interfaces and returns first non-loopback IPv4
  local vmid="$1"
  # Retry a few times while guest boots / agent comes up
  for _ in {1..30}; do
    if qm agent "$vmid" ping >/dev/null 2>&1; then
      local json
      if json="$(qm agent "$vmid" network-get-interfaces 2>/dev/null)"; then
        local ip
        ip="$(echo "$json" \
          | jq -r '.[] | select(.name!="lo") | .["ip-addresses"][]? 
                    | select(.["ip-address-type"]=="ipv4") 
                    | .["ip-address"]' \
          | head -n1)"
        if [[ -n "${ip:-}" ]]; then
          echo "$ip"
          return 0
        fi
      fi
    fi
    sleep 2
  done
  return 1
}

ssh_inner() {
  local host="$1"; shift
  if [[ "$SSH_PASS" != "-" ]]; then
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$SSH_USER@$host" "$@"
  else
    [[ -n "$SSH_KEY" ]] || { echo "SSH key path required when password is '-'" >&2; exit 1; }
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$SSH_USER@$host" "$@"
  fi
}

scp_inner() {
  local src="$1" dst="$2"
  local host="$3"
  if [[ "$SSH_PASS" != "-" ]]; then
    sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$src" "$SSH_USER@$host:$dst"
  else
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$src" "$SSH_USER@$host:$dst"
  fi
}

vmid_to_prefix() {
  # Formats VMID -> BC:XX:YY (XX,YY are two-digit hex *strings* derived from zero-padded decimal digits)
  # Example: 1346 -> BC:13:46 ; 87 -> BC:00:87
  local vmid="$1"
  local z
  z=$(printf "%04d" "$vmid")
  local a="${z:0:2}"
  local b="${z:2:2}"
  echo "BC:${a}:${b}"
}

###############################################################################
# Pre-flight
###############################################################################

__install_or_prompt__ "jq"
__install_or_prompt__ "sshpass"

###############################################################################
# Main loop
###############################################################################
for (( VMID=START_VMID; VMID<=END_VMID; VMID++ )); do
  echo "=== Processing outer VMID $VMID ==="

  echo "Starting VM $VMID..."
  qm start "$VMID" >/dev/null || true

  echo "Waiting for QEMU Guest Agent & IP..."
  IP="$(get_vm_ip_via_agent "$VMID")" || { echo "Failed to get IP for VMID $VMID"; continue; }
  echo "Inner Proxmox IP: $IP"

  NEW_PREFIX="$(vmid_to_prefix "$VMID")"
  echo "Computed prefix for VMID $VMID -> $NEW_PREFIX"

  echo "Listing inner VMs on $IP:"
  ssh_inner "$IP" "qm list || true; pct list || true"

  # Build a one-off script to run inside the inner PVE
  TMP_SCRIPT="$(mktemp)"
  cat >"$TMP_SCRIPT" <<'INNER_EOF'
#!/bin/bash
set -euo pipefail

NEW_PREFIX="$1"   # e.g., BC:13:46

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
  # QEMU VM lines: netX: <model>=AA:BB:CC:DD:EE:FF,...
  sed -i -E \
    "s/(net[0-9]+:[[:space:]]*[^=]+=)[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})/\1$UPREFIX:\2/g" \
    "$file"

  # LXC lines: ... hwaddr=AA:BB:CC:DD:EE:FF
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
INNER_EOF

  # Copy & run inside
  scp_inner "$TMP_SCRIPT" "/root/_mac_update.sh" "$IP"
  rm -f "$TMP_SCRIPT"

  echo "Applying MAC prefix & rewriting inner VM configs on $IP ..."
  ssh_inner "$IP" "bash /root/_mac_update.sh '$NEW_PREFIX'"

  echo "Verification (post-change) on $IP:"
  ssh_inner "$IP" "grep -H \"^mac_prefix\" /etc/pve/datacenter.cfg || true"
  ssh_inner "$IP" "qm list | awk 'NR==1 || NR>1{print}'"
  ssh_inner "$IP" "pct list || true"

  echo "=== Completed outer VMID $VMID ==="
  echo
done

echo "All done."
