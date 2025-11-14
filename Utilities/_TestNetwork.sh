#!/bin/bash
#
# Function Index:
#   - test_validate_ipv4_valid
#   - test_validate_ipv4_invalid
#   - test_validate_ipv6_valid
#   - test_validate_cidr_valid
#   - test_validate_cidr_invalid
#   - test_calculate_network_address
#   - test_calculate_broadcast_address
#   - test_cidr_to_netmask
#   - test_netmask_to_cidr
#   - test_ip_in_subnet
#   - test_validate_mac_address
#   - test_normalize_mac_address
#   - test_generate_random_mac
#   - test_get_interface_info
#   - test_list_bridges
#   - test_add_network_interface
#   - test_remove_network_interface
#   - test_validate_vlan_id
#   - test_validate_hostname
#   - test_validate_domain
#   - test_validate_port
#   - test_ping_host
#

set -euo pipefail

################################################################################
# Test Suite for Network.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/TestFramework.sh"
source "${SCRIPT_DIR}/Network.sh"

################################################################################
# TEST: IP ADDRESS VALIDATION
################################################################################

test_validate_ipv4_valid() {
    validate_ipv4 "192.168.1.1"
    assert_exit_code 0 $? "Should validate correct IPv4"

    validate_ipv4 "10.0.0.1"
    assert_exit_code 0 $? "Should validate 10.x.x.x"

    validate_ipv4 "172.16.0.1"
    assert_exit_code 0 $? "Should validate 172.16.x.x"
}

test_validate_ipv4_invalid() {
    local result

    validate_ipv4 "256.1.1.1" && result=0 || result=$?
    assert_not_equals 0 $result "Should reject 256"

    validate_ipv4 "192.168.1" && result=0 || result=$?
    assert_not_equals 0 $result "Should reject incomplete IP"

    validate_ipv4 "abc.def.ghi.jkl" && result=0 || result=$?
    assert_not_equals 0 $result "Should reject non-numeric"
}

test_validate_ipv6_valid() {
    validate_ipv6 "2001:db8::1"
    assert_exit_code 0 $? "Should validate compressed IPv6"

    validate_ipv6 "fe80::1"
    assert_exit_code 0 $? "Should validate link-local"
}

test_validate_cidr_valid() {
    validate_cidr "192.168.1.0/24"
    assert_exit_code 0 $? "Should validate /24 CIDR"

    validate_cidr "10.0.0.0/8"
    assert_exit_code 0 $? "Should validate /8 CIDR"
}

test_validate_cidr_invalid() {
    local result

    validate_cidr "192.168.1.0/33" && result=0 || result=$?
    assert_not_equals 0 $result "Should reject /33 (too large)"

    validate_cidr "192.168.1.0" && result=0 || result=$?
    assert_not_equals 0 $result "Should reject missing mask"
}

################################################################################
# TEST: IP ADDRESS CALCULATIONS
################################################################################

test_calculate_network_address() {
    local result

    result=$(calculate_network_address "192.168.1.100" "255.255.255.0")
    assert_equals "192.168.1.0" "$result" "Should calculate network address"

    result=$(calculate_network_address "10.5.10.50" "255.255.0.0")
    assert_equals "10.5.0.0" "$result" "Should calculate with /16"
}

test_calculate_broadcast_address() {
    local result

    result=$(calculate_broadcast_address "192.168.1.0" "255.255.255.0")
    assert_equals "192.168.1.255" "$result" "Should calculate broadcast"
}

test_cidr_to_netmask() {
    local result

    result=$(cidr_to_netmask 24)
    assert_equals "255.255.255.0" "$result" "Should convert /24"

    result=$(cidr_to_netmask 16)
    assert_equals "255.255.0.0" "$result" "Should convert /16"

    result=$(cidr_to_netmask 8)
    assert_equals "255.0.0.0" "$result" "Should convert /8"
}

test_netmask_to_cidr() {
    local result

    result=$(netmask_to_cidr "255.255.255.0")
    assert_equals "24" "$result" "Should convert to /24"

    result=$(netmask_to_cidr "255.255.0.0")
    assert_equals "16" "$result" "Should convert to /16"
}

test_ip_in_subnet() {
    is_ip_in_subnet "192.168.1.100" "192.168.1.0/24"
    assert_exit_code 0 $? "Should be in subnet"

    local result
    is_ip_in_subnet "192.168.2.100" "192.168.1.0/24" && result=0 || result=$?
    assert_not_equals 0 $result "Should not be in subnet"
}

################################################################################
# TEST: MAC ADDRESS OPERATIONS
################################################################################

test_validate_mac_address() {
    validate_mac_address "00:11:22:33:44:55"
    assert_exit_code 0 $? "Should validate colon format"

    validate_mac_address "00-11-22-33-44-55"
    assert_exit_code 0 $? "Should validate dash format"

    validate_mac_address "001122334455"
    assert_exit_code 0 $? "Should validate compact format"
}

