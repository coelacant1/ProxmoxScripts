#!/bin/bash
#
# BulkConfigureNetwork.sh
#
# Configures network interface settings for a range of virtual machines (VMs) on a Proxmox VE cluster.
# Supports comprehensive network configuration including bridge, VLAN, firewall, MTU, rate limiting,
# multiqueue, MAC address, and NIC model settings.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkConfigureNetwork.sh 100 110 --bridge vmbr1
#   BulkConfigureNetwork.sh 100 110 --bridge vmbr0 --vlan 100
#   BulkConfigureNetwork.sh 400 410 --bridge vmbr1 --vlan 50 --firewall 1 --mtu 9000 --rate 1000 --queues 4 --model virtio
#   BulkConfigureNetwork.sh 100 110 --mac-prefix BC:24:11
#   BulkConfigureNetwork.sh 100 110 --link-down 1
#   BulkConfigureNetwork.sh 100 110 --rate 100 --queues 8
#
# Arguments:
#   start_id               - Starting VM ID in the range
#   end_id                 - Ending VM ID in the range
#   --bridge <bridge>      - Network bridge (e.g., vmbr0, vmbr1)
#   --vlan <tag>          - VLAN tag (1-4094)
#   --firewall <0|1>      - Enable/disable firewall (0=off, 1=on)
#   --link-down <0|1>     - Disconnect/connect network (0=connected, 1=disconnected)
#   --mtu <bytes>         - MTU size (576-65520 bytes)
#   --rate <mbps>         - Rate limit in Mbps
#   --queues <num>        - Number of multiqueue queues (0-16, 0=disabled)
#   --mac <address>       - MAC address (e.g., BC:24:11:00:01:00)
#   --mac-prefix <prefix> - MAC address prefix (e.g., BC:24:11, auto-generates rest from VMID)
#   --model <type>        - NIC model (virtio, e1000, rtl8139, vmxnet3, etc.)
#   --net-id <id>         - Network interface ID (default: net0)
#
# NIC Models: virtio, e1000, e1000-82540em, e1000-82544gc, e1000-82545em, i82551, i82557b,
#             i82559er, ne2k_isa, ne2k_pci, pcnet, rtl8139, vmxnet3
#
# Notes:
#   - At least one network option must be specified
#   - MAC prefix auto-generates last 3 octets from VMID
#   - VLAN tags range from 1-4094
#   - MTU range: 576-65520 bytes
#
# Function Index:
#   - validate_custom_options
#   - generate_mac_from_vmid
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- validate_custom_options -------------------------------------------------
# @function validate_custom_options
# @description Validates network-specific configuration options not covered by ArgumentParser.
validate_custom_options() {
    # Check that at least one network option is specified
    if [[ -z "$BRIDGE" && -z "$VLAN" && -z "$FIREWALL" && -z "$LINK_DOWN" && \
          -z "$MTU" && -z "$RATE" && -z "$QUEUES" && -z "$MAC" && \
          -z "$MAC_PREFIX" && -z "$MODEL" ]]; then
        __err__ "At least one network option must be specified"
        exit 64
    fi

    # Validate MAC address format
    if [[ -n "$MAC" && ! "$MAC" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        __err__ "Invalid MAC address format. Use XX:XX:XX:XX:XX:XX"
        exit 64
    fi

    # Validate MAC prefix format
    if [[ -n "$MAC_PREFIX" && ! "$MAC_PREFIX" =~ ^([0-9A-Fa-f]{2}:){2}[0-9A-Fa-f]{2}$ ]]; then
        __err__ "Invalid MAC prefix format. Use XX:XX:XX"
        exit 64
    fi

    # Validate NIC model
    if [[ -n "$MODEL" ]]; then
        local valid_models="e1000 e1000-82540em e1000-82544gc e1000-82545em i82551 i82557b i82559er ne2k_isa ne2k_pci pcnet rtl8139 virtio vmxnet3"
        if ! echo "$valid_models" | grep -qw "$MODEL"; then
            __err__ "Invalid NIC model: ${MODEL}"
            __err__ "Valid models: ${valid_models}"
            exit 64
        fi
    fi
}

# --- generate_mac_from_vmid --------------------------------------------------
# @function generate_mac_from_vmid
# @description Generates a MAC address from prefix and VMID.
# @param 1 VM ID
# @return MAC address
generate_mac_from_vmid() {
    local vmid="$1"
    local prefix="$MAC_PREFIX"

    # Convert VMID to hex and pad to 6 digits
    local vmid_hex=$(printf "%06X" "$vmid")

    # Split into 3 octets
    local octet1="${vmid_hex:0:2}"
    local octet2="${vmid_hex:2:2}"
    local octet3="${vmid_hex:4:2}"

    echo "${prefix}:${octet1}:${octet2}:${octet3}"
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Parse arguments using ArgumentParser
    __parse_args__ "start_id:vmid end_id:vmid --bridge:bridge:? --vlan:vlan:? --firewall:boolean:? --link-down:boolean:? --mtu:number:? --rate:number:? --queues:number:? --mac:string:? --mac-prefix:string:? --model:string:? --net-id:string:net0" "$@"

    # Additional custom validation
    validate_custom_options

    __info__ "Bulk configure network: VMs ${START_ID} to ${END_ID} (cluster-wide)"
    __info__ "Network interface: ${NET_ID}"
    [[ -n "$BRIDGE" ]] && __info__ "  Bridge: ${BRIDGE}"
    [[ -n "$VLAN" ]] && __info__ "  VLAN: ${VLAN}"
    [[ -n "$FIREWALL" ]] && __info__ "  Firewall: ${FIREWALL}"
    [[ -n "$LINK_DOWN" ]] && __info__ "  Link Down: ${LINK_DOWN}"
    [[ -n "$MTU" ]] && __info__ "  MTU: ${MTU}"
    [[ -n "$RATE" ]] && __info__ "  Rate Limit: ${RATE} Mbps"
    [[ -n "$QUEUES" ]] && __info__ "  Queues: ${QUEUES}"
    [[ -n "$MAC" ]] && __info__ "  MAC: ${MAC}"
    [[ -n "$MAC_PREFIX" ]] && __info__ "  MAC Prefix: ${MAC_PREFIX} (auto-generate from VMID)"
    [[ -n "$MODEL" ]] && __info__ "  Model: ${MODEL}"

    # Confirm action
    if ! __prompt_user_yn__ "Configure network for VMs ${START_ID}-${END_ID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi

    # Local callback for bulk operation
    configure_network_callback() {
        local vmid="$1"
        local node

        node=$(__get_vm_node__ "$vmid")

        if [[ -z "$node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        __update__ "Configuring network for VM ${vmid} on node ${node}..."

        # Get current network configuration
        local current_config
        current_config=$(qm config "$vmid" --node "$node" 2>/dev/null | grep "^${NET_ID}:" | cut -d' ' -f2- || echo "")

        if [[ -z "$current_config" ]]; then
            __update__ "VM ${vmid} has no ${NET_ID} interface"
            return 1
        fi

        # Build new configuration by modifying existing config
        local new_config="$current_config"

        # Update bridge
        if [[ -n "$BRIDGE" ]]; then
            new_config=$(echo "$new_config" | sed "s/bridge=[^,]*/bridge=${BRIDGE}/")
            if ! echo "$new_config" | grep -q "bridge="; then
                new_config="${new_config},bridge=${BRIDGE}"
            fi
        fi

        # Update VLAN
        if [[ -n "$VLAN" ]]; then
            new_config=$(echo "$new_config" | sed "s/tag=[^,]*/tag=${VLAN}/")
            if ! echo "$new_config" | grep -q "tag="; then
                new_config="${new_config},tag=${VLAN}"
            fi
        fi

        # Update firewall
        if [[ -n "$FIREWALL" ]]; then
            new_config=$(echo "$new_config" | sed "s/firewall=[^,]*/firewall=${FIREWALL}/")
            if ! echo "$new_config" | grep -q "firewall="; then
                new_config="${new_config},firewall=${FIREWALL}"
            fi
        fi

        # Update link-down
        if [[ -n "$LINK_DOWN" ]]; then
            new_config=$(echo "$new_config" | sed "s/link_down=[^,]*/link_down=${LINK_DOWN}/")
            if ! echo "$new_config" | grep -q "link_down="; then
                new_config="${new_config},link_down=${LINK_DOWN}"
            fi
        fi

        # Update MTU
        if [[ -n "$MTU" ]]; then
            new_config=$(echo "$new_config" | sed "s/mtu=[^,]*/mtu=${MTU}/")
            if ! echo "$new_config" | grep -q "mtu="; then
                new_config="${new_config},mtu=${MTU}"
            fi
        fi

        # Update rate
        if [[ -n "$RATE" ]]; then
            new_config=$(echo "$new_config" | sed "s/rate=[^,]*/rate=${RATE}/")
            if ! echo "$new_config" | grep -q "rate="; then
                new_config="${new_config},rate=${RATE}"
            fi
        fi

        # Update queues
        if [[ -n "$QUEUES" ]]; then
            new_config=$(echo "$new_config" | sed "s/queues=[^,]*/queues=${QUEUES}/")
            if ! echo "$new_config" | grep -q "queues="; then
                new_config="${new_config},queues=${QUEUES}"
            fi
        fi

        # Update MAC address
        local mac_to_set=""
        if [[ -n "$MAC" ]]; then
            mac_to_set="$MAC"
        elif [[ -n "$MAC_PREFIX" ]]; then
            mac_to_set=$(generate_mac_from_vmid "$vmid")
        fi

        if [[ -n "$mac_to_set" ]]; then
            # Extract model from current config or use existing
            local model_part=""
            if echo "$new_config" | grep -q "^[^=]*="; then
                model_part=$(echo "$new_config" | cut -d'=' -f1)
            else
                model_part="virtio"
            fi
            new_config=$(echo "$new_config" | sed "s/^[^=]*=/${model_part}=${mac_to_set}/")
        fi

        # Update model
        if [[ -n "$MODEL" ]]; then
            new_config=$(echo "$new_config" | sed "s/^[^=]*=/${MODEL}=/")
        fi

        # Apply configuration
        if qm set "$vmid" --node "$node" "--${NET_ID}" "$new_config" 2>&1; then
            return 0
        else
            return 1
        fi
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Network Configuration" --report "$START_ID" "$END_ID" configure_network_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All network configurations completed successfully!"
}

main "$@"

# Testing status:
#   - 2025-11-04: Refactored to use ArgumentParser.sh declarative parsing
#   - Removed manual usage() and parse_args() functions
#   - Now uses __parse_args__ with automatic validation
#   - Fixed __prompt_yes_no__ -> __prompt_user_yn__
#   - Added missing Cluster.sh source for __get_vm_node__
