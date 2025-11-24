#!/bin/bash
#
# Network.sh
#
# Network management framework for VM/CT network configuration, IP management,
# and network validation.
#
# Usage:
#   source "${UTILITYPATH}/Network.sh"
#
# Features:
#   - Configure network interfaces
#   - Manage IP addresses (DHCP/Static)
#   - VLAN and bridge management
#   - Network validation and testing
#   - Bulk network operations
#   - Network migration support
#
# Function Index:
#   - __net_log__
#   - __net_vm_add_interface__
#   - __net_vm_remove_interface__
#   - __net_vm_set_bridge__
#   - __net_vm_set_vlan__
#   - __net_vm_set_mac__
#   - __net_vm_get_interfaces__
#   - __net_ct_add_interface__
#   - __net_ct_remove_interface__
#   - __net_ct_set_ip__
#   - __net_ct_set_gateway__
#   - __net_ct_set_nameserver__
#   - __net_ct_get_interfaces__
#   - __net_validate_ip__
#   - __net_validate_cidr__
#   - __net_validate_mac__
#   - __net_is_ip_in_use__
#   - __net_get_next_ip__
#   - __net_test_connectivity__
#   - __net_test_dns__
#   - __net_test_gateway__
#   - __net_ping__
#   - __net_bulk_set_bridge__
#   - __net_bulk_set_vlan__
#   - __net_migrate_network__
#

# Source Logger for structured logging
if [[ -n "${UTILITYPATH:-}" && -f "${UTILITYPATH}/Logger.sh" ]]; then
    # shellcheck source=Utilities/Logger.sh
    source "${UTILITYPATH}/Logger.sh"
fi

# Safe logging wrapper
__net_log__() {
    local level="$1"
    local message="$2"
    if declare -f __log__ >/dev/null 2>&1; then
        __log__ "$level" "$message" "NET"
    fi
}

# Source dependencies
source "${UTILITYPATH}/Operations.sh"
source "${UTILITYPATH}/Communication.sh"

###############################################################################
# VM Network Configuration
###############################################################################

# --- __net_vm_add_interface__ ------------------------------------------------
# @function __net_vm_add_interface__
# @description Add network interface to VM.
# @usage __net_vm_add_interface__ <vmid> <net_id> [options]
# @param 1 VMID
# @param 2 Network ID (net0, net1, etc.)
# @param --bridge Bridge name (e.g., vmbr0)
# @param --vlan VLAN tag
# @param --mac MAC address
# @param --model Network model (virtio, e1000, etc.)
# @return 0 on success, 1 on error
__net_vm_add_interface__() {
    local vmid="$1"
    local net_id="$2"
    shift 2

    __net_log__ "DEBUG" "Adding interface $net_id to VM $vmid"

    if ! __vm_exists__ "$vmid"; then
        __net_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Parse options
    local bridge="vmbr0"
    local vlan=""
    local mac=""
    local model="virtio"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bridge)
                bridge="$2"
                shift 2
                ;;
            --vlan)
                vlan="$2"
                shift 2
                ;;
            --mac)
                mac="$2"
                shift 2
                ;;
            --model)
                model="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Build network configuration string
    local net_config="${model},bridge=${bridge}"

    if [[ -n "$vlan" ]]; then
        net_config="${net_config},tag=${vlan}"
    fi

    if [[ -n "$mac" ]]; then
        if ! __net_validate_mac__ "$mac"; then
            __net_log__ "ERROR" "Invalid MAC address: $mac"
            echo "Error: Invalid MAC address: $mac" >&2
            return 1
        fi
        net_config="${net_config},macaddr=${mac}"
    fi

    __net_log__ "INFO" "Applying network config: $net_config"

    # Apply configuration
    if __vm_set_config__ "$vmid" "--${net_id}" "$net_config"; then
        __net_log__ "INFO" "Added interface $net_id to VM $vmid successfully"
        echo "Added interface $net_id to VM $vmid: $net_config"
        return 0
    else
        __net_log__ "ERROR" "Failed to add interface $net_id to VM $vmid"
        echo "Error: Failed to add interface" >&2
        return 1
    fi
}

# --- __net_vm_remove_interface__ ---------------------------------------------
# @function __net_vm_remove_interface__
# @description Remove network interface from VM.
# @usage __net_vm_remove_interface__ <vmid> <net_id>
# @param 1 VMID
# @param 2 Network ID (net0, net1, etc.)
# @return 0 on success, 1 on error
__net_vm_remove_interface__() {
    local vmid="$1"
    local net_id="$2"

    __net_log__ "DEBUG" "Removing interface $net_id from VM $vmid"

    if ! __vm_exists__ "$vmid"; then
        __net_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    if __vm_set_config__ "$vmid" "--delete" "$net_id"; then
        __net_log__ "INFO" "Removed interface $net_id from VM $vmid"
        echo "Removed interface $net_id from VM $vmid"
        return 0
    else
        __net_log__ "ERROR" "Failed to remove interface $net_id from VM $vmid"
        echo "Error: Failed to remove interface" >&2
        return 1
    fi
}

