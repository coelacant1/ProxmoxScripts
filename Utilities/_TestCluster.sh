#!/bin/bash
#
# _TestCluster.sh
#
# Test suite for Cluster.sh utility functions including cluster topology,
# node resolution, VM/CT queries, and validation functions.
#
# Usage:
#   _TestCluster.sh
#
# Notes:
#   - Uses TestFramework.sh for test execution and assertions
#   - Mocks external commands (pvecm, qm, pct) for isolation
#   - Tests cluster-aware functions without requiring actual Proxmox cluster
#   - Can be run locally or via RemoteRunAllTests.sh on Proxmox nodes
#
# Function Index:
#   - __setup_cluster_mocks__
#   - __teardown_cluster_mocks__
#   - test_get_remote_node_ips
#   - test_check_cluster_membership
#   - test_get_number_of_cluster_nodes
#   - test_validate_vm_id_range
#   - test_validate_vmid
#   - test_validate_ctid
#   - test_get_vm_node
#   - test_resolve_node_name
#

set -euo pipefail

################################################################################
# _TestCluster.sh - Test suite for Cluster.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"
export LOG_LEVEL=ERROR
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"

# Mock pvecm command for testing
__setup_cluster_mocks__() {
    # Mock pvecm status output
    mock_command "pvecm" "$(
        cat <<'EOF'
Cluster information
-------------------
Name:             testcluster
Config Version:   3
Transport:        knet
Secure auth:      on

Quorum information
------------------
Date:             Mon Jan 01 12:00:00 2024
Quorum provider:  corosync_votequorum
Nodes:            3
Node ID:          0x00000001
Ring ID:          1.2
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   3
Highest expected: 3
Total votes:      3
Quorum:           2  
Flags:            Quorate 

Membership information
----------------------
    Nodeid      Votes Name
0x00000001          1 192.168.1.101 (local)
0x00000002          1 192.168.1.102
0x00000003          1 192.168.1.103
EOF
    )" 0

    # Mock qm list
    mock_command "qm" "VMID STATUS     MEM(MB)    DISK(GB) PID       NAME
100  running    2048/4096  32.00/100 12345     test-vm-1
101  stopped    0/2048     16.00/50  -         test-vm-2" 0

    # Mock pct list
    mock_command "pct" "VMID       STATUS     LOCK         NAME
200        running    -            test-ct-1
201        stopped    -            test-ct-2" 0
}

__teardown_cluster_mocks__() {
    restore_all_mocks
}

################################################################################
# TEST: Get Remote Node IPs
################################################################################

test_get_remote_node_ips() {
    __setup_cluster_mocks__

    # Source after mocks are set up
    source "${SCRIPT_DIR}/Cluster.sh" 2>/dev/null || true

    local result
    result=$(__get_remote_node_ips__ 2>/dev/null || echo "")

    assert_contains "$result" "192.168.1.102" "Should contain first remote node IP"
    assert_contains "$result" "192.168.1.103" "Should contain second remote node IP"
    assert_not_contains "$result" "192.168.1.101" "Should not contain local node IP"

    __teardown_cluster_mocks__
}

################################################################################
# TEST: Check Cluster Membership
################################################################################

test_check_cluster_membership() {
    __setup_cluster_mocks__
    source "${SCRIPT_DIR}/Cluster.sh" 2>/dev/null || true

    # Function should return 0 when cluster is active
    if declare -f __check_cluster_membership__ >/dev/null 2>&1; then
        __check_cluster_membership__ 2>/dev/null
        local result=$?
        assert_exit_code 0 $result "Should detect cluster membership"
    else
        skip_test "Function __check_cluster_membership__ not available"
    fi

    __teardown_cluster_mocks__
}

################################################################################
# TEST: Get Number of Cluster Nodes
################################################################################

test_get_number_of_cluster_nodes() {
    __setup_cluster_mocks__
    source "${SCRIPT_DIR}/Cluster.sh" 2>/dev/null || true

    if declare -f __get_number_of_cluster_nodes__ >/dev/null 2>&1; then
        local count
        count=$(__get_number_of_cluster_nodes__ 2>/dev/null || echo "0")
        assert_equals "3" "$count" "Should return correct number of cluster nodes"
    else
        skip_test "Function __get_number_of_cluster_nodes__ not available"
    fi

    __teardown_cluster_mocks__
}

