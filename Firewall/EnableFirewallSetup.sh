#!/bin/bash
#
# EnableFirewallSetup.sh
#
# This script enables the firewall on the Proxmox VE datacenter and all nodes, then configures:
#   1. An IP set ("proxmox-nodes") containing the cluster interface IPs of each node.
#   2. Rules to allow:
#       - internal node-to-node traffic,
#       - Ceph traffic (including msgr2 on port 3300),
#       - SSH (22) and Proxmox Web GUI (8006) from a specified management subnet,
#       - VXLAN traffic (UDP 4789 by default) within the node subnet.
#   3. (Optional) Sets default inbound policy to DROP for the datacenter firewall (commented by default).
#
# Usage:
#   ./EnableFirewallSetup.sh <management_subnet/netmask>
#   e.g., ./EnableFirewallSetup.sh 10.0.0.0/24
#
# Notes:
#   - Requires passwordless SSH or valid credentials for root on each node (uses "ssh").
#   - Adjust the CLUSTER_INTERFACE variable to match your environment (e.g., "vmbr0", "vmbr1").
#   - Re-running the script should *not* duplicate existing rules or IP set entries, thanks to checks.
#
# Example:
#   ./EnableFirewallSetup.sh 192.168.1.0/24
#

set -e

# ----------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# ----------------------------------------------------------------------------
find_utilities_script() {
  # Check current directory first
  if [[ -d "./Utilities" ]]; then
    echo "./Utilities"
    return 0
  fi

  local rel_path=""
  for _ in {1..15}; do
    cd ..
    # If rel_path is empty, set it to '..' else prepend '../'
    if [[ -z "$rel_path" ]]; then
      rel_path=".."
    else
      rel_path="../$rel_path"
    fi

    if [[ -d "./Utilities" ]]; then
      echo "$rel_path/Utilities"
      return 0
    fi
  done

  echo "Error: Could not find 'Utilities' folder within 15 levels." >&2
  return 1
}

###############################################################################
# Locate and source the Utilities script
###############################################################################
UTILITIES_DIR="$(find_utilities_script)"
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# Prompt to remove newly installed packages at script exit
###############################################################################
trap prompt_keep_installed_packages EXIT

###############################################################################
# CONFIGURATION
###############################################################################
# Which interface holds the *cluster/storage* IP address on each node?
# Adjust this to the actual interface in your environment (e.g., "vmbr1" or "eth1").
CLUSTER_INTERFACE="vmbr0"

# By default, we assume VXLAN uses UDP port 4789. Change if your environment differs.
VXLAN_PORT="4789"

###############################################################################
# HELPER FUNCTIONS
###############################################################################

# Check if a given CIDR is already in the proxmox-nodes IP set
ipset_contains_cidr() {
  local cidr="$1"
  local existing
  # pvesh get /cluster/firewall/ipset/proxmox-nodes returns a JSON array
  # Each entry is an object with "cidr": "x.x.x.x/yy"
  existing=$(
    pvesh get /cluster/firewall/ipset/proxmox-nodes --output-format json 2>/dev/null \
      | jq -r '.[].cidr'
  )

  if echo "$existing" | grep -qx "$cidr"; then
    return 0  # Found
  else
    return 1  # Not found
  fi
}

# Check if a firewall rule with a particular comment already exists
rule_exists_by_comment() {
  local comment="$1"
  # pvesh get /cluster/firewall/rules returns a JSON array of firewall rules
  # Each entry can have a "comment" field.
  local existing_comments
  existing_comments=$(
    pvesh get /cluster/firewall/rules --output-format json 2>/dev/null \
      | jq -r '.[].comment // empty'
  )
  if echo "$existing_comments" | grep -Fxq "$comment"; then
    return 0
  else
    return 1
  fi
}

# Create a firewall rule only if it doesn't already exist (based on comment)
create_rule_once() {
  local comment="$1"
  shift
  if rule_exists_by_comment "$comment"; then
    echo " - Rule with comment '$comment' already exists, skipping."
  else
    pvesh create /cluster/firewall/rules "$@" --comment "$comment"
    echo " - Created new rule: $comment"
  fi
}

###############################################################################
# MAIN SCRIPT
###############################################################################

# 1. Ensure we are root on a Proxmox node
check_proxmox_and_root

# 2. Make sure we have the needed commands
install_or_prompt "jq"
install_or_prompt "ssh"

# 3. Check that we're in a cluster
check_cluster_membership

# 4. Parse management subnet
if [ -z "$1" ]; then
  echo "Usage: $0 <management_subnet>"
  echo "Example: $0 192.168.1.0/24"
  exit 1
fi

MANAGEMENT_SUBNET="$1"

echo "Management Subnet: $MANAGEMENT_SUBNET"
echo "Cluster Interface: $CLUSTER_INTERFACE"
echo

# 5. Gather node names and IPs
#    We SSH into each node and get the IP address from the specified interface.
# Get IP of the local node (first IPv4 address reported by hostname -I)
echo "=== Collecting IPs for all nodes ==="
LOCAL_NODE_IP="$(hostname -I | awk '{print $1}')"

