#!/bin/bash
#
# Function Index:
#   - test_validate_ip_valid
#   - test_validate_ip_invalid
#   - test_validate_cidr_valid
#   - test_validate_cidr_invalid
#   - test_validate_mac_valid
#   - test_validate_mac_invalid
#

set -euo pipefail

################################################################################
# _TestNetwork.sh - Test suite for Network.sh
################################################################################
#
# Test suite for Network.sh validation and network functions.
# Tests IP, CIDR, and MAC address validation.
#
# Usage: ./_TestNetwork.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

# Suppress verbose logging during tests
export LOG_LEVEL=ERROR

# Skip dependency checks during testing
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"
source "${SCRIPT_DIR}/Network.sh"

################################################################################
# TEST: IP ADDRESS VALIDATION
################################################################################

test_validate_ip_valid() {
    __net_validate_ip__ "192.168.1.1"
    assert_exit_code 0 $? "Should validate correct IPv4"

    __net_validate_ip__ "10.0.0.1"
    assert_exit_code 0 $? "Should validate 10.x.x.x"

    __net_validate_ip__ "172.16.0.1"
    assert_exit_code 0 $? "Should validate 172.16.x.x"

    __net_validate_ip__ "0.0.0.0"
    assert_exit_code 0 $? "Should validate 0.0.0.0"

    __net_validate_ip__ "255.255.255.255"
    assert_exit_code 0 $? "Should validate 255.255.255.255"
}

test_validate_ip_invalid() {
    local result

    __net_validate_ip__ "256.1.1.1" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject 256"

    __net_validate_ip__ "192.168.1" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject incomplete IP"

    __net_validate_ip__ "abc.def.ghi.jkl" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject non-numeric"

    __net_validate_ip__ "192.168.1.1.1" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject too many octets"
}

################################################################################
# TEST: CIDR VALIDATION
################################################################################

test_validate_cidr_valid() {
    __net_validate_cidr__ "192.168.1.0/24"
    assert_exit_code 0 $? "Should validate /24 CIDR"

    __net_validate_cidr__ "10.0.0.0/8"
    assert_exit_code 0 $? "Should validate /8 CIDR"

    __net_validate_cidr__ "172.16.0.0/16"
    assert_exit_code 0 $? "Should validate /16 CIDR"

    __net_validate_cidr__ "192.168.1.100/32"
    assert_exit_code 0 $? "Should validate /32 CIDR"

    __net_validate_cidr__ "0.0.0.0/0"
    assert_exit_code 0 $? "Should validate /0 CIDR"
}

test_validate_cidr_invalid() {
    local result

    __net_validate_cidr__ "192.168.1.0/33" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject /33 (too large)"

    __net_validate_cidr__ "192.168.1.0" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject missing mask"

    __net_validate_cidr__ "256.1.1.1/24" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject invalid IP"
}

################################################################################
# TEST: MAC ADDRESS VALIDATION
################################################################################

test_validate_mac_valid() {
    __net_validate_mac__ "00:11:22:33:44:55"
    assert_exit_code 0 $? "Should validate lowercase colon format"

    __net_validate_mac__ "AA:BB:CC:DD:EE:FF"
    assert_exit_code 0 $? "Should validate uppercase colon format"

    __net_validate_mac__ "aA:bB:cC:dD:eE:fF"
    assert_exit_code 0 $? "Should validate mixed case"

    __net_validate_mac__ "00:00:00:00:00:00"
    assert_exit_code 0 $? "Should validate all zeros"

    __net_validate_mac__ "FF:FF:FF:FF:FF:FF"
    assert_exit_code 0 $? "Should validate all Fs"
}

test_validate_mac_invalid() {
    local result

    __net_validate_mac__ "00:11:22:33:44" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject too few octets"

    __net_validate_mac__ "00:11:22:33:44:55:66" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject too many octets"

    __net_validate_mac__ "00-11-22-33-44-55" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject dash format"

    __net_validate_mac__ "001122334455" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject compact format"

    __net_validate_mac__ "GG:11:22:33:44:55" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should reject invalid hex"
}

################################################################################
# RUN TEST SUITES
################################################################################

test_framework_init

run_test_suite "Network - IP Validation" \
    test_validate_ip_valid \
    test_validate_ip_invalid

run_test_suite "Network - CIDR Validation" \
    test_validate_cidr_valid \
    test_validate_cidr_invalid

run_test_suite "Network - MAC Validation" \
    test_validate_mac_valid \
    test_validate_mac_invalid

test_framework_cleanup