# --- __net_vm_set_bridge__ ---------------------------------------------------
# @function __net_vm_set_bridge__
# @description Change bridge for VM network interface.
# @usage __net_vm_set_bridge__ <vmid> <net_id> <bridge>
# @param 1 VMID
# @param 2 Network ID (net0, net1, etc.)
# @param 3 Bridge name (e.g., vmbr0)
# @return 0 on success, 1 on error
__net_vm_set_bridge__() {
    local vmid="$1"
    local net_id="$2"
    local new_bridge="$3"

    __net_log__ "DEBUG" "Setting bridge for VM $vmid $net_id to $new_bridge"

    if ! __vm_exists__ "$vmid"; then
        __net_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Get current network config
    local current_config
    current_config=$(qm config "$vmid" | grep "^${net_id}:" | cut -d':' -f2- | sed 's/^ //')

    if [[ -z "$current_config" ]]; then
        __net_log__ "ERROR" "Interface $net_id not found on VM $vmid"
        echo "Error: Interface $net_id not found" >&2
        return 1
    fi

    # Replace bridge in config
    local new_config="${current_config/bridge=[^,]*/bridge=${new_bridge}}"
    __net_log__ "DEBUG" "New config: $new_config"

    if __vm_set_config__ "$vmid" "--${net_id}" "$new_config"; then
        __net_log__ "INFO" "Changed bridge for VM $vmid $net_id to $new_bridge"
        echo "Changed bridge for $net_id to $new_bridge"
        return 0
    else
        __net_log__ "ERROR" "Failed to change bridge for VM $vmid $net_id"
        echo "Error: Failed to change bridge" >&2
        return 1
    fi
}

# --- __net_vm_set_vlan__ -----------------------------------------------------
# @function __net_vm_set_vlan__
# @description Set or change VLAN tag for VM network interface.
# @usage __net_vm_set_vlan__ <vmid> <net_id> <vlan>
# @param 1 VMID
# @param 2 Network ID (net0, net1, etc.)
# @param 3 VLAN tag (or "none" to remove)
# @return 0 on success, 1 on error
__net_vm_set_vlan__() {
    local vmid="$1"
    local net_id="$2"
    local vlan="$3"

    __net_log__ "DEBUG" "Setting VLAN for VM $vmid $net_id to $vlan"

    if ! __vm_exists__ "$vmid"; then
        __net_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    # Get current network config
    local current_config
    current_config=$(qm config "$vmid" | grep "^${net_id}:" | cut -d':' -f2- | sed 's/^ //')

    if [[ -z "$current_config" ]]; then
        __net_log__ "ERROR" "Interface $net_id not found on VM $vmid"
        echo "Error: Interface $net_id not found" >&2
        return 1
    fi

    local new_config

    if [[ "$vlan" == "none" ]]; then
        # Remove VLAN tag
        __net_log__ "DEBUG" "Removing VLAN tag from $net_id"
        new_config="${current_config//,tag=[^,]*/}"
    else
        # Add or replace VLAN tag
        if echo "$current_config" | grep -q "tag="; then
            __net_log__ "DEBUG" "Replacing existing VLAN tag with $vlan"
            new_config="${current_config/tag=[^,]*/tag=${vlan}}"
        else
            __net_log__ "DEBUG" "Adding VLAN tag $vlan"
            new_config="${current_config},tag=${vlan}"
        fi
    fi

    if __vm_set_config__ "$vmid" "--${net_id}" "$new_config"; then
        __net_log__ "INFO" "Set VLAN tag for VM $vmid $net_id to $vlan"
        echo "Set VLAN tag for $net_id to $vlan"
        return 0
    else
        __net_log__ "ERROR" "Failed to set VLAN tag for VM $vmid $net_id"
        echo "Error: Failed to set VLAN tag" >&2
        return 1
    fi
}

