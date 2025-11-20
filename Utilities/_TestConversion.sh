#!/bin/bash
#
# Function Index:
#   - test_ip_to_int_localhost
#   - test_ip_to_int_private
#   - test_ip_to_int_class_a
#   - test_int_to_ip_localhost
#   - test_int_to_ip_private
#   - test_int_to_ip_class_a
#   - test_vmid_to_mac_basic
#   - test_vmid_to_mac_padding
#   - test_vmid_to_mac_long
#

set -euo pipefail

################################################################################
# _TestConversion.sh - Test suite for Conversion.sh
################################################################################
#
# Usage: ./_TestConversion.sh
#
# Tests all conversion functions including IP-to-int, int-to-IP, and VMID-to-MAC
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

# Suppress verbose logging during tests
export LOG_LEVEL=ERROR

source "${SCRIPT_DIR}/TestFramework.sh"
source "${SCRIPT_DIR}/Conversion.sh"

################################################################################
# TEST: IP TO INTEGER CONVERSIONS
################################################################################

test_ip_to_int_localhost() {
    local result
    result="$(__ip_to_int__ "127.0.0.1")"
    assert_equals "2130706433" "$result" "Should convert 127.0.0.1 to integer"
}

test_ip_to_int_private() {
    local result
    result="$(__ip_to_int__ "192.168.1.10")"
    assert_equals "3232235786" "$result" "Should convert 192.168.1.10 to integer"
}

test_ip_to_int_class_a() {
    local result
    result="$(__ip_to_int__ "10.0.0.255")"
    assert_equals "167772415" "$result" "Should convert 10.0.0.255 to integer"
}

################################################################################
# TEST: INTEGER TO IP CONVERSIONS
################################################################################

test_int_to_ip_localhost() {
    local result
    result="$(__int_to_ip__ "2130706433")"
    assert_equals "127.0.0.1" "$result" "Should convert integer to 127.0.0.1"
}

test_int_to_ip_private() {
    local result
    result="$(__int_to_ip__ "3232235786")"
    assert_equals "192.168.1.10" "$result" "Should convert integer to 192.168.1.10"
}

test_int_to_ip_class_a() {
    local result
    result="$(__int_to_ip__ "167772415")"
    assert_equals "10.0.0.255" "$result" "Should convert integer to 10.0.0.255"
}

################################################################################
# TEST: VMID TO MAC PREFIX CONVERSIONS
################################################################################

test_vmid_to_mac_basic() {
    local result
    result="$(__vmid_to_mac_prefix__ --vmid "1346")"
    assert_equals "BC:13:46" "$result" "Should convert VMID 1346 to MAC prefix"
}

test_vmid_to_mac_padding() {
    local result
    result="$(__vmid_to_mac_prefix__ --vmid "12")"
    assert_equals "BC:00:12" "$result" "Should pad VMID 12 with leading zeros"
}

test_vmid_to_mac_long() {
    local result
    result="$(__vmid_to_mac_prefix__ --vmid "987654")"
    assert_equals "BC:98:76:54" "$result" "Should handle longer VMID 987654"
}

################################################################################
# RUN TEST SUITE
################################################################################

test_framework_init

run_test_suite "Conversion Functions" \
    test_ip_to_int_localhost \
    test_ip_to_int_private \
    test_ip_to_int_class_a \
    test_int_to_ip_localhost \
    test_int_to_ip_private \
    test_int_to_ip_class_a \
    test_vmid_to_mac_basic \
    test_vmid_to_mac_padding \
    test_vmid_to_mac_long

exit $?

###############################################################################
# Script notes:
###############################################################################
# Last checked: YYYY-MM-DD
#
# Changes:
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

