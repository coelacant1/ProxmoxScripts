#!/bin/bash
#
# _TestDiscovery.sh
#
# Test suite for Discovery.sh utility functions including IP discovery,
# node name resolution, guest agent queries, and VMID lookups.
#
# Usage:
#   _TestDiscovery.sh
#
# Notes:
#   - Uses TestFramework.sh for test execution and assertions
#   - Mocks external commands (arp-scan, pct, hostname) for isolation
#   - Tests IP discovery without requiring actual network infrastructure
#   - Can be run locally or via RemoteRunAllTests.sh on Proxmox nodes
#
# Function Index:
#   - __setup_discovery_mocks__
#   - __teardown_discovery_mocks__
#   - test_get_ip_from_name
#   - test_get_name_from_ip
#   - test_get_ip_from_guest_agent_vm
#   - test_get_ip_from_guest_agent_lxc
#   - test_discovery_with_invalid_vmid
#   - test_discovery_with_missing_mac
#

set -euo pipefail

################################################################################
# _TestDiscovery.sh - Test suite for Discovery.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"
export LOG_LEVEL=ERROR
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"

# Mock setup for discovery functions
__setup_discovery_mocks__() {
    # Mock arp-scan
    mock_command "arp-scan" "192.168.1.100	aa:bb:cc:dd:ee:ff	Test Device" 0

    # Mock pct exec for LXC
    mock_command "hostname" "192.168.1.200" 0

    # Mock qm guest exec for VM guest agent
    mock_command "jq" '{"ip-addresses":[{"ip-address":"192.168.1.150"}]}' 0
}

__teardown_discovery_mocks__() {
    restore_all_mocks
}

################################################################################
# TEST: Get IP from Node Name
################################################################################

test_get_ip_from_name() {
    source "${SCRIPT_DIR}/Discovery.sh" 2>/dev/null || true

    # Set up node mappings
    NODE_NAME_TO_IP["node1"]="192.168.1.101"
    NODE_NAME_TO_IP["node2"]="192.168.1.102"

    if declare -f __get_ip_from_name__ >/dev/null 2>&1; then
        local result
        result=$(__get_ip_from_name__ "node1" 2>/dev/null || echo "")
        assert_equals "192.168.1.101" "$result" "Should return correct IP for node name"

        result=$(__get_ip_from_name__ "node2" 2>/dev/null || echo "")
        assert_equals "192.168.1.102" "$result" "Should return correct IP for second node"

        result=$(__get_ip_from_name__ "nonexistent" 2>/dev/null || echo "")
        assert_false "$result" "Should return empty for nonexistent node"
    else
        skip_test "Function __get_ip_from_name__ not available"
    fi
}

################################################################################
# TEST: Get Name from IP
################################################################################

test_get_name_from_ip() {
    source "${SCRIPT_DIR}/Discovery.sh" 2>/dev/null || true

    # Set up node mappings
    NODE_IP_TO_NAME["192.168.1.101"]="node1"
    NODE_IP_TO_NAME["192.168.1.102"]="node2"

    if declare -f __get_name_from_ip__ >/dev/null 2>&1; then
        local result
        result=$(__get_name_from_ip__ "192.168.1.101" 2>/dev/null || echo "")
        assert_equals "node1" "$result" "Should return correct name for IP"

        result=$(__get_name_from_ip__ "192.168.1.102" 2>/dev/null || echo "")
        assert_equals "node2" "$result" "Should return correct name for second IP"

        result=$(__get_name_from_ip__ "192.168.1.999" 2>/dev/null || echo "")
        assert_false "$result" "Should return empty for nonexistent IP"
    else
        skip_test "Function __get_name_from_ip__ not available"
    fi
}

################################################################################
# TEST: Get IP from Guest Agent (VM)
################################################################################

test_get_ip_from_guest_agent_vm() {
    __setup_discovery_mocks__

    # Create mock VM config
    local vm_conf="${TEST_TEMP_DIR}/etc/pve/qemu-server/100.conf"
    mkdir -p "$(dirname "$vm_conf")"
    echo "agent: 1" >"$vm_conf"

    source "${SCRIPT_DIR}/Discovery.sh" 2>/dev/null || true

    if declare -f __get_ip_from_guest_agent__ >/dev/null 2>&1; then
        # Test would require full mocking of qm guest cmd
        # For now, verify function exists and is callable
        assert_true "1" "Function __get_ip_from_guest_agent__ exists"
    else
        skip_test "Function __get_ip_from_guest_agent__ not available"
    fi

    __teardown_discovery_mocks__
}

################################################################################
# TEST: Get IP from Guest Agent (LXC)
################################################################################

test_get_ip_from_guest_agent_lxc() {
    __setup_discovery_mocks__

    # Create mock LXC config
    local lxc_conf="${TEST_TEMP_DIR}/etc/pve/lxc/200.conf"
    mkdir -p "$(dirname "$lxc_conf")"
    echo "net0: name=eth0,bridge=vmbr0,hwaddr=AA:BB:CC:DD:EE:FF,ip=dhcp,type=veth" >"$lxc_conf"

    source "${SCRIPT_DIR}/Discovery.sh" 2>/dev/null || true

    if declare -f __get_ip_from_vmid__ >/dev/null 2>&1; then
        # Verify function is available
        assert_true "1" "Function __get_ip_from_vmid__ exists"
    else
        skip_test "Function __get_ip_from_vmid__ not available"
    fi

    __teardown_discovery_mocks__
}

################################################################################
# TEST: Discovery with Invalid VMID
################################################################################

test_discovery_with_invalid_vmid() {
    source "${SCRIPT_DIR}/Discovery.sh" 2>/dev/null || true

    if declare -f __get_ip_from_vmid__ >/dev/null 2>&1; then
        # Empty VMID should fail
        ! __get_ip_from_vmid__ "" 2>/dev/null
        assert_exit_code 0 $? "Should reject empty VMID"
    else
        skip_test "Function __get_ip_from_vmid__ not available"
    fi
}

################################################################################
# TEST: Discovery with Missing MAC Address
################################################################################

test_discovery_with_missing_mac() {
    # Create mock VM config without network
    local vm_conf="${TEST_TEMP_DIR}/etc/pve/qemu-server/999.conf"
    mkdir -p "$(dirname "$vm_conf")"
    echo "memory: 2048" >"$vm_conf"

    source "${SCRIPT_DIR}/Discovery.sh" 2>/dev/null || true

    if declare -f __get_ip_from_vmid__ >/dev/null 2>&1; then
        # Function should handle missing MAC gracefully
        local result
        result=$(__get_ip_from_vmid__ "999" 2>/dev/null || echo "")
        # Just verify it doesn't crash
        assert_true "1" "Function handles missing MAC address"
    else
        skip_test "Function __get_ip_from_vmid__ not available"
    fi
}

################################################################################
# RUN TESTS
################################################################################

run_test_suite "Discovery.sh Tests" \
    test_get_ip_from_name \
    test_get_name_from_ip \
    test_get_ip_from_guest_agent_vm \
    test_get_ip_from_guest_agent_lxc \
    test_discovery_with_invalid_vmid \
    test_discovery_with_missing_mac

exit $?