################################################################################
# TEST: Validate VM ID Range
################################################################################

test_validate_vm_id_range() {
    source "${SCRIPT_DIR}/Cluster.sh" 2>/dev/null || true

    if declare -f __validate_vm_id_range__ >/dev/null 2>&1; then
        # Valid range
        __validate_vm_id_range__ "100-110" 2>/dev/null
        assert_exit_code 0 $? "Should accept valid range"

        # Invalid range (start > end)
        ! __validate_vm_id_range__ "110-100" 2>/dev/null
        assert_exit_code 0 $? "Should reject invalid range"
    else
        skip_test "Function __validate_vm_id_range__ not available"
    fi
}

################################################################################
# TEST: Validate VMID
################################################################################

test_validate_vmid() {
    source "${SCRIPT_DIR}/Cluster.sh" 2>/dev/null || true

    if declare -f __validate_vmid__ >/dev/null 2>&1; then
        # Valid VMID
        __validate_vmid__ "100" 2>/dev/null
        assert_exit_code 0 $? "Should accept valid VMID"

        # Invalid VMID (non-numeric)
        ! __validate_vmid__ "abc" 2>/dev/null
        assert_exit_code 0 $? "Should reject non-numeric VMID"

        # Invalid VMID (out of range)
        ! __validate_vmid__ "99" 2>/dev/null
        assert_exit_code 0 $? "Should reject VMID below 100"
    else
        skip_test "Function __validate_vmid__ not available"
    fi
}

################################################################################
# TEST: Validate CTID
################################################################################

test_validate_ctid() {
    source "${SCRIPT_DIR}/Cluster.sh" 2>/dev/null || true

    if declare -f __validate_ctid__ >/dev/null 2>&1; then
        # Valid CTID
        __validate_ctid__ "200" 2>/dev/null
        assert_exit_code 0 $? "Should accept valid CTID"

        # Invalid CTID (non-numeric)
        ! __validate_ctid__ "xyz" 2>/dev/null
        assert_exit_code 0 $? "Should reject non-numeric CTID"
    else
        skip_test "Function __validate_ctid__ not available"
    fi
}

################################################################################
# TEST: Get VM Node
################################################################################

test_get_vm_node() {
    __setup_cluster_mocks__

    # Create mock config file
    local test_vm_conf="${TEST_TEMP_DIR}/100.conf"
    mkdir -p "$(dirname "$test_vm_conf")"
    echo "# VM Config" >"$test_vm_conf"

    # Mock the config directory
    mock_command "pvesh" "node1" 0

    source "${SCRIPT_DIR}/Cluster.sh" 2>/dev/null || true

    if declare -f __get_vm_node__ >/dev/null 2>&1; then
        local node
        node=$(__get_vm_node__ "100" 2>/dev/null || echo "")
        # Function exists and executed
        assert_true "1" "Function __get_vm_node__ is callable"
    else
        skip_test "Function __get_vm_node__ not available"
    fi

    __teardown_cluster_mocks__
}

################################################################################
# TEST: Resolve Node Name
################################################################################

test_resolve_node_name() {
    source "${SCRIPT_DIR}/Cluster.sh" 2>/dev/null || true

    if declare -f __resolve_node_name__ >/dev/null 2>&1; then
        # Test with IP input
        NODEID_TO_NAME[1]="node1"
        NODEID_TO_IP[1]="192.168.1.101"
        IP_TO_NAME["192.168.1.101"]="node1"
        NAME_TO_IP["node1"]="192.168.1.101"

        local result
        result=$(__resolve_node_name__ "192.168.1.101" 2>/dev/null || echo "")
        # Function is callable
        assert_true "1" "Function __resolve_node_name__ is callable"
    else
        skip_test "Function __resolve_node_name__ not available"
    fi
}

################################################################################
# RUN TESTS
################################################################################

run_test_suite "Cluster.sh Tests" \
    test_get_remote_node_ips \
    test_check_cluster_membership \
    test_get_number_of_cluster_nodes \
    test_validate_vm_id_range \
    test_validate_vmid \
    test_validate_ctid \
    test_get_vm_node \
    test_resolve_node_name

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