# --- __net_vm_set_mac__ ------------------------------------------------------
# @function __net_vm_set_mac__
# @description Set MAC address for VM network interface.
# @usage __net_vm_set_mac__ <vmid> <net_id> <mac>
# @param 1 VMID
# @param 2 Network ID (net0, net1, etc.)
# @param 3 MAC address
# @return 0 on success, 1 on error
__net_vm_set_mac__() {
    local vmid="$1"
    local net_id="$2"
    local mac="$3"

    __net_log__ "DEBUG" "Setting MAC for VM $vmid $net_id to $mac"

    if ! __vm_exists__ "$vmid"; then
        __net_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    if ! __net_validate_mac__ "$mac"; then
        __net_log__ "ERROR" "Invalid MAC address: $mac"
        echo "Error: Invalid MAC address: $mac" >&2
        return 1
    fi

    # Get current network config
    local current_config
    current_config=$(qm config "$vmid" | grep "^${net_id}:" | cut -d':' -f2- | sed 's/^ //')

    if [[ -z "$current_config" ]]; then
        __net_log__ "ERROR" "Interface $net_id not found on VM $vmid"
        echo "Error: Interface $net_id not found" >&2
        return 1
    fi

    local new_config

    # Add or replace MAC address
    if echo "$current_config" | grep -q "macaddr="; then
        __net_log__ "DEBUG" "Replacing existing MAC address"
        new_config="${current_config/macaddr=[^,]*/macaddr=${mac}}"
    else
        __net_log__ "DEBUG" "Adding MAC address"
        new_config="${current_config},macaddr=${mac}"
    fi

    if __vm_set_config__ "$vmid" "--${net_id}" "$new_config"; then
        __net_log__ "INFO" "Set MAC address for VM $vmid $net_id to $mac"
        echo "Set MAC address for $net_id to $mac"
        return 0
    else
        __net_log__ "ERROR" "Failed to set MAC address for VM $vmid $net_id"
        echo "Error: Failed to set MAC address" >&2
        return 1
    fi
}

# --- __net_vm_get_interfaces__ -----------------------------------------------
# @function __net_vm_get_interfaces__
# @description Get list of network interfaces for VM.
# @usage __net_vm_get_interfaces__ <vmid>
# @param 1 VMID
# @return 0 on success, prints interface list
__net_vm_get_interfaces__() {
    local vmid="$1"

    __net_log__ "DEBUG" "Getting network interfaces for VM $vmid"

    if ! __vm_exists__ "$vmid"; then
        __net_log__ "ERROR" "VM $vmid does not exist"
        echo "Error: VM $vmid does not exist" >&2
        return 1
    fi

    local count=0
    while IFS=':' read -r netid config; do
        echo "$netid: $config"
        count=$((count + 1))
    done < <(qm config "$vmid" | grep "^net[0-9]")

    __net_log__ "DEBUG" "Found $count network interface(s) for VM $vmid"
    return 0
}

###############################################################################
# CT Network Configuration
###############################################################################

# --- __net_ct_add_interface__ ------------------------------------------------
# @function __net_ct_add_interface__
# @description Add network interface to CT.
# @usage __net_ct_add_interface__ <ctid> <net_id> [options]
# @param 1 CTID
# @param 2 Network ID (net0, net1, etc.)
# @param --bridge Bridge name
# @param --ip IP address (CIDR notation or dhcp)
# @param --gateway Gateway address
# @param --vlan VLAN tag
# @return 0 on success, 1 on error
__net_ct_add_interface__() {
    local ctid="$1"
    local net_id="$2"
    shift 2

    __net_log__ "DEBUG" "Adding interface $net_id to CT $ctid"

    if ! __ct_exists__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    # Parse options
    local bridge="vmbr0"
    local ip="dhcp"
    local gateway=""
    local vlan=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bridge)
                bridge="$2"
                shift 2
                ;;
            --ip)
                ip="$2"
                shift 2
                ;;
            --gateway)
                gateway="$2"
                shift 2
                ;;
            --vlan)
                vlan="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    __net_log__ "DEBUG" "Interface config: bridge=$bridge, ip=$ip, gateway=$gateway, vlan=$vlan"

    # Validate IP if not DHCP
    if [[ "$ip" != "dhcp" ]] && ! __net_validate_cidr__ "$ip"; then
        __net_log__ "ERROR" "Invalid IP address: $ip"
        echo "Error: Invalid IP address: $ip" >&2
        return 1
    fi

    # Build network configuration
    local net_config="name=eth${net_id#net},bridge=${bridge}"

    if [[ -n "$vlan" ]]; then
        net_config="${net_config},tag=${vlan}"
    fi

    if [[ -n "$gateway" ]]; then
        net_config="${net_config},gw=${gateway}"
    fi

    net_config="${net_config},ip=${ip}"

    # Apply configuration
    if pct set "$ctid" "-${net_id}" "$net_config" 2>/dev/null; then
        __net_log__ "INFO" "Added interface $net_id to CT $ctid"
        echo "Added interface $net_id to CT $ctid: $net_config"
        return 0
    else
        __net_log__ "ERROR" "Failed to add interface $net_id to CT $ctid"
        echo "Error: Failed to add interface" >&2
        return 1
    fi
}

