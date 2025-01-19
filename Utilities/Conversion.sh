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
#

###############################################################################
# IP Conversion Utilities
###############################################################################

# @function __ip_to_int__
# @description Converts a dotted IPv4 address string to its 32-bit integer equivalent.
# @usage
#   local ip_integer=$(__ip_to_int__ "127.0.0.1")
# @param 1 Dotted IPv4 address string (e.g., "192.168.1.10")
# @return
#   Prints the 32-bit integer representation of the IP to stdout.
__ip_to_int__() {
    local a b c d
    IFS=. read -r a b c d <<<"$1"
    echo "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

# @function __int_to_ip__
# @description Converts a 32-bit integer to its dotted IPv4 address equivalent.
# @usage
#   local ip_string=$(__int_to_ip__ 2130706433)
# @param 1 32-bit integer
# @return
#   Prints the dotted IPv4 address string to stdout.
__int_to_ip__() {
    local ip
    ip=$(printf "%d.%d.%d.%d" \
        "$((($1 >> 24) & 255))" \
        "$((($1 >> 16) & 255))" \
        "$((($1 >> 8) & 255))" \
        "$(($1 & 255))")
    echo "$ip"
}
