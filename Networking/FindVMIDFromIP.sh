#!/bin/bash
#
# FindVMIDFromIP.sh
#
# Finds VM/LXC ID(s) from an IP address in a Proxmox cluster. Supports detection
# of nested VMs by matching MAC addresses with the BC:XX:XX prefix pattern.
#
# Usage:
#   FindVMIDFromIP.sh <ip_address>
#   FindVMIDFromIP.sh <ip_address> --nested-only
#
# Arguments:
#   ip_address    : IP address to search for
#   --nested-only : Only check for nested VMs (optional)
#
# Examples:
#   FindVMIDFromIP.sh 192.168.1.100
#   FindVMIDFromIP.sh 10.0.0.50 --nested-only
#
# Notes:
#   - Searches guest agent data and network configurations
#   - Nested VM detection: Checks if MAC address matches BC:XX:XX where XX:XX
#     is the decimal representation of the VMID (e.g., VMID 100 = BC:01:00)
#   - This narrows down which host VMID the nested VM is running under
#
# Function Index:
#   - get_mac_from_ip
#   - extract_vmid_from_mac
#   - find_direct_vmid
#   - find_nested_vmid
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "ip_address:ip --nested-only:flag" "$@"

# --- get_mac_from_ip ---------------------------------------------------------
# Attempts to resolve MAC address from IP using ARP and guest agent data
get_mac_from_ip() {
    local ip="$1"
    local mac=""
    
    # Try ARP table first
    mac=$(ip neigh show "$ip" 2>/dev/null | grep -oP '(?<=lladdr )[0-9a-f:]+' | head -1 || true)
    
    if [[ -n "$mac" ]]; then
        echo "$mac"
        return 0
    fi
    
    # Try guest agent data from all VMs/CTs
    local nodes
    nodes=$(pvesh get /nodes --output-format=json | jq -r '.[] | .node')
    
    for node in $nodes; do
        # Check VMs
        local vm_ids
        vm_ids=$(pvesh get /nodes/"$node"/qemu --output-format=json 2>/dev/null | jq -r '.[] | .vmid' || true)
        
        for vmid in $vm_ids; do
            local guest_ips
            guest_ips=$(pvesh get /nodes/"$node"/qemu/"$vmid"/agent/network-get-interfaces --output-format=json 2>/dev/null | \
                jq -r '.result[] | select(."ip-addresses") | ."ip-addresses"[] | select(."ip-address") | ."ip-address"' 2>/dev/null || true)
            
            if echo "$guest_ips" | grep -q "^${ip}$"; then
                mac=$(pvesh get /nodes/"$node"/qemu/"$vmid"/agent/network-get-interfaces --output-format=json 2>/dev/null | \
                    jq -r --arg ip "$ip" '.result[] | select(."ip-addresses") | select(any(."ip-addresses"[]; ."ip-address" == $ip)) | ."hardware-address"' 2>/dev/null | head -1 || true)
                if [[ -n "$mac" ]]; then
                    echo "$mac"
                    return 0
                fi
            fi
        done
        
        # Check CTs
        local ct_ids
        ct_ids=$(pvesh get /nodes/"$node"/lxc --output-format=json 2>/dev/null | jq -r '.[] | .vmid' || true)
        
        for ctid in $ct_ids; do
            local ct_ips
            ct_ips=$(pvesh get /nodes/"$node"/lxc/"$ctid"/interfaces --output-format=json 2>/dev/null | \
                jq -r '.[] | select(.inet) | .inet' 2>/dev/null | cut -d'/' -f1 || true)
            
            if echo "$ct_ips" | grep -q "^${ip}$"; then
                mac=$(pvesh get /nodes/"$node"/lxc/"$ctid"/interfaces --output-format=json 2>/dev/null | \
                    jq -r --arg ip "$ip" '.[] | select(.inet) | select(.inet | startswith($ip + "/")) | .hwaddr' 2>/dev/null | head -1 || true)
                if [[ -n "$mac" ]]; then
                    echo "$mac"
                    return 0
                fi
            fi
        done
    done
    
    return 1
}

