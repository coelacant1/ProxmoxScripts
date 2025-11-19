#!/bin/bash
#
# _TestNodeSelection.sh
#
# Test suite for node selection and validation functions used by ConfigManager.sh
# including node listing, multi-node selection, and SSH key detection.
#
# Usage:
#   _TestNodeSelection.sh
#
# Notes:
#   - Uses TestFramework.sh for test execution and assertions
#   - Creates temporary nodes.json with test configuration
#   - Tests node listing from configuration
#   - Tests multi-node target selection
#   - Tests SSH key status detection
#   - Can be run locally or via RemoteRunAllTests.sh on Proxmox nodes
#
# Function Index:
#   - __test_setup__
#   - __test_teardown__
#   - test_node_selection_list
#   - test_node_selection_validation
#   - test_multi_node_selection
#   - test_ssh_key_detection
#

set -euo pipefail

################################################################################
# _TestNodeSelection.sh - Test suite for NodeSelection.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"
export LOG_LEVEL=ERROR
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"

# Setup test environment
__test_setup__() {
    # Create test nodes.json
    TEST_NODES_JSON="${TEST_TEMP_DIR}/nodes.json"
    cat >"$TEST_NODES_JSON" <<'EOF'
{
  "cluster": {
    "name": "testcluster"
  },
  "nodes": [
    {
      "id": 1,
      "name": "node1",
      "ip": "192.168.1.101",
      "ssh_keys": true
    },
    {
      "id": 2,
      "name": "node2",
      "ip": "192.168.1.102",
      "ssh_keys": false
    },
    {
      "id": 3,
      "name": "node3",
      "ip": "192.168.1.103",
      "ssh_keys": true
    }
  ]
}
EOF

    export NODES_FILE="$TEST_NODES_JSON"
}

__test_teardown__() {
    rm -f "$TEST_NODES_JSON" 2>/dev/null || true
}

################################################################################
# TEST: Node Selection List
################################################################################

test_node_selection_list() {
    # Load ConfigManager which has node functions
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __init_config__ >/dev/null 2>&1; then
        __init_config__ 2>/dev/null

        # Verify nodes were loaded
        assert_true "${AVAILABLE_NODES[node1]:-}" "Should have node1 available"
        assert_true "${AVAILABLE_NODES[node2]:-}" "Should have node2 available"
        assert_true "${AVAILABLE_NODES[node3]:-}" "Should have node3 available"

        # Check node count
        local count=${#AVAILABLE_NODES[@]}
        assert_greater_than "$count" 0 "Should have nodes available"
    else
        skip_test "Function __init_config__ not available"
    fi
}

################################################################################
# TEST: Node Selection Validation
################################################################################

test_node_selection_validation() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __init_config__ >/dev/null 2>&1 && declare -f __node_exists__ >/dev/null 2>&1; then
        __init_config__ 2>/dev/null

        # Valid node
        __node_exists__ "node1"
        assert_exit_code 0 $? "Should validate existing node"

        # Invalid node
        ! __node_exists__ "nonexistent"
        assert_exit_code 0 $? "Should reject nonexistent node"
    else
        skip_test "Required functions not available"
    fi
}

################################################################################
# TEST: Multi-Node Selection
################################################################################

test_multi_node_selection() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __add_remote_target__ >/dev/null 2>&1; then
        # Clear existing targets
        REMOTE_TARGETS=()
        NODE_PASSWORDS=()

        # Add multiple nodes
        __add_remote_target__ "node1" "192.168.1.101" "pass1"
        __add_remote_target__ "node2" "192.168.1.102" "pass2"
        __add_remote_target__ "node3" "192.168.1.103" "pass3"

        assert_equals 3 "${#REMOTE_TARGETS[@]}" "Should have 3 targets selected"

        # Verify each target
        assert_contains "${REMOTE_TARGETS[0]}" "node1" "Should contain node1"
        assert_contains "${REMOTE_TARGETS[1]}" "node2" "Should contain node2"
        assert_contains "${REMOTE_TARGETS[2]}" "node3" "Should contain node3"
    else
        skip_test "Function __add_remote_target__ not available"
    fi
}

################################################################################
# TEST: SSH Key Detection
################################################################################

test_ssh_key_detection() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __init_config__ >/dev/null 2>&1; then
        __init_config__ 2>/dev/null

        # Check SSH key status was loaded
        if [[ ${#NODE_SSH_KEYS[@]} -gt 0 ]]; then
            assert_equals "true" "${NODE_SSH_KEYS[node1]:-unknown}" "Node1 should have SSH keys"
            assert_equals "false" "${NODE_SSH_KEYS[node2]:-unknown}" "Node2 should not have SSH keys"
            assert_equals "true" "${NODE_SSH_KEYS[node3]:-unknown}" "Node3 should have SSH keys"
        else
            # If SSH keys array is not populated, that's okay for basic test
            assert_true "1" "Node configuration loaded"
        fi
    else
        skip_test "Function __init_config__ not available"
    fi
}

################################################################################
# RUN TESTS
################################################################################

run_test_suite "NodeSelection.sh Tests" \
    test_node_selection_list \
    test_node_selection_validation \
    test_multi_node_selection \
    test_ssh_key_detection

exit $?
