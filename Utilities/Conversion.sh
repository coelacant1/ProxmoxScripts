#!/bin/bash
#
# Conversion.sh
#
# Provides utility functions for converting data structures, such as
# converting a dotted IPv4 address to its 32-bit integer representation
# (and vice versa).
#
# Usage:
#   source "Conversion.sh"
#
# Example:
#   source "./Conversion.sh"
#
# This script is mainly intended as a library of functions to be sourced
# by other scripts. If invoked directly, it currently has no standalone
# actions.
#
# Function Index:
#   - __ip_to_int__
#   - __int_to_ip__
#   - __cidr_to_netmask__
#   - __vmid_to_mac_prefix__
#

###############################################################################
# IP Conversion Utilities
###############################################################################

# --- __ip_to_int__ ------------------------------------------------------------
# @function __ip_to_int__
# @description Converts a dotted IPv4 address string to its 32-bit integer equivalent.
# @usage __ip_to_int__ "127.0.0.1"
# @param 1 Dotted IPv4 address string (e.g., "192.168.1.10")
# @return Prints the 32-bit integer representation of the IP to stdout.
# @example_output For __ip_to_int__ "127.0.0.1", the output is: 2130706433
__ip_to_int__() {
    local a b c d
    IFS=. read -r a b c d <<<"$1"
    echo "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

# --- __int_to_ip__ ------------------------------------------------------------
# @function __int_to_ip__
# @description Converts a 32-bit integer to its dotted IPv4 address equivalent.
# @usage __int_to_ip__ 2130706433
# @param 1 32-bit integer
# @return Prints the dotted IPv4 address string to stdout.
# @example_output For __int_to_ip__ 2130706433, the output is: 127.0.0.1
__int_to_ip__() {
    local ip
    ip=$(printf "%d.%d.%d.%d" \
        "$((($1 >> 24) & 255))" \
        "$((($1 >> 16) & 255))" \
        "$((($1 >> 8) & 255))" \
        "$(($1 & 255))")
    echo "$ip"
}

# --- __cidr_to_netmask__ ------------------------------------------------------------
# @function __cidr_to_netmask__
# @description Converts a CIDR prefix to a dotted-decimal netmask.
# @usage __cidr_to_netmask__ 18
# @param 1 CIDR prefix (e.g., 18)
# @return Prints the full subnet netmask.
# @example_output For __cidr_to_netmask__ 18, the output is: 255.255.192.0
__cidr_to_netmask__() {
  local cidr="$1"
  local mask=$(( 0xffffffff << (32 - cidr) & 0xffffffff ))
  local octet1=$(( (mask >> 24) & 255 ))
  local octet2=$(( (mask >> 16) & 255 ))
  local octet3=$(( (mask >>  8) & 255 ))
  local octet4=$((  mask        & 255 ))
  echo "${octet1}.${octet2}.${octet3}.${octet4}"
}

# --- __vmid_to_mac_prefix__ -------------------------------------------------
# @function __vmid_to_mac_prefix__
# @description Converts a numeric VMID into a deterministic MAC prefix string (e.g., BC:12:34).
# @usage __vmid_to_mac_prefix__ --vmid 1234 [--prefix BC] [--pad-length 4]
# @flags
#   --vmid <vmid>         Integer VMID (required).
#   --prefix <prefix>     Two-hex-character vendor prefix (default "BC").
#   --pad-length <len>    Total digits (must be even, default 4). Additional digits produce extra octets.
# @return Prints the computed MAC prefix (uppercase) to stdout.
# @example __vmid_to_mac_prefix__ --vmid 27
# @example __vmid_to_mac_prefix__ --vmid 512 --prefix aa --pad-length 6
__vmid_to_mac_prefix__() {
    local vmid=""
    local prefix="BC"
    local padLength=4

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --vmid)
                vmid="$2"
                shift 2
                ;;
            --prefix)
                prefix="$2"
                shift 2
                ;;
            --pad-length)
                padLength="$2"
                shift 2
                ;;
            --)
                shift
                ;;
            *)
                echo "Error: Unknown option '$1' passed to __vmid_to_mac_prefix__." >&2
                return 1
                ;;
        esac
    done

    if [[ -z "$vmid" ]]; then
        echo "Error: __vmid_to_mac_prefix__ requires --vmid." >&2
        return 1
    fi

    if [[ ! "$vmid" =~ ^[0-9]+$ ]]; then
        echo "Error: VMID must be a non-negative integer." >&2
        return 1
    fi

    if [[ -z "$padLength" || ! "$padLength" =~ ^[0-9]+$ ]]; then
        echo "Error: --pad-length must be a positive integer." >&2
        return 1
    fi

    if (( padLength <= 0 || padLength % 2 != 0 )); then
        echo "Error: --pad-length must be a positive, even integer." >&2
        return 1
    fi

        local padded
        printf -v padded "%0${padLength}d" "$vmid"

        local effectiveLength=${#padded}
        if (( effectiveLength % 2 != 0 )); then
            padded="0${padded}"
            ((effectiveLength++))
        fi

        local -a segments=()
        local i
        for (( i = 0; i < effectiveLength; i += 2 )); do
            segments+=("${padded:i:2}")
        done

    local upperPrefix
    upperPrefix=$(echo "$prefix" | tr '[:lower:]' '[:upper:]')

    local result="$upperPrefix"
    local segment
    for segment in "${segments[@]}"; do
        result+=":${segment^^}"
    done

    echo "$result"
}