# --- __net_ct_remove_interface__ ---------------------------------------------
# @function __net_ct_remove_interface__
# @description Remove network interface from CT.
# @usage __net_ct_remove_interface__ <ctid> <net_id>
# @param 1 CTID
# @param 2 Network ID (net0, net1, etc.)
# @return 0 on success, 1 on error
__net_ct_remove_interface__() {
    local ctid="$1"
    local net_id="$2"

    __net_log__ "DEBUG" "Removing interface $net_id from CT $ctid"

    if ! __ct_exists__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if pct set "$ctid" "--delete" "$net_id" 2>/dev/null; then
        __net_log__ "INFO" "Removed interface $net_id from CT $ctid"
        echo "Removed interface $net_id from CT $ctid"
        return 0
    else
        __net_log__ "ERROR" "Failed to remove interface $net_id from CT $ctid"
        echo "Error: Failed to remove interface" >&2
        return 1
    fi
}

# --- __net_ct_set_ip__ -------------------------------------------------------
# @function __net_ct_set_ip__
# @description Set IP address for CT interface.
# @usage __net_ct_set_ip__ <ctid> <net_id> <ip>
# @param 1 CTID
# @param 2 Network ID (net0, net1, etc.)
# @param 3 IP address in CIDR notation or "dhcp"
# @return 0 on success, 1 on error
__net_ct_set_ip__() {
    local ctid="$1"
    local net_id="$2"
    local ip="$3"

    __net_log__ "DEBUG" "Setting IP for CT $ctid $net_id to $ip"

    if ! __ct_exists__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    # Validate IP if not DHCP
    if [[ "$ip" != "dhcp" ]] && ! __net_validate_cidr__ "$ip"; then
        __net_log__ "ERROR" "Invalid IP address: $ip"
        echo "Error: Invalid IP address: $ip" >&2
        return 1
    fi

    # Get current network config
    local current_config
    current_config=$(pct config "$ctid" | grep "^${net_id}:" | cut -d':' -f2- | sed 's/^ //')

    if [[ -z "$current_config" ]]; then
        __net_log__ "ERROR" "Interface $net_id not found on CT $ctid"
        echo "Error: Interface $net_id not found" >&2
        return 1
    fi

    # Replace IP in config
    local new_config="${current_config/ip=[^,]*/ip=${ip}}"

    if pct set "$ctid" "-${net_id}" "$new_config" 2>/dev/null; then
        __net_log__ "INFO" "Set IP for CT $ctid $net_id to $ip"
        echo "Set IP for $net_id to $ip"
        return 0
    else
        __net_log__ "ERROR" "Failed to set IP for CT $ctid $net_id"
        echo "Error: Failed to set IP address" >&2
        return 1
    fi
}

# --- __net_ct_set_gateway__ --------------------------------------------------
# @function __net_ct_set_gateway__
# @description Set gateway for CT interface.
# @usage __net_ct_set_gateway__ <ctid> <net_id> <gateway>
# @param 1 CTID
# @param 2 Network ID (net0, net1, etc.)
# @param 3 Gateway IP address
# @return 0 on success, 1 on error
__net_ct_set_gateway__() {
    local ctid="$1"
    local net_id="$2"
    local gateway="$3"

    __net_log__ "DEBUG" "Setting gateway for CT $ctid $net_id to $gateway"

    if ! __ct_exists__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __net_validate_ip__ "$gateway"; then
        __net_log__ "ERROR" "Invalid gateway address: $gateway"
        echo "Error: Invalid gateway address: $gateway" >&2
        return 1
    fi

    # Get current network config
    local current_config
    current_config=$(pct config "$ctid" | grep "^${net_id}:" | cut -d':' -f2- | sed 's/^ //')

    if [[ -z "$current_config" ]]; then
        __net_log__ "ERROR" "Interface $net_id not found on CT $ctid"
        echo "Error: Interface $net_id not found" >&2
        return 1
    fi

    local new_config

    # Add or replace gateway
    if echo "$current_config" | grep -q "gw="; then
        __net_log__ "DEBUG" "Replacing existing gateway"
        new_config="${current_config/gw=[^,]*/gw=${gateway}}"
    else
        __net_log__ "DEBUG" "Adding gateway"
        new_config="${current_config},gw=${gateway}"
    fi

    if pct set "$ctid" "-${net_id}" "$new_config" 2>/dev/null; then
        __net_log__ "INFO" "Set gateway for CT $ctid $net_id to $gateway"
        echo "Set gateway for $net_id to $gateway"
        return 0
    else
        __net_log__ "ERROR" "Failed to set gateway for CT $ctid $net_id"
        echo "Error: Failed to set gateway" >&2
        return 1
    fi
}