# Gather remote node IPs (excludes local)
readarray -t REMOTE_NODE_IPS < <(get_remote_node_ips)

# Combine local + remote
NODE_IPS=("$LOCAL_NODE_IP" "${REMOTE_NODE_IPS[@]}")
echo

# 6. Create the proxmox-nodes IP set if it doesn’t exist
if ! pvesh get /cluster/firewall/ipset --output-format json 2>/dev/null | jq -r '.[].name' | grep -qx 'proxmox-nodes'; then
  echo "Creating IP set 'proxmox-nodes'..."
  pvesh create /cluster/firewall/ipset --name proxmox-nodes --comment "IP set for Proxmox nodes"
else
  echo "IP set 'proxmox-nodes' already exists, skipping creation."
fi
echo

# 7. Add each node IP to the proxmox-nodes set (if not already there)
echo "=== Adding Node IPs to IP set 'proxmox-nodes' ==="
for IP in "${NODE_IPS[@]}"; do
  if ipset_contains_cidr "${IP}/32"; then
    echo " - $IP/32 is already in the IP set, skipping."
  else
    pvesh create /cluster/firewall/ipset/proxmox-nodes --cidr "$IP/32"
    echo " - Added $IP/32 to IP set 'proxmox-nodes'."
  fi
done
echo

# 8. Allow all traffic within the proxmox-nodes IP set
create_rule_once \
  "Allow all traffic within Proxmox nodes IP set" \
  --action ACCEPT \
  --type ipset \
  --source proxmox-nodes \
  --dest proxmox-nodes \
  --enable 1

echo

# 9. Create rules to allow SSH and Proxmox Web GUI from the management subnet
create_rule_once \
  "Allow SSH from $MANAGEMENT_SUBNET" \
  --action ACCEPT \
  --source "$MANAGEMENT_SUBNET" \
  --dest '+' \
  --dport 22 \
  --proto tcp \
  --enable 1

create_rule_once \
  "Allow Web GUI from $MANAGEMENT_SUBNET" \
  --action ACCEPT \
  --source "$MANAGEMENT_SUBNET" \
  --dest '+' \
  --dport 8006 \
  --proto tcp \
  --enable 1

# 10. (Optional) Attempt to allow VXLAN traffic (UDP $VXLAN_PORT) within the node subnet
echo
if [ -n "${NODE_IPS[0]}" ]; then
  FIRST_NODE_IP="${NODE_IPS[0]}"
  # Attempt to find a local route containing that IP (on this node).
  # This is a best-effort approach for demonstration. You may need to hardcode your subnet if needed.
  NODE_SUBNET=$(ip route | grep "$FIRST_NODE_IP" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}\b' | head -n1)
  if [ -n "$NODE_SUBNET" ]; then
    create_rule_once \
      "Allow VXLAN for $NODE_SUBNET" \
      --action ACCEPT \
      --source "$NODE_SUBNET" \
      --dest "$NODE_SUBNET" \
      --proto udp \
      --dport "$VXLAN_PORT" \
      --enable 1
    echo " - Allowed VXLAN (UDP $VXLAN_PORT) traffic for subnet: $NODE_SUBNET"
  else
    echo "WARNING: Could not determine node subnet from first node IP $FIRST_NODE_IP; skipping VXLAN rule."
  fi
fi
echo

# 11. Allow Ceph communication among nodes (ports 3300, 6789, 6800–7300)
echo "=== Creating Ceph rules among node IPs ==="
for IP in "${NODE_IPS[@]}"; do
  create_rule_once \
    "Allow Ceph MON 6789 from $IP" \
    --action ACCEPT \
    --source "$IP/32" \
    --dest proxmox-nodes \
    --proto tcp \
    --dport 6789 \
    --enable 1

  create_rule_once \
    "Allow Ceph MON 3300 from $IP" \
    --action ACCEPT \
    --source "$IP/32" \
    --dest proxmox-nodes \
    --proto tcp \
    --dport 3300 \
    --enable 1

  create_rule_once \
    "Allow Ceph OSD 6800-7300 from $IP" \
    --action ACCEPT \
    --source "$IP/32" \
    --dest proxmox-nodes \
    --proto tcp \
    --dport 6800:7300 \
    --enable 1
done
echo

# 12. (Optional) Set default inbound/outbound policies for the Datacenter firewall
# By default we keep them as is. If you prefer a stricter default, uncomment below:
# echo "Setting default policy to DROP incoming traffic..."
# pvesh set /cluster/firewall/options --policy_in DROP --policy_out ACCEPT

# 13. Enable firewall for the Datacenter
pvesh set /cluster/firewall/options --enable 1
echo "Firewall enabled for datacenter."

# 14. Enable firewall for all nodes
for NODE in $NODES; do
  pvesh set "/nodes/$NODE/firewall/options" --enable 1
  echo " - Firewall enabled for node: $NODE."
done

echo
echo "=== Firewall setup and enablement completed for all nodes and datacenter! ==="