# --- extract_vmid_from_mac ---------------------------------------------------
# Extracts VMID from MAC address if it matches BC:XX:XX pattern
# Returns VMID or empty string if pattern doesn't match
# Note: The MAC uses decimal digits, not hex. BC:01:00 = VMID 100, BC:12:34 = VMID 1234
extract_vmid_from_mac() {
    local mac="$1"
    local mac_upper
    mac_upper=$(echo "$mac" | tr '[:lower:]' '[:upper:]')
    
    # Check if MAC starts with BC:
    if [[ ! "$mac_upper" =~ ^BC: ]]; then
        return 1
    fi
    
    # Extract the next two octets (BC:XX:XX)
    local dec_vmid
    dec_vmid=$(echo "$mac_upper" | cut -d: -f2-3 | tr -d ':')
    
    # The MAC uses decimal representation, so just remove leading zeros
    local vmid=$((10#$dec_vmid))
    
    if [[ $vmid -gt 0 ]]; then
        echo "$vmid"
        return 0
    fi
    
    return 1
}

# --- find_direct_vmid --------------------------------------------------------
# Searches for VM/CT with the given IP address directly
find_direct_vmid() {
    local ip="$1"
    local found=0
    
    __info__ "Searching for direct VM/CT with IP ${ip}..."
    
    local nodes
    nodes=$(pvesh get /nodes --output-format=json | jq -r '.[] | .node')
    
    for node in $nodes; do
        # Check VMs
        local vm_ids
        vm_ids=$(pvesh get /nodes/"$node"/qemu --output-format=json 2>/dev/null | jq -r '.[] | .vmid' || true)
        
        for vmid in $vm_ids; do
            # Check guest agent
            local guest_ips
            guest_ips=$(pvesh get /nodes/"$node"/qemu/"$vmid"/agent/network-get-interfaces --output-format=json 2>/dev/null | \
                jq -r '.result[] | select(."ip-addresses") | ."ip-addresses"[] | select(."ip-address") | ."ip-address"' 2>/dev/null || true)
            
            if echo "$guest_ips" | grep -q "^${ip}$"; then
                local vm_name
                vm_name=$(pvesh get /nodes/"$node"/qemu/"$vmid"/config --output-format=json 2>/dev/null | jq -r '.name // "N/A"')
                echo ""
                __ok__ "Found VM ${vmid} on node ${node}"
                echo "  Type: VM (qemu)"
                echo "  Name: ${vm_name}"
                echo "  IP:   ${ip}"
                found=1
            fi
            
            # Check config
            local config_ips
            config_ips=$(pvesh get /nodes/"$node"/qemu/"$vmid"/config 2>/dev/null | \
                grep -oP 'ip=\K[0-9.]+' || true)
            
            if echo "$config_ips" | grep -q "^${ip}$"; then
                local vm_name
                vm_name=$(pvesh get /nodes/"$node"/qemu/"$vmid"/config --output-format=json 2>/dev/null | jq -r '.name // "N/A"')
                echo ""
                __ok__ "Found VM ${vmid} on node ${node} (from config)"
                echo "  Type: VM (qemu)"
                echo "  Name: ${vm_name}"
                echo "  IP:   ${ip}"
                found=1
            fi
        done
        
        # Check CTs
        local ct_ids
        ct_ids=$(pvesh get /nodes/"$node"/lxc --output-format=json 2>/dev/null | jq -r '.[] | .vmid' || true)
        
        for ctid in $ct_ids; do
            # Check interfaces
            local ct_ips
            ct_ips=$(pvesh get /nodes/"$node"/lxc/"$ctid"/interfaces --output-format=json 2>/dev/null | \
                jq -r '.[] | select(.inet) | .inet' 2>/dev/null | cut -d'/' -f1 || true)
            
            if echo "$ct_ips" | grep -q "^${ip}$"; then
                local ct_name
                ct_name=$(pvesh get /nodes/"$node"/lxc/"$ctid"/config --output-format=json 2>/dev/null | jq -r '.hostname // "N/A"')
                echo ""
                __ok__ "Found CT ${ctid} on node ${node}"
                echo "  Type: LXC"
                echo "  Name: ${ct_name}"
                echo "  IP:   ${ip}"
                found=1
            fi
            
            # Check config
            config_ips=$(pvesh get /nodes/"$node"/lxc/"$ctid"/config 2>/dev/null | \
                grep -oP 'ip=\K[0-9.]+' || true)
            
            if echo "$config_ips" | grep -q "^${ip}$"; then
                local ct_name
                ct_name=$(pvesh get /nodes/"$node"/lxc/"$ctid"/config --output-format=json 2>/dev/null | jq -r '.hostname // "N/A"')
                echo ""
                __ok__ "Found CT ${ctid} on node ${node} (from config)"
                echo "  Type: LXC"
                echo "  Name: ${ct_name}"
                echo "  IP:   ${ip}"
                found=1
            fi
        done
    done
    
    return $((1 - found))
}

# --- find_nested_vmid --------------------------------------------------------
# Searches for nested VM by checking MAC address prefix pattern
find_nested_vmid() {
    local ip="$1"
    
    __info__ "Checking for nested VM with IP ${ip}..."
    
    # Get MAC address for the IP
    local mac
    mac=$(get_mac_from_ip "$ip" || true)
    
    if [[ -z "$mac" ]]; then
        __warn__ "Could not determine MAC address for IP ${ip}"
        __info__ "Tips:"
        echo "  - Ensure the IP is reachable via ARP"
        echo "  - Check if guest agent is installed and running"
        echo "  - Try: arp -a | grep ${ip}"
        return 1
    fi
    
    __info__ "Found MAC address: ${mac}"
    
    # Extract VMID from MAC if it matches pattern
    local parent_vmid
    parent_vmid=$(extract_vmid_from_mac "$mac" || true)
    
    if [[ -z "$parent_vmid" ]]; then
        __warn__ "MAC address ${mac} does not match BC:XX:XX pattern"
        echo "  This IP is likely not a nested VM using the standard MAC prefix scheme"
        return 1
    fi
    
    # Verify the parent VMID exists
    local parent_node
    parent_node=$(__get_vm_node__ "$parent_vmid" 2>/dev/null || __get_ct_node__ "$parent_vmid" 2>/dev/null || true)
    
    if [[ -z "$parent_node" ]]; then
        __warn__ "Extracted VMID ${parent_vmid} from MAC, but no such VM/CT exists"
        return 1
    fi
    
    # Get parent details
    local parent_name
    local parent_type
    if __get_vm_node__ "$parent_vmid" >/dev/null 2>&1; then
        parent_type="VM (qemu)"
        parent_name=$(pvesh get /nodes/"$parent_node"/qemu/"$parent_vmid"/config --output-format=json 2>/dev/null | jq -r '.name // "N/A"')
    else
        parent_type="LXC"
        parent_name=$(pvesh get /nodes/"$parent_node"/lxc/"$parent_vmid"/config --output-format=json 2>/dev/null | jq -r '.hostname // "N/A"')
    fi
    
    echo ""
    __ok__ "Found nested VM indicator!"
    echo "  IP:          ${ip}"
    echo "  MAC:         ${mac}"
    echo "  Parent VMID: ${parent_vmid}"
    echo "  Parent Type: ${parent_type}"
    echo "  Parent Name: ${parent_name}"
    echo "  Parent Node: ${parent_node}"
    echo ""
    echo "  This suggests IP ${ip} belongs to a nested VM running inside VMID ${parent_vmid}"
    echo "  Connect to VMID ${parent_vmid} to investigate the nested environment"
    
    return 0
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __install_or_prompt__ "jq"
    __check_cluster_membership__
    
    local found=0
    
    # Search for direct VM/CT match (unless --nested-only specified)
    if [[ "$NESTED_ONLY" != "true" ]]; then
        if find_direct_vmid "$IP_ADDRESS"; then
            found=1
        fi
    fi
    
    # Search for nested VM
    if find_nested_vmid "$IP_ADDRESS"; then
        found=1
    fi
    
    if [[ $found -eq 0 ]]; then
        echo ""
        __err__ "No VM/CT found with IP ${IP_ADDRESS}"
        __info__ "Troubleshooting tips:"
        echo "  - Verify the IP is correct and reachable"
        echo "  - Check if guest agent is installed and running"
        echo "  - For nested VMs, ensure MAC uses BC:XX:XX prefix pattern"
        echo "  - Try manual search: pvesh get /cluster/resources --type vm"
        exit 1
    fi
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-12-01
#
# Changes:
# - 2025-12-01: Initial version created
#   - Direct VM/CT search via guest agent and config
#   - Nested VM detection via BC:XX:XX MAC prefix pattern
#   - Cluster-wide search capability
#
# Fixes:
# -
#
# Known issues:
# -
#
