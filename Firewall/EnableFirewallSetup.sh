#!/bin/bash
#
# EnableFirewallSetup.sh
#
# Enables the firewall on the Proxmox VE datacenter and all nodes. It then configures:
#   1. An IP set ("proxmox-nodes") containing each node’s cluster interface IP.
#   2. Rules to allow:
#       - Internal node-to-node traffic
#       - Ceph traffic (including msgr2 on port 3300)
#       - SSH (22) and Proxmox Web GUI (8006) from a specified management subnet
#       - VXLAN traffic (UDP 4789 by default) within the node subnet
#   3. (Optional) Sets default inbound policy to DROP for the datacenter firewall (commented by default).
#
# Usage:
#   ./EnableFirewallSetup.sh <management_subnet/netmask>
#
# Example Usage:
#   # Allow SSH/Web GUI from 192.168.1.0/24
#   ./EnableFirewallSetup.sh 192.168.1.0/24
#
# Function Index:
#   - ipset_contains_cidr
#   - rule_exists_by_comment
#   - create_rule_once
#

source "$UTILITIES"

###############################################################################
# CONFIGURATION
###############################################################################
CLUSTER_INTERFACE="vmbr0"  # Interface for cluster/storage network
VXLAN_PORT="4789"          # Default VXLAN UDP port

###############################################################################
# HELPER FUNCTIONS
###############################################################################

ipset_contains_cidr() {
  # Check if a given CIDR is already in the proxmox-nodes IP set
  local cidr="$1"
  local existingCidrs=$(
    pvesh get /cluster/firewall/ipset/proxmox-nodes --output-format json 2>/dev/null \
      | jq -r '.[].cidr'
  )
  if echo "${existingCidrs}" | grep -qx "${cidr}"; then
    return 0
  else
    return 1
  fi
}

rule_exists_by_comment() {
  # Check if a firewall rule with a particular comment already exists
  local comment="$1"
  local existingComments=$(
    pvesh get /cluster/firewall/rules --output-format json 2>/dev/null \
      | jq -r '.[].comment // empty'
  )
  if echo "${existingComments}" | grep -Fxq "${comment}"; then
    return 0
  else
    return 1
  fi
}

create_rule_once() {
  # Create a firewall rule only if it doesn't already exist (based on comment)
  local comment="$1"
  shift
  if rule_exists_by_comment "${comment}"; then
    echo " - Rule with comment '${comment}' already exists, skipping."
  else
    pvesh create /cluster/firewall/rules "$@" --comment "${comment}"
    echo " - Created new rule: ${comment}"
  fi
}

###############################################################################
# MAIN SCRIPT
###############################################################################

# 1. Ensure we have the necessary privileges and environment
check_root
check_proxmox

# 2. Make sure we have the needed commands (jq is not installed by default on Proxmox)
install_or_prompt "jq"

# 3. Verify we are in a cluster
check_cluster_membership

# 4. Parse management subnet
if [ -z "$1" ]; then
  echo "Usage: $0 <management_subnet/netmask>"
  echo "Example: $0 192.168.1.0/24"
  exit 1
fi
MANAGEMENT_SUBNET="$1"

echo "Management Subnet: \"${MANAGEMENT_SUBNET}\""
echo "Cluster Interface: \"${CLUSTER_INTERFACE}\""
echo

# 5. Gather node IPs (local + remote)
LOCAL_NODE_IP="$(hostname -I | awk '{print $1}')"
readarray -t REMOTE_NODE_IPS < <( get_remote_node_ips )
NODE_IPS=("${LOCAL_NODE_IP}" "${REMOTE_NODE_IPS[@]}")

###############################################################################
# Create and populate 'proxmox-nodes' IP set
###############################################################################
if ! pvesh get /cluster/firewall/ipset --output-format json 2>/dev/null \
   | jq -r '.[].name' | grep -qx 'proxmox-nodes'; then
  echo "Creating IP set 'proxmox-nodes'..."
  pvesh create /cluster/firewall/ipset --name proxmox-nodes \
    --comment "IP set for Proxmox nodes"
else
  echo "IP set 'proxmox-nodes' already exists, skipping creation."
