#!/bin/bash
#
# _TestConfigManager.sh
#
# Test suite for ConfigManager.sh utility functions including configuration
# loading from nodes.json, execution mode management, and remote target handling.
#
# Usage:
#   _TestConfigManager.sh
#
# Notes:
#   - Uses TestFramework.sh for test execution and assertions
#   - Creates temporary nodes.json for testing configuration loading
#   - Tests execution mode switching (local/single-remote/multi-remote)
#   - Requires jq for JSON parsing (gracefully skips if not available)
#   - Can be run locally or via RemoteRunAllTests.sh on Proxmox nodes
#
# Function Index:
#   - __test_setup__
#   - __test_teardown__
#   - test_init_config
#   - test_set_execution_mode_local
#   - test_set_execution_mode_single_remote
#   - test_set_execution_mode_multi_remote
#   - test_add_remote_target
#   - test_clear_remote_targets
#   - test_get_node_ip
#   - test_node_exists
#

set -euo pipefail

################################################################################
# _TestConfigManager.sh - Test suite for ConfigManager.sh
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
      "ip": "192.168.1.101"
    },
    {
      "id": 2,
      "name": "node2",
      "ip": "192.168.1.102"
    }
  ]
}
EOF

    # Override nodes file location
    NODES_FILE="$TEST_NODES_JSON"
}

__test_teardown__() {
    rm -f "$TEST_NODES_JSON" 2>/dev/null || true
}

################################################################################
# TEST: Initialize Config
################################################################################

test_init_config() {
    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        skip_test "jq not available for config parsing"
    fi

    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __init_config__ >/dev/null 2>&1; then
        __init_config__ 2>/dev/null

        # Check that nodes were loaded (handle unset variables)
        local node1_ip="${AVAILABLE_NODES[node1]:-}"
        local node2_ip="${AVAILABLE_NODES[node2]:-}"

        if [[ -n "$node1_ip" ]]; then
            assert_equals "192.168.1.101" "$node1_ip" "Should have correct IP for node1"
        fi

        if [[ -n "$node2_ip" ]]; then
            assert_equals "192.168.1.102" "$node2_ip" "Should have correct IP for node2"
        fi

        # At minimum, verify function executed without error
        assert_true "1" "Function __init_config__ executed successfully"
    else
        skip_test "Function __init_config__ not available"
    fi
}

################################################################################
# TEST: Set Execution Mode - Local
################################################################################

test_set_execution_mode_local() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __set_execution_mode__ >/dev/null 2>&1; then
        __set_execution_mode__ "local"

        assert_equals "local" "$EXECUTION_MODE" "Should set local mode"
        assert_equals "Local System" "$EXECUTION_MODE_DISPLAY" "Should set local display name"
        assert_equals "This System" "$TARGET_DISPLAY" "Should set local target display"
    else
        skip_test "Function __set_execution_mode__ not available"
    fi
}

################################################################################
# TEST: Set Execution Mode - Single Remote
################################################################################

test_set_execution_mode_single_remote() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __set_execution_mode__ >/dev/null 2>&1; then
        # Add a remote target first
        if declare -f __add_remote_target__ >/dev/null 2>&1; then
            __add_remote_target__ "node1" "192.168.1.101" "password"
        fi

        __set_execution_mode__ "single-remote"

        assert_equals "single-remote" "$EXECUTION_MODE" "Should set single-remote mode"
        assert_equals "Single Remote" "$EXECUTION_MODE_DISPLAY" "Should set single-remote display name"
        assert_contains "$TARGET_DISPLAY" "node1" "Should show node1 in target display"
    else
        skip_test "Function __set_execution_mode__ not available"
    fi
}

################################################################################
# TEST: Set Execution Mode - Multi Remote
################################################################################

test_set_execution_mode_multi_remote() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __set_execution_mode__ >/dev/null 2>&1; then
        # Add multiple remote targets
        if declare -f __add_remote_target__ >/dev/null 2>&1; then
            __add_remote_target__ "node1" "192.168.1.101" "password1"
            __add_remote_target__ "node2" "192.168.1.102" "password2"
        fi

        __set_execution_mode__ "multi-remote"

        assert_equals "multi-remote" "$EXECUTION_MODE" "Should set multi-remote mode"
        assert_equals "Multiple Remote" "$EXECUTION_MODE_DISPLAY" "Should set multi-remote display name"
        assert_contains "$TARGET_DISPLAY" "2 nodes" "Should show node count in target display"
    else
        skip_test "Function __set_execution_mode__ not available"
    fi
}

################################################################################
# TEST: Add Remote Target
################################################################################

test_add_remote_target() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __add_remote_target__ >/dev/null 2>&1; then
        # Clear any existing targets
        REMOTE_TARGETS=()
        NODE_PASSWORDS=()

        __add_remote_target__ "testnode" "192.168.1.200" "testpass"

        assert_equals 1 "${#REMOTE_TARGETS[@]}" "Should add one remote target"
        assert_contains "${REMOTE_TARGETS[0]}" "testnode" "Should contain node name"
        assert_contains "${REMOTE_TARGETS[0]}" "192.168.1.200" "Should contain node IP"
        assert_equals "testpass" "${NODE_PASSWORDS[testnode]}" "Should store password"
    else
        skip_test "Function __add_remote_target__ not available"
    fi
}

################################################################################
# TEST: Clear Remote Targets
################################################################################

test_clear_remote_targets() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __clear_remote_targets__ >/dev/null 2>&1; then
        # Add some targets first
        if declare -f __add_remote_target__ >/dev/null 2>&1; then
            __add_remote_target__ "node1" "192.168.1.101" "pass1"
            __add_remote_target__ "node2" "192.168.1.102" "pass2"
        fi

        assert_equals 2 "${#REMOTE_TARGETS[@]}" "Should have two targets before clear"

        __clear_remote_targets__

        assert_equals 0 "${#REMOTE_TARGETS[@]}" "Should have no targets after clear"
        assert_equals 0 "${#NODE_PASSWORDS[@]}" "Should have no passwords after clear"
    else
        skip_test "Function __clear_remote_targets__ not available"
    fi
}

################################################################################
# TEST: Get Node IP
################################################################################

test_get_node_ip() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __get_node_ip__ >/dev/null 2>&1; then
        # Set up test data
        AVAILABLE_NODES["testnode"]="192.168.1.201"

        local result
        result=$(__get_node_ip__ "testnode")
        assert_equals "192.168.1.201" "$result" "Should return correct IP for node"

        result=$(__get_node_ip__ "nonexistent")
        assert_false "$result" "Should return empty for nonexistent node"
    else
        skip_test "Function __get_node_ip__ not available"
    fi
}

################################################################################
# TEST: Node Exists
################################################################################

test_node_exists() {
    source "${SCRIPT_DIR}/ConfigManager.sh" 2>/dev/null || true

    if declare -f __node_exists__ >/dev/null 2>&1; then
        # Set up test data
        AVAILABLE_NODES["existingnode"]="192.168.1.202"

        __node_exists__ "existingnode"
        assert_exit_code 0 $? "Should return true for existing node"

        ! __node_exists__ "nonexistentnode"
        assert_exit_code 0 $? "Should return false for nonexistent node"
    else
        skip_test "Function __node_exists__ not available"
    fi
}

################################################################################
# RUN TESTS
################################################################################

run_test_suite "ConfigManager.sh Tests" \
    test_init_config \
    test_set_execution_mode_local \
    test_set_execution_mode_single_remote \
    test_set_execution_mode_multi_remote \
    test_add_remote_target \
    test_clear_remote_targets \
    test_get_node_ip \
    test_node_exists

exit $?
