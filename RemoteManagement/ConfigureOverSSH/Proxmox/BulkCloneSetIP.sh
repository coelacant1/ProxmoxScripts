#!/bin/bash
#
# BulkCloneSetIPDebian.sh
#
# Clones a Debian-based VM multiple times, updates each clone's IP/network,
# sets a default gateway, and restarts networking. Uses SSH with username/password.
# ALSO: for each cloned VM (assumed to be a Proxmox-in-VM), set datacenter mac_prefix
#       to BC:<VMID[0..1]>:<VMID[2..3]> and rewrite existing VM/LXC MACs to that prefix.
#
# Usage:
#   ./BulkCloneSetIPDebian.sh <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId> <sshUsername> <sshPassword> <vmNamePrefix>
#
# Example:
#   ./BulkCloneSetIPDebian.sh 172.20.83.22 172.20.83.100/24 172.20.83.1 5 100 200 root pass123 CLOUD-
#

set -euo pipefail

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/SSH.sh"
source "${UTILITYPATH}/Conversion.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

__install_or_prompt__ "jq"
__install_or_prompt__ "sshpass"

###############################################################################
# Argument Parsing
###############################################################################
if [ "$#" -lt 9 ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId> <sshUsername> <sshPassword> <vmNamePrefix>"
  exit 1
fi

templateIpAddr="$1"
startIpCidr="$2"
newGateway="$3"
instanceCount="$4"
templateId="$5"
baseVmId="$6"
sshUsername="$7"
sshPassword="$8"
vmNamePrefix="$9"

IFS='/' read -r startIpAddrOnly startMask <<<"$startIpCidr"
ipInt="$(__ip_to_int__ "$startIpAddrOnly")"

###############################################################################
# Helpers
###############################################################################
# Get first non-loopback IPv4 from guest agent (with retries)
get_ip_via_agent() {
  local vmid="$1"
  for _ in {1..30}; do
    if qm agent "$vmid" ping >/dev/null 2>&1; then
      local json ip
      if json="$(qm agent "$vmid" network-get-interfaces 2>/dev/null)"; then
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

# Compute BC:<VMID[0..1]>:<VMID[2..3]> from decimal VMID (zero-padded to 4 digits)
vmid_to_prefix() {
  local vmid="$1"
  local z; z=$(printf "%04d" "$vmid")
  echo "BC:${z:0:2}:${z:2:2}"
}

# Run a command on the child via SSH
ssh_child() {
  local host="$1"; shift
  sshpass -p "$sshPassword" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$sshUsername@$host" "$@"
}

# Copy a file to the child via SCP
scp_child() {
  local src="$1" dst="$2" host="$3"
  sshpass -p "$sshPassword" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$src" "$sshUsername@$host:$dst"
}

###############################################################################
# Main Logic
###############################################################################
for ((i=0; i<instanceCount; i++)); do
  currentVmId=$((baseVmId + i))
  currentIp="$(__int_to_ip__ "$ipInt")"
  currentIpCidr="$currentIp/$startMask"

  echo "Cloning VM ID \"$templateId\" to new VM ID \"$currentVmId\" with IP \"$currentIpCidr\"..."
  qm clone "$templateId" "$currentVmId" --name "${vmNamePrefix}${currentVmId}" >/dev/null
  echo "Starting VM \"$currentVmId\"..."
  qm start "$currentVmId" >/dev/null || true

  __wait_for_ssh__ "$templateIpAddr" "$sshUsername" "$sshPassword"

  sshpass -p "$sshPassword" ssh -o StrictHostKeyChecking=no "$sshUsername@$templateIpAddr" bash -s <<EOF
sed -i '/\bgateway\b/d' /etc/network/interfaces
sed -i "s#${templateIpAddr}/[0-9]\\+#${currentIpCidr}#g" /etc/network/interfaces
sed -i "\#address ${currentIpCidr}#a gateway ${newGateway}" /etc/network/interfaces
TAB="\$(printf '\\t')"
sed -i "s|^[[:space:]]*gateway\\(.*\\)|\${TAB}gateway\\1|" /etc/network/interfaces
EOF

  sshpass -p "$sshPassword" ssh -o StrictHostKeyChecking=no "$sshUsername@$templateIpAddr" \
    "nohup sh -c 'sleep 2; systemctl restart networking' >/dev/null 2>&1 &"

  __wait_for_ssh__ "$currentIp" "$sshUsername" "$sshPassword"

  # --- Child Proxmox: set datacenter mac_prefix and rewrite existing MACs ----
  newPrefix="$(vmid_to_prefix "$currentVmId")"
  echo "Computed MAC prefix for VMID $currentVmId: $newPrefix"

  # Build + push inner script
  tmpInner="$(mktemp)"
  cat >"$tmpInner" <<'INNER_EOF'
#!/usr/bin/env bash
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
  # QEMU VMs: netX: <model>=AA:BB:CC:DD:EE:FF,...
  sed -i -E \
    "s/(net[0-9]+:[[:space:]]*[^=]+=)[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})/\1$UPREFIX:\2/g" \
    "$file"
  # LXC: ... hwaddr=AA:BB:CC:DD:EE:FF
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

echo "Reloading pvedaemon (non-disruptive) ..."
systemctl reload pvedaemon 2>/dev/null || true

echo "Done."
INNER_EOF

  echo "Copying inner MAC-update script to $currentIp ..."
  scp_child "$tmpInner" "/root/_mac_update.sh" "$currentIp"
  rm -f "$tmpInner"

  echo "Applying MAC prefix + rewriting child VMs on $currentIp ..."
  ssh_child "$currentIp" "bash /root/_mac_update.sh '$newPrefix'"

  echo "Verification on $currentIp:"
  ssh_child "$currentIp" "grep -H '^mac_prefix' /etc/pve/datacenter.cfg || true"
  ssh_child "$currentIp" "qm list || true; pct list || true"

  # Next IP
  ipInt=$((ipInt + 1))
  echo "----- Completed VM $currentVmId ($currentIp) -----"
done

###############################################################################
# Testing status
###############################################################################
# Tested single-node