# --- __net_ct_set_nameserver__ -----------------------------------------------
# @function __net_ct_set_nameserver__
# @description Set nameserver for CT.
# @usage __net_ct_set_nameserver__ <ctid> <nameserver>
# @param 1 CTID
# @param 2 Nameserver IP address
# @return 0 on success, 1 on error
__net_ct_set_nameserver__() {
    local ctid="$1"
    local nameserver="$2"

    __net_log__ "DEBUG" "Setting nameserver for CT $ctid to $nameserver"

    if ! __ct_exists__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __net_validate_ip__ "$nameserver"; then
        __net_log__ "ERROR" "Invalid nameserver address: $nameserver"
        echo "Error: Invalid nameserver address: $nameserver" >&2
        return 1
    fi

    if pct set "$ctid" "-nameserver" "$nameserver" 2>/dev/null; then
        __net_log__ "INFO" "Set nameserver for CT $ctid to $nameserver"
        echo "Set nameserver to $nameserver"
        return 0
    else
        __net_log__ "ERROR" "Failed to set nameserver for CT $ctid"
        echo "Error: Failed to set nameserver" >&2
        return 1
    fi
}

# --- __net_ct_get_interfaces__ -----------------------------------------------
# @function __net_ct_get_interfaces__
# @description Get list of network interfaces for CT.
# @usage __net_ct_get_interfaces__ <ctid>
# @param 1 CTID
# @return 0 on success, prints interface list
__net_ct_get_interfaces__() {
    local ctid="$1"

    __net_log__ "DEBUG" "Getting network interfaces for CT $ctid"

    if ! __ct_exists__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    local count=0
    while IFS=':' read -r netid config; do
        echo "$netid: $config"
        count=$((count + 1))
    done < <(pct config "$ctid" | grep "^net[0-9]")

    __net_log__ "DEBUG" "Found $count network interface(s) for CT $ctid"

    return 0
}

###############################################################################
# IP Management and Validation
###############################################################################

# --- __net_validate_ip__ -----------------------------------------------------
# @function __net_validate_ip__
# @description Validate IPv4 address format.
# @usage __net_validate_ip__ <ip>
# @param 1 IP address
# @return 0 if valid, 1 if invalid
__net_validate_ip__() {
    local ip="$1"

    __net_log__ "TRACE" "Validating IP address: $ip"

    # Check format: xxx.xxx.xxx.xxx
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        __net_log__ "DEBUG" "IP validation failed (format): $ip"
        return 1
    fi

    # Check each octet is 0-255
    local IFS='.'
    local -a octets
    read -ra octets <<<"$ip"

    for octet in "${octets[@]}"; do
        if ((octet > 255)); then
            __net_log__ "DEBUG" "IP validation failed (octet > 255): $ip"
            return 1
        fi
    done

    __net_log__ "DEBUG" "IP validation passed: $ip"
    return 0
}

# --- __net_validate_cidr__ ---------------------------------------------------
# @function __net_validate_cidr__
# @description Validate IP address in CIDR notation.
# @usage __net_validate_cidr__ <cidr>
# @param 1 IP in CIDR notation (e.g., 192.168.1.10/24)
# @return 0 if valid, 1 if invalid
__net_validate_cidr__() {
    local cidr="$1"

    __net_log__ "TRACE" "Validating CIDR: $cidr"

    # Check format: IP/mask
    if [[ ! "$cidr" =~ ^([0-9.]+)/([0-9]+)$ ]]; then
        __net_log__ "DEBUG" "CIDR validation failed (format): $cidr"
        return 1
    fi

    local ip="${BASH_REMATCH[1]}"
    local mask="${BASH_REMATCH[2]}"

    # Validate IP
    if ! __net_validate_ip__ "$ip"; then
        __net_log__ "DEBUG" "CIDR validation failed (invalid IP): $cidr"
        return 1
    fi

    # Validate mask (0-32)
    if ((mask < 0 || mask > 32)); then
        __net_log__ "DEBUG" "CIDR validation failed (mask out of range): $cidr"
        return 1
    fi

    __net_log__ "DEBUG" "CIDR validation passed: $cidr"
    return 0
}