test_normalize_mac_address() {
    local result

    result=$(normalize_mac_address "00:11:22:33:44:55")
    assert_equals "00:11:22:33:44:55" "$result" "Should keep colon format"

    result=$(normalize_mac_address "00-11-22-33-44-55")
    assert_equals "00:11:22:33:44:55" "$result" "Should convert dashes"

    result=$(normalize_mac_address "001122334455")
    assert_equals "00:11:22:33:44:55" "$result" "Should format compact"
}

test_generate_random_mac() {
    local mac1 mac2

    mac1=$(generate_random_mac)
    assert_matches "$mac1" "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$" "Should generate valid MAC"

    mac2=$(generate_random_mac)
    assert_not_equals "$mac1" "$mac2" "Should generate unique MACs"
}

################################################################################
# TEST: NETWORK INTERFACE QUERIES
################################################################################

test_get_interface_info() {
    # Mock pvesh command
    mock_command "pvesh" "net0: virtio=00:11:22:33:44:55,bridge=vmbr0,ip=192.168.1.100/24" 0

    local result
    result=$(get_vm_network_config 100)
    assert_contains "$result" "net0" "Should return network config"
}

test_list_bridges() {
    # Mock pvesh command
    mock_command "pvesh" "vmbr0
vmbr1" 0

    local result
    result=$(list_bridges)
    assert_contains "$result" "vmbr0" "Should list vmbr0"
    assert_contains "$result" "vmbr1" "Should list vmbr1"
}

################################################################################
# TEST: NETWORK CONFIGURATION
################################################################################

test_add_network_interface() {
    # Mock pvesh command
    mock_command "pvesh" "success" 0

    add_vm_network_interface 100 "net1" "virtio" "vmbr0" "" "" "false"
    assert_exit_code 0 $? "Should add interface"
}

test_remove_network_interface() {
    # Mock pvesh command
    mock_command "pvesh" "success" 0

    remove_vm_network_interface 100 "net1"
    assert_exit_code 0 $? "Should remove interface"
}

################################################################################
# TEST: VLAN OPERATIONS
################################################################################

test_validate_vlan_id() {
    validate_vlan_id 100
    assert_exit_code 0 $? "Should validate VLAN 100"

    validate_vlan_id 1
    assert_exit_code 0 $? "Should validate VLAN 1"

    validate_vlan_id 4094
    assert_exit_code 0 $? "Should validate VLAN 4094"

    local result
    validate_vlan_id 0 && result=0 || result=$?
    assert_not_equals 0 $result "Should reject VLAN 0"

    validate_vlan_id 4095 && result=0 || result=$?
    assert_not_equals 0 $result "Should reject VLAN 4095"
}

################################################################################
# TEST: DNS OPERATIONS
################################################################################

test_validate_hostname() {
    validate_hostname "server01"
    assert_exit_code 0 $? "Should validate simple hostname"

    validate_hostname "web-server-01"
    assert_exit_code 0 $? "Should validate with dashes"

    validate_hostname "app.example.com"
    assert_exit_code 0 $? "Should validate FQDN"
}

test_validate_domain() {
    validate_domain "example.com"
    assert_exit_code 0 $? "Should validate domain"

    validate_domain "sub.example.com"
    assert_exit_code 0 $? "Should validate subdomain"
}

################################################################################
# TEST: PORT VALIDATION
################################################################################

test_validate_port() {
    validate_port 80
    assert_exit_code 0 $? "Should validate port 80"

    validate_port 443
    assert_exit_code 0 $? "Should validate port 443"

    validate_port 65535
    assert_exit_code 0 $? "Should validate max port"

    local result
    validate_port 0 && result=0 || result=$?
    assert_not_equals 0 $result "Should reject port 0"

    validate_port 65536 && result=0 || result=$?
    assert_not_equals 0 $result "Should reject port > 65535"
}

################################################################################
# TEST: NETWORK TESTING
################################################################################

test_ping_host() {
    # Mock ping command
    mock_command "ping" "PING 192.168.1.1 (192.168.1.1) 56(84) bytes of data.
64 bytes from 192.168.1.1: icmp_seq=1 ttl=64 time=0.123 ms" 0

    ping_host "192.168.1.1" 1
    assert_exit_code 0 $? "Should ping successfully"
}

################################################################################
# RUN ALL TESTS
################################################################################

run_test_suite "Network Tests" \
    test_validate_ipv4_valid \
    test_validate_ipv4_invalid \
    test_validate_ipv6_valid \
    test_validate_cidr_valid \
    test_validate_cidr_invalid \
    test_calculate_network_address \
    test_calculate_broadcast_address \
    test_cidr_to_netmask \
    test_netmask_to_cidr \
    test_ip_in_subnet \
    test_validate_mac_address \
    test_normalize_mac_address \
    test_generate_random_mac \
    test_get_interface_info \
    test_list_bridges \
    test_add_network_interface \
    test_remove_network_interface \
    test_validate_vlan_id \
    test_validate_hostname \
    test_validate_domain \
    test_validate_port \
    test_ping_host

exit $?