fi
echo

echo "=== Adding Node IPs to IP set 'proxmox-nodes' ==="
for ipAddr in "${NODE_IPS[@]}"; do
  if ipset_contains_cidr "${ipAddr}/32"; then
    echo " - \"${ipAddr}/32\" is already in the IP set, skipping."
  else
    pvesh create /cluster/firewall/ipset/proxmox-nodes --cidr "${ipAddr}/32"
    echo " - Added \"${ipAddr}/32\" to IP set 'proxmox-nodes'."
  fi
done
echo

###############################################################################
# Create firewall rules
###############################################################################
create_rule_once \
  "Allow all traffic within Proxmox nodes IP set" \
  --action ACCEPT \
  --type ipset \
  --source proxmox-nodes \
  --dest proxmox-nodes \
  --enable 1
echo

create_rule_once \
  "Allow SSH from ${MANAGEMENT_SUBNET}" \
  --action ACCEPT \
  --source "${MANAGEMENT_SUBNET}" \
  --dest '+' \
  --dport 22 \
  --proto tcp \
  --enable 1

create_rule_once \
  "Allow Web GUI from ${MANAGEMENT_SUBNET}" \
  --action ACCEPT \
  --source "${MANAGEMENT_SUBNET}" \
  --dest '+' \
  --dport 8006 \
  --proto tcp \
  --enable 1
echo

# Attempt to allow VXLAN traffic
if [ -n "${NODE_IPS[0]}" ]; then
  FIRST_NODE_IP="${NODE_IPS[0]}"
  NODE_SUBNET=$(ip route | grep "${FIRST_NODE_IP}" \
    | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}\b' | head -n1)
  if [ -n "${NODE_SUBNET}" ]; then
    create_rule_once \
      "Allow VXLAN for ${NODE_SUBNET}" \
      --action ACCEPT \
      --source "${NODE_SUBNET}" \
      --dest "${NODE_SUBNET}" \
      --proto udp \
      --dport "${VXLAN_PORT}" \
      --enable 1
    echo " - Allowed VXLAN (UDP ${VXLAN_PORT}) traffic for subnet: \"${NODE_SUBNET}\""
  else
    echo "WARNING: Could not determine node subnet from \"${FIRST_NODE_IP}\"; skipping VXLAN rule."
  fi
fi
echo

# Allow Ceph traffic among nodes
echo "=== Creating Ceph rules among node IPs ==="
for ipAddr in "${NODE_IPS[@]}"; do
  create_rule_once \
    "Allow Ceph MON 6789 from ${ipAddr}" \
    --action ACCEPT \
    --source "${ipAddr}/32" \
    --dest proxmox-nodes \
    --proto tcp \
    --dport 6789 \
    --enable 1

  create_rule_once \
    "Allow Ceph MON 3300 from ${ipAddr}" \
    --action ACCEPT \
    --source "${ipAddr}/32" \
    --dest proxmox-nodes \
    --proto tcp \
    --dport 3300 \
    --enable 1

  create_rule_once \
    "Allow Ceph OSD 6800-7300 from ${ipAddr}" \
    --action ACCEPT \
    --source "${ipAddr}/32" \
    --dest proxmox-nodes \
    --proto tcp \
    --dport 6800:7300 \
    --enable 1
done
echo

###############################################################################
# Optional default policy settings
###############################################################################
# Uncomment to set the default inbound policy to DROP on the datacenter:
# pvesh set /cluster/firewall/options --policy_in DROP --policy_out ACCEPT
# echo "Default inbound policy set to DROP."

###############################################################################
# Enable firewall on datacenter and all nodes
###############################################################################
pvesh set /cluster/firewall/options --enable 1
echo "Firewall enabled for datacenter."

echo "Enabling firewall for each node:"
for ipAddr in "${NODE_IPS[@]}"; do
  nodeName=$(get_name_from_ip "${ipAddr}")
  pvesh set "/nodes/${nodeName}/firewall/options" --enable 1
  echo " - Firewall enabled for node: \"${nodeName}\"."
done

echo
echo "=== Firewall setup and enablement completed for all nodes and datacenter! ==="
