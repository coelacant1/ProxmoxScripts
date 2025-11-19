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
#   BulkCloneSetIPDebian.sh <templateIp> <startIpCIDR> <newGateway> <count> <templateId> <baseVmId> <sshUsername> <sshPassword> <vmNamePrefix>
#
# Example:
#   BulkCloneSetIPDebian.sh 192.168.1.22 192.168.1.100/24 192.168.1.1 5 100 200 root pass123 CLOUD-
#
# Function Index:
#   - rewrite_file_mac_prefix
#

set -euo pipefail

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/SSH.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Conversion.sh
source "${UTILITYPATH}/Conversion.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

__ensure_dependencies__ sshpass

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
# Main Logic
###############################################################################
read -r -d '' networkUpdateScript <<'EOF' || true
#!/bin/bash
set -euo pipefail

templateIp="$1"
currentIpCidr="$2"
newGateway="$3"

sed -i '/\bgateway\b/d' /etc/network/interfaces
sed -i "s#${templateIp}/[0-9]\\+#${currentIpCidr}#g" /etc/network/interfaces
sed -i "\#address ${currentIpCidr}#a gateway ${newGateway}" /etc/network/interfaces
TAB="$(printf '\t')"
sed -i "s|^[[:space:]]*gateway\\(.*\\)|${TAB}gateway\\1|" /etc/network/interfaces
EOF

read -r -d '' macUpdateScript <<'EOF' || true
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
EOF

for ((i = 0; i < instanceCount; i++)); do
    currentVmId=$((baseVmId + i))
    currentIp="$(__int_to_ip__ "$ipInt")"
    currentIpCidr="$currentIp/$startMask"

    echo "Cloning VM ID \"$templateId\" to new VM ID \"$currentVmId\" with IP \"$currentIpCidr\"..."
    qm clone "$templateId" "$currentVmId" --name "${vmNamePrefix}${currentVmId}" >/dev/null
    echo "Starting VM \"$currentVmId\"..."
    qm start "$currentVmId" >/dev/null || true

    __wait_for_ssh__ "$templateIpAddr" "$sshUsername" "$sshPassword"
    __ssh_exec_script__ \
        --host "$templateIpAddr" \
        --user "$sshUsername" \
        --password "$sshPassword" \
        --sudo \
        --script-content "$networkUpdateScript" \
        --arg "$templateIpAddr" \
        --arg "$currentIpCidr" \
        --arg "$newGateway"

    __ssh_exec__ \
        --host "$templateIpAddr" \
        --user "$sshUsername" \
        --password "$sshPassword" \
        --sudo \
        --shell bash \
        --command "nohup sh -c 'sleep 2; systemctl restart networking' >/dev/null 2>&1 &"

    __wait_for_ssh__ "$currentIp" "$sshUsername" "$sshPassword"

    # --- Child Proxmox: set datacenter mac_prefix and rewrite existing MACs ----
    newPrefix="$(__vmid_to_mac_prefix__ --vmid "$currentVmId")"
    echo "Computed MAC prefix for VMID $currentVmId: $newPrefix"

    __ssh_exec_script__ \
        --host "$currentIp" \
        --user "$sshUsername" \
        --password "$sshPassword" \
        --sudo \
        --script-content "$macUpdateScript" \
        --arg "$newPrefix"

    echo "Verification on $currentIp:"
    __ssh_exec__ \
        --host "$currentIp" \
        --user "$sshUsername" \
        --password "$sshPassword" \
        --sudo \
        --command "grep -H '^mac_prefix' /etc/pve/datacenter.cfg || true"
    __ssh_exec__ \
        --host "$currentIp" \
        --user "$sshUsername" \
        --password "$sshPassword" \
        --sudo \
        --shell bash \
        --command "qm list || true; pct list || true"

    # Next IP
    ipInt=$((ipInt + 1))
    echo "----- Completed VM $currentVmId ($currentIp) -----"
done

###############################################################################
# Testing status
###############################################################################
# Tested single-node