# --- __net_validate_mac__ ----------------------------------------------------
# @function __net_validate_mac__
# @description Validate MAC address format.
# @usage __net_validate_mac__ <mac>
# @param 1 MAC address
# @return 0 if valid, 1 if invalid
__net_validate_mac__() {
    local mac="$1"

    __net_log__ "TRACE" "Validating MAC address: $mac"

    # Check format: xx:xx:xx:xx:xx:xx or XX:XX:XX:XX:XX:XX
    if [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        __net_log__ "DEBUG" "MAC validation passed: $mac"
        return 0
    fi

    __net_log__ "DEBUG" "MAC validation failed: $mac"
    return 1
}

# --- __net_is_ip_in_use__ ----------------------------------------------------
# @function __net_is_ip_in_use__
# @description Check if IP address is in use by any VM/CT.
# @usage __net_is_ip_in_use__ <ip>
# @param 1 IP address
# @return 0 if in use, 1 if not in use
__net_is_ip_in_use__() {
    local search_ip="$1"

    __net_log__ "DEBUG" "Checking if IP is in use: $search_ip"

    # Search in all VM configs
    for vmid in $(qm list 2>/dev/null | awk 'NR>1 {print $1}'); do
        if qm config "$vmid" 2>/dev/null | grep -q "$search_ip"; then
            __net_log__ "INFO" "IP $search_ip in use by VM $vmid"
            echo "IP $search_ip in use by VM $vmid"
            return 0
        fi
    done

    # Search in all CT configs
    for ctid in $(pct list 2>/dev/null | awk 'NR>1 {print $1}'); do
        if pct config "$ctid" 2>/dev/null | grep -q "$search_ip"; then
            __net_log__ "INFO" "IP $search_ip in use by CT $ctid"
            echo "IP $search_ip in use by CT $ctid"
            return 0
        fi
    done

    return 1
}

# --- __net_get_next_ip__ -----------------------------------------------------
# @function __net_get_next_ip__
# @description Get next available IP in subnet.
# @usage __net_get_next_ip__ <base_ip> [start_host]
# @param 1 Base IP (e.g., 192.168.1.0)
# @param 2 Starting host number (default: 1)
# @return 0 on success, prints next available IP
__net_get_next_ip__() {
    local base_ip="$1"
    local start_host="${2:-1}"

    __net_log__ "DEBUG" "Finding next available IP from $base_ip starting at host $start_host"

    # Extract base network
    local IFS='.'
    local -a octets
    read -ra octets <<<"$base_ip"
    local base="${octets[0]}.${octets[1]}.${octets[2]}"

    # Check IPs starting from start_host
    for host in $(seq "$start_host" 254); do
        local test_ip="${base}.${host}"

        if ! __net_is_ip_in_use__ "$test_ip" &>/dev/null; then
            __net_log__ "INFO" "Found available IP: $test_ip"
            echo "$test_ip"
            return 0
        fi
    done

    __net_log__ "ERROR" "No available IPs in subnet $base.0"
    echo "Error: No available IPs in subnet" >&2
    return 1
}

###############################################################################
# Network Testing
###############################################################################

# --- __net_test_connectivity__ -----------------------------------------------
# @function __net_test_connectivity__
# @description Test network connectivity from VM/CT.
# @usage __net_test_connectivity__ <vmid_or_ctid> <target>
# @param 1 VM or CT ID
# @param 2 Target IP or hostname
# @return 0 if reachable, 1 if not reachable
__net_test_connectivity__() {
    local id="$1"
    local target="$2"

    __net_log__ "DEBUG" "Testing connectivity from $id to $target"

    # Try as VM first
    if __vm_exists__ "$id" &>/dev/null; then
        if __vm_is_running__ "$id"; then
            # For VMs, we'd need guest agent
            __net_log__ "INFO" "VM connectivity testing requires guest agent"
            echo "Note: VM connectivity testing requires guest agent"
            return 2
        else
            __net_log__ "ERROR" "VM $id is not running"
            echo "Error: VM $id is not running" >&2
            return 1
        fi
    # Try as CT
    elif __ct_exists__ "$id" &>/dev/null; then
        if __ct_is_running__ "$id"; then
            if pct exec "$id" -- ping -c 1 -W 2 "$target" &>/dev/null; then
                __net_log__ "INFO" "CT $id can reach $target"
                echo "CT $id can reach $target"
                return 0
            else
                __net_log__ "WARN" "CT $id cannot reach $target"
                echo "CT $id cannot reach $target"
                return 1
            fi
        else
            __net_log__ "ERROR" "CT $id is not running"
            echo "Error: CT $id is not running" >&2
            return 1
        fi
    else
        __net_log__ "ERROR" "ID $id not found"
        echo "Error: ID $id not found" >&2
        return 1
    fi
}

# --- __net_test_dns__ --------------------------------------------------------
# @function __net_test_dns__
# @description Test DNS resolution from CT.
# @usage __net_test_dns__ <ctid> <hostname>
# @param 1 CTID
# @param 2 Hostname to resolve
# @return 0 if resolvable, 1 if not
__net_test_dns__() {
    local ctid="$1"
    local hostname="$2"

    __net_log__ "DEBUG" "Testing DNS resolution for $hostname from CT $ctid"

    if ! __ct_exists__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __ct_is_running__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid is not running"
        echo "Error: CT $ctid is not running" >&2
        return 1
    fi

    if pct exec "$ctid" -- nslookup "$hostname" &>/dev/null; then
        __net_log__ "INFO" "DNS resolution successful for $hostname from CT $ctid"
        echo "DNS resolution successful for $hostname"
        return 0
    else
        __net_log__ "WARN" "DNS resolution failed for $hostname from CT $ctid"
        echo "DNS resolution failed for $hostname"
        return 1
    fi
}

# --- __net_test_gateway__ ----------------------------------------------------
# @function __net_test_gateway__
# @description Test gateway reachability from CT.
# @usage __net_test_gateway__ <ctid>
# @param 1 CTID
# @return 0 if gateway reachable, 1 if not
__net_test_gateway__() {
    local ctid="$1"

    __net_log__ "DEBUG" "Testing gateway reachability for CT $ctid"

    if ! __ct_exists__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid does not exist"
        echo "Error: CT $ctid does not exist" >&2
        return 1
    fi

    if ! __ct_is_running__ "$ctid"; then
        __net_log__ "ERROR" "CT $ctid is not running"
        echo "Error: CT $ctid is not running" >&2
        return 1
    fi

    # Get gateway from config
    local gateway
    gateway=$(pct config "$ctid" | grep "gw=" | head -1 | sed 's/.*gw=\([^,]*\).*/\1/')

    if [[ -z "$gateway" ]]; then
        __net_log__ "ERROR" "No gateway configured for CT $ctid"
        echo "Error: No gateway configured" >&2
        return 1
    fi

    __net_log__ "DEBUG" "Testing gateway $gateway"
    if pct exec "$ctid" -- ping -c 1 -W 2 "$gateway" &>/dev/null; then
        __net_log__ "INFO" "Gateway $gateway is reachable from CT $ctid"
        echo "Gateway $gateway is reachable"
        return 0
    else
        __net_log__ "WARN" "Gateway $gateway is not reachable from CT $ctid"
        echo "Gateway $gateway is not reachable"
        return 1
    fi
}

# --- __net_ping__ ------------------------------------------------------------
# @function __net_ping__
# @description Ping host from node.
# @usage __net_ping__ <host> [count]
# @param 1 Host IP or hostname
# @param 2 Ping count (default: 4)
# @return 0 if reachable, 1 if not
__net_ping__() {
    local host="$1"
    local count="${2:-4}"

    __net_log__ "DEBUG" "Pinging $host (count=$count)"

    if ping -c "$count" -W 2 "$host" &>/dev/null; then
        __net_log__ "INFO" "Host $host is reachable"
        echo "Host $host is reachable"
        return 0
    else
        __net_log__ "WARN" "Host $host is not reachable"
        echo "Host $host is not reachable"
        return 1
    fi
}

###############################################################################
# Bulk Network Operations
###############################################################################

# --- __net_bulk_set_bridge__ -------------------------------------------------
# @function __net_bulk_set_bridge__
# @description Change bridge for multiple VMs.
# @usage __net_bulk_set_bridge__ <start_vmid> <end_vmid> <net_id> <bridge>
# @param 1 Start VMID
# @param 2 End VMID
# @param 3 Network ID (net0, net1, etc.)
# @param 4 New bridge name
# @return 0 on success, 1 if any failed
__net_bulk_set_bridge__() {
    local start_vmid="$1"
    local end_vmid="$2"
    local net_id="$3"
    local bridge="$4"

    __net_log__ "INFO" "Bulk bridge change: range=$start_vmid-$end_vmid, interface=$net_id, bridge=$bridge"

    local success=0
    local failed=0

    for ((vmid = start_vmid; vmid <= end_vmid; vmid++)); do
        if __net_vm_set_bridge__ "$vmid" "$net_id" "$bridge" 2>/dev/null; then
            ((success += 1))
        else
            ((failed += 1))
        fi
    done

    __net_log__ "INFO" "Bulk bridge change complete: $success succeeded, $failed failed"
    echo "Bulk bridge change complete: $success succeeded, $failed failed"

    if ((failed > 0)); then
        return 1
    else
        return 0
    fi
}

# --- __net_bulk_set_vlan__ ---------------------------------------------------
# @function __net_bulk_set_vlan__
# @description Set VLAN tag for multiple VMs.
# @usage __net_bulk_set_vlan__ <start_vmid> <end_vmid> <net_id> <vlan>
# @param 1 Start VMID
# @param 2 End VMID
# @param 3 Network ID (net0, net1, etc.)
# @param 4 VLAN tag
# @return 0 on success, 1 if any failed
__net_bulk_set_vlan__() {
    local start_vmid="$1"
    local end_vmid="$2"
    local net_id="$3"
    local vlan="$4"

    __net_log__ "INFO" "Bulk VLAN change: range=$start_vmid-$end_vmid, interface=$net_id, vlan=$vlan"

    local success=0
    local failed=0

    for ((vmid = start_vmid; vmid <= end_vmid; vmid++)); do
        if __net_vm_set_vlan__ "$vmid" "$net_id" "$vlan" 2>/dev/null; then
            ((success += 1))
        else
            ((failed += 1))
        fi
    done

    __net_log__ "INFO" "Bulk VLAN change complete: $success succeeded, $failed failed"
    echo "Bulk VLAN change complete: $success succeeded, $failed failed"

    if ((failed > 0)); then
        return 1
    else
        return 0
    fi
}

# --- __net_migrate_network__ -------------------------------------------------
# @function __net_migrate_network__
# @description Migrate VMs from one bridge/VLAN to another.
# @usage __net_migrate_network__ <start_vmid> <end_vmid> <net_id> [options]
# @param 1 Start VMID
# @param 2 End VMID
# @param 3 Network ID
# @param --from-bridge Source bridge
# @param --to-bridge Destination bridge
# @param --from-vlan Source VLAN
# @param --to-vlan Destination VLAN
# @return 0 on success, 1 if any failed
__net_migrate_network__() {
    local start_vmid="$1"
    local end_vmid="$2"
    local net_id="$3"
    shift 3

    local to_bridge=""
    local to_vlan=""

    __net_log__ "DEBUG" "Network migration: range=$start_vmid-$end_vmid, interface=$net_id"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from-bridge)
                # from_bridge parameter accepted but not used (for future filtering)
                shift 2
                ;;
            --to-bridge)
                to_bridge="$2"
                __net_log__ "DEBUG" "Migrating to bridge: $to_bridge"
                shift 2
                ;;
            --from-vlan)
                # from_vlan parameter accepted but not used (for future filtering)
                shift 2
                ;;
            --to-vlan)
                to_vlan="$2"
                __net_log__ "DEBUG" "Migrating to VLAN: $to_vlan"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local success=0
    local failed=0
    local skipped=0

    for ((vmid = start_vmid; vmid <= end_vmid; vmid++)); do
        if ! __vm_exists__ "$vmid" &>/dev/null; then
            ((skipped += 1))
            continue
        fi

        local changed=false

        # Change bridge if specified
        if [[ -n "$to_bridge" ]]; then
            if __net_vm_set_bridge__ "$vmid" "$net_id" "$to_bridge" 2>/dev/null; then
                changed=true
            fi
        fi

        # Change VLAN if specified
        if [[ -n "$to_vlan" ]]; then
            if __net_vm_set_vlan__ "$vmid" "$net_id" "$to_vlan" 2>/dev/null; then
                changed=true
            fi
        fi

        if [[ "$changed" == "true" ]]; then
            ((success += 1))
        else
            ((failed += 1))
        fi
    done

    __net_log__ "INFO" "Network migration complete: $success succeeded, $failed failed, $skipped skipped"

    echo "Network migration complete:"
    echo "  Success: $success"
    echo "  Failed:  $failed"
    echo "  Skipped: $skipped"

    if ((failed > 0)); then
        return 1
    else
        return 0
    fi
}

