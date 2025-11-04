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
#   BulkConfigureNetwork.sh <start_id> <end_id> [options]
#
# Arguments:
#   start_id  - The starting VM ID in the range to be processed
#   end_id    - The ending VM ID in the range to be processed
#
# Network Configuration Options:
#   --bridge <bridge>        - Network bridge (e.g., vmbr0, vmbr1)
#   --vlan <tag>            - VLAN tag (1-4094)
#   --firewall <0|1>        - Enable/disable firewall (0=off, 1=on)
#   --link-down <0|1>       - Disconnect/connect network (0=connected, 1=disconnected)
#   --mtu <bytes>           - MTU size (576-65520 bytes)
#   --rate <mbps>           - Rate limit in Mbps
#   --queues <num>          - Number of multiqueue queues (0-16, 0=disabled)
#   --mac <address>         - MAC address (e.g., BC:24:11:00:01:00)
#   --mac-prefix <prefix>   - MAC address prefix (e.g., BC:24:11, auto-generates rest)
#   --model <type>          - NIC model (e1000, e1000-82540em, e1000-82544gc, e1000-82545em,
#                             i82551, i82557b, i82559er, ne2k_isa, ne2k_pci, pcnet, rtl8139,
#                             virtio, vmxnet3)
#   --net-id <id>           - Network interface ID (default: net0)
#
# Examples:
#   # Change bridge only
#   BulkConfigureNetwork.sh 100 110 --bridge vmbr1
#
#   # Configure bridge with VLAN
#   BulkConfigureNetwork.sh 100 110 --bridge vmbr0 --vlan 100
#
#   # Full configuration with multiple options
#   BulkConfigureNetwork.sh 400 410 --bridge vmbr1 --vlan 50 --firewall 1 --mtu 9000 --rate 1000 --queues 4 --model virtio
#
#   # Set MAC address with prefix (auto-generates last 3 octets from VMID)
#   BulkConfigureNetwork.sh 100 110 --mac-prefix BC:24:11
#
#   # Disconnect network interfaces
#   BulkConfigureNetwork.sh 100 110 --link-down 1
#
#   # Rate limit to 100 Mbps with multiqueue
#   BulkConfigureNetwork.sh 100 110 --rate 100 --queues 8
#
# Function Index:
#   - usage
#   - parse_args
#   - validate_options
#   - generate_mac_from_vmid
#   - main
#   - configure_network_callback
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Global variables
START_ID=""
END_ID=""
BRIDGE=""
VLAN=""
FIREWALL=""
LINK_DOWN=""
MTU=""
RATE=""
QUEUES=""
MAC=""
MAC_PREFIX=""
MODEL=""
NET_ID="net0"

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_id> <end_id> [options]

Configures network interface settings for a range of VMs cluster-wide.

Arguments:
  start_id  - Starting VM ID
  end_id    - Ending VM ID

Network Options:
  --bridge <bridge>       - Network bridge (e.g., vmbr0, vmbr1)
  --vlan <tag>           - VLAN tag (1-4094)
  --firewall <0|1>       - Enable/disable firewall
  --link-down <0|1>      - Disconnect (1) or connect (0) network
  --mtu <bytes>          - MTU size (576-65520)
  --rate <mbps>          - Rate limit in Mbps
  --queues <num>         - Multiqueue queues (0-16, 0=disabled)
  --mac <address>        - Full MAC address (e.g., BC:24:11:00:01:00)
  --mac-prefix <prefix>  - MAC prefix, auto-generate rest from VMID
  --model <type>         - NIC model (virtio, e1000, rtl8139, vmxnet3, etc.)
  --net-id <id>          - Network interface ID (default: net0)

NIC Models:
  - virtio (recommended for Linux)
  - e1000, e1000-82540em, e1000-82544gc, e1000-82545em
  - i82551, i82557b, i82559er
  - ne2k_isa, ne2k_pci, pcnet, rtl8139
  - vmxnet3 (VMware compatible)

Examples:
  # Change bridge with VLAN
  ${0##*/} 100 110 --bridge vmbr1 --vlan 100

  # Full configuration
  ${0##*/} 400 410 --bridge vmbr0 --vlan 50 --firewall 1 --mtu 9000 --rate 1000 --queues 4 --model virtio

  # Set MAC prefix (auto-generates last 3 octets from VMID)
  ${0##*/} 100 110 --mac-prefix BC:24:11

  # Disconnect all network interfaces
  ${0##*/} 100 110 --link-down 1
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_ID="$1"
    END_ID="$2"
    shift 2

    # Validate IDs are numeric
    if ! [[ "$START_ID" =~ ^[0-9]+$ ]] || ! [[ "$END_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_ID > END_ID )); then
        __err__ "Start ID must be less than or equal to end ID"
        exit 64
    fi

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --bridge)
                BRIDGE="$2"
                shift 2
                ;;
            --vlan)
                VLAN="$2"
                shift 2
                ;;
            --firewall)
                FIREWALL="$2"
                shift 2
                ;;
            --link-down)
                LINK_DOWN="$2"
                shift 2
                ;;
            --mtu)
                MTU="$2"
                shift 2
                ;;
            --rate)
                RATE="$2"
                shift 2
                ;;
            --queues)
                QUEUES="$2"
                shift 2
                ;;
            --mac)
                MAC="$2"
                shift 2
                ;;
            --mac-prefix)
                MAC_PREFIX="$2"
                shift 2
                ;;
            --model)
                MODEL="$2"
                shift 2
                ;;
            --net-id)
                NET_ID="$2"
                shift 2
                ;;
            *)
                __err__ "Unknown option: $1"
                usage
                exit 64
                ;;
        esac
    done

    # Check that at least one option is specified
    if [[ -z "$BRIDGE" && -z "$VLAN" && -z "$FIREWALL" && -z "$LINK_DOWN" && \
          -z "$MTU" && -z "$RATE" && -z "$QUEUES" && -z "$MAC" && \
          -z "$MAC_PREFIX" && -z "$MODEL" ]]; then
        __err__ "At least one network option must be specified"
        usage
        exit 64
    fi
}

