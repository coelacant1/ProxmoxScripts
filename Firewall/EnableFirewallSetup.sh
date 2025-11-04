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
#   EnableFirewallSetup.sh <management_subnet/netmask>
#
# Example Usage:
#   # Allow SSH/Web GUI from 192.168.1.0/24
#   EnableFirewallSetup.sh 192.168.1.0/24
#
# Function Index:
#   - ipset_contains_cidr
#   - rule_exists_by_comment
#   - create_rule_once
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

###############################################################################
# CONFIGURATION
###############################################################################
CLUSTER_INTERFACE="vmbr0"  # Interface for cluster/storage network
VXLAN_PORT="4789"          # Default VXLAN UDP port

# --- ipset_contains_cidr -----------------------------------------------------
ipset_contains_cidr() {
    local cidr="$1"
    local existing_cidrs
    existing_cidrs=$(
        pvesh get /cluster/firewall/ipset/proxmox-nodes --output-format json 2>/dev/null \
        | jq -r '.[].cidr'
    )
    echo "${existing_cidrs}" | grep -qx "${cidr}"
}

# --- rule_exists_by_comment --------------------------------------------------
rule_exists_by_comment() {
    local comment="$1"
    local existing_comments
    existing_comments=$(
        pvesh get /cluster/firewall/rules --output-format json 2>/dev/null \
        | jq -r '.[].comment // empty'
    )
    echo "${existing_comments}" | grep -Fxq "${comment}"
}

# --- create_rule_once --------------------------------------------------------
create_rule_once() {
    local comment="$1"
    shift
    if rule_exists_by_comment "${comment}"; then
        __update__ "Rule '${comment}' already exists, skipping"
    else
        pvesh create /cluster/firewall/rules "$@" --comment "${comment}"
        __ok__ "Created rule: ${comment}"
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "jq"
    __check_cluster_membership__

    if [[ $# -lt 1 ]]; then
        __err__ "Missing required argument: management_subnet"
        echo "Usage: $0 <management_subnet>"
        exit 64
    fi

    local management_subnet="$1"

    __info__ "Management Subnet: ${management_subnet}"
    __info__ "Cluster Interface: ${CLUSTER_INTERFACE}"

    # Gather node IPs
    local local_node_ip
    local_node_ip=$(hostname -I | awk '{print $1}')
    local -a remote_node_ips
    mapfile -t remote_node_ips < <(__get_remote_node_ips__)
    local -a node_ips=("${local_node_ip}" "${remote_node_ips[@]}")

    # Create and populate proxmox-nodes IP set
    __info__ "Creating IP set 'proxmox-nodes'"
    if ! pvesh get /cluster/firewall/ipset --output-format json 2>/dev/null \
       | jq -r '.[].name' | grep -qx 'proxmox-nodes'; then
        pvesh create /cluster/firewall/ipset --name proxmox-nodes \
            --comment "IP set for Proxmox nodes"
        __ok__ "Created IP set 'proxmox-nodes'"
    else
        __update__ "IP set 'proxmox-nodes' already exists"
    fi

    __info__ "Adding node IPs to IP set"
    for ip_addr in "${node_ips[@]}"; do
        if ipset_contains_cidr "${ip_addr}/32"; then
            __update__ "${ip_addr}/32 already in IP set"
        else
            pvesh create /cluster/firewall/ipset/proxmox-nodes --cidr "${ip_addr}/32"
            __ok__ "Added ${ip_addr}/32 to IP set"
        fi
    done

    # Create firewall rules
    __info__ "Creating firewall rules"

    create_rule_once \
        "Allow all traffic within Proxmox nodes IP set" \
        --action ACCEPT \
        --type ipset \
        --source proxmox-nodes \
        --dest proxmox-nodes \
        --enable 1

    create_rule_once \
        "Allow SSH from ${management_subnet}" \
        --action ACCEPT \
        --source "${management_subnet}" \
        --dest '+' \
        --dport 22 \
        --proto tcp \
        --enable 1

    create_rule_once \
        "Allow Web GUI from ${management_subnet}" \
        --action ACCEPT \
        --source "${management_subnet}" \
        --dest '+' \
        --dport 8006 \
        --proto tcp \
        --enable 1

    # VXLAN rule
    if [[ -n "${node_ips[0]}" ]]; then
        local first_node_ip="${node_ips[0]}"
        local node_subnet
        node_subnet=$(ip route | grep "${first_node_ip}" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}\b' | head -n1)
        if [[ -n "${node_subnet}" ]]; then
            create_rule_once \
                "Allow VXLAN for ${node_subnet}" \
                --action ACCEPT \
                --source "${node_subnet}" \
                --dest "${node_subnet}" \
                --proto udp \
                --dport "${VXLAN_PORT}" \
                --enable 1
        fi
    fi

    # Ceph rules
    __info__ "Creating Ceph rules"
    for ip_addr in "${node_ips[@]}"; do
        create_rule_once \
            "Allow Ceph MON 6789 from ${ip_addr}" \
            --action ACCEPT \
            --source "${ip_addr}/32" \
            --dest proxmox-nodes \
            --proto tcp \
            --dport 6789 \
            --enable 1

        create_rule_once \
            "Allow Ceph MON 3300 from ${ip_addr}" \
            --action ACCEPT \
            --source "${ip_addr}/32" \
            --dest proxmox-nodes \
            --proto tcp \
            --dport 3300 \
            --enable 1

        create_rule_once \
            "Allow Ceph OSD 6800-7300 from ${ip_addr}" \
            --action ACCEPT \
            --source "${ip_addr}/32" \
            --dest proxmox-nodes \
            --proto tcp \
            --dport 6800:7300 \
            --enable 1
    done

    # Enable firewall on datacenter
    __info__ "Enabling datacenter firewall"
    pvesh set /cluster/firewall/options --enable 1
    __ok__ "Datacenter firewall enabled"

    # Enable firewall on all nodes
    __info__ "Enabling node firewalls"
    for ip_addr in "${node_ips[@]}"; do
        local node_name
        node_name=$(__get_name_from_ip__ "${ip_addr}")
        pvesh set "/nodes/${node_name}/firewall/options" --enable 1
        __ok__ "Firewall enabled on ${node_name}"
    done

    __ok__ "Firewall setup completed successfully!"
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