###############################################################################
# Example Usage (commented out)
###############################################################################
#
# # Add network interface to VM
# __net_vm_add_interface__ 100 net1 --bridge vmbr1 --vlan 10
#
# # Change bridge for VM
# __net_vm_set_bridge__ 100 net0 vmbr2
#
# # Add network interface to CT with static IP
# __net_ct_add_interface__ 200 net0 --bridge vmbr0 --ip 192.168.1.100/24 --gateway 192.168.1.1
#
# # Validate IP address
# __net_validate_ip__ "192.168.1.1"
#
# # Check if IP is in use
# __net_is_ip_in_use__ "192.168.1.100"
#
# # Bulk change bridge
# __net_bulk_set_bridge__ 100 110 net0 vmbr1
#
# # Test connectivity from CT
# __net_test_connectivity__ 200 "8.8.8.8"
#

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Fixed ShellCheck warnings (SC2155, SC2001, SC2030/2031, SC2206, SC2034)
#
# Fixes:
# - 2025-11-24: Separated variable declaration/assignment for proper error handling
# - 2025-11-24: Changed pipeline to process substitution to fix subshell variable scope
# - 2025-11-24: Used bash parameter expansion instead of sed for simple replacements
# - 2025-11-24: Used read -ra for proper array splitting
# - 2025-11-24: Removed unused from_bridge and from_vlan variables (reserved for future use)
#
# Known issues:
# -
#