# --- validate_options --------------------------------------------------------
# @function validate_options
# @description Validates network configuration options.
validate_options() {
    # Validate VLAN tag
    if [[ -n "$VLAN" ]]; then
        if ! [[ "$VLAN" =~ ^[0-9]+$ ]] || (( VLAN < 1 || VLAN > 4094 )); then
            __err__ "VLAN tag must be between 1 and 4094"
            exit 64
        fi
    fi

    # Validate firewall setting
    if [[ -n "$FIREWALL" && ! "$FIREWALL" =~ ^[01]$ ]]; then
        __err__ "Firewall must be 0 or 1"
        exit 64
    fi

    # Validate link-down setting
    if [[ -n "$LINK_DOWN" && ! "$LINK_DOWN" =~ ^[01]$ ]]; then
        __err__ "Link-down must be 0 or 1"
        exit 64
    fi

    # Validate MTU
    if [[ -n "$MTU" ]]; then
        if ! [[ "$MTU" =~ ^[0-9]+$ ]] || (( MTU < 576 || MTU > 65520 )); then
            __err__ "MTU must be between 576 and 65520"
            exit 64
        fi
    fi

    # Validate rate limit
    if [[ -n "$RATE" && ! "$RATE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        __err__ "Rate must be a positive number"
        exit 64
    fi

    # Validate queues
    if [[ -n "$QUEUES" ]]; then
        if ! [[ "$QUEUES" =~ ^[0-9]+$ ]] || (( QUEUES < 0 || QUEUES > 16 )); then
            __err__ "Queues must be between 0 and 16"
            exit 64
        fi
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

    # Validate model
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

    # Validate options
    validate_options

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
    if ! __prompt_yes_no__ "Configure network for VMs ${START_ID}-${END_ID}?"; then
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

        __update__ "Configuring network for VM ${vmid}..."

        # Get current network configuration
        local current_config
        current_config=$(qm config "$vmid" --node "$node" 2>/dev/null | grep "^${NET_ID}:" || true)

        if [[ -z "$current_config" ]]; then
            __update__ "Network interface ${NET_ID} not found on VM ${vmid}"
            return 1
        fi

        # Build qm set command
        local cmd="qm set \"$vmid\" --node \"$node\""
        local net_config=""

        # Parse existing configuration
        local existing_model=$(echo "$current_config" | sed -n 's/.*model=\([^,]*\).*/\1/p')
        local existing_bridge=$(echo "$current_config" | sed -n 's/.*bridge=\([^,]*\).*/\1/p')
        local existing_mac=$(echo "$current_config" | sed -n 's/.*=\([0-9A-Fa-f:]*\),.*/\1/p')

        # Start building network configuration string
        # Model
        if [[ -n "$MODEL" ]]; then
            net_config="${MODEL}"
        elif [[ -n "$existing_model" ]]; then
            net_config="${existing_model}"
        else
            net_config="virtio"
        fi

        # MAC address
        if [[ -n "$MAC" ]]; then
            net_config+=",macaddr=${MAC}"
        elif [[ -n "$MAC_PREFIX" ]]; then
            local generated_mac=$(generate_mac_from_vmid "$vmid")
            net_config+=",macaddr=${generated_mac}"
        elif [[ -n "$existing_mac" ]]; then
            net_config+=",macaddr=${existing_mac}"
        fi

        # Bridge
        if [[ -n "$BRIDGE" ]]; then
            net_config+=",bridge=${BRIDGE}"
        elif [[ -n "$existing_bridge" ]]; then
            net_config+=",bridge=${existing_bridge}"
        fi

        # VLAN tag
        [[ -n "$VLAN" ]] && net_config+=",tag=${VLAN}"

        # Firewall
        [[ -n "$FIREWALL" ]] && net_config+=",firewall=${FIREWALL}"

        # Link down (disconnect)
        [[ -n "$LINK_DOWN" ]] && net_config+=",link_down=${LINK_DOWN}"

        # MTU
        [[ -n "$MTU" ]] && net_config+=",mtu=${MTU}"

        # Rate limit
        [[ -n "$RATE" ]] && net_config+=",rate=${RATE}"

        # Multiqueue
        [[ -n "$QUEUES" ]] && net_config+=",queues=${QUEUES}"

        # Execute configuration
        cmd+=" --${NET_ID} \"${net_config}\""

        if eval "$cmd" 2>&1; then
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

parse_args "$@"
main

# Testing status:
#   - Updated to use BulkOperations framework
