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
