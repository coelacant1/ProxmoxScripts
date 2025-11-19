#!/bin/bash
#
# _TestOperations.sh
#
# Test suite for Operations.sh utility functions including VM/CT operations
# such as start, stop, status checks, existence checks, and configuration queries.
#
# Usage:
#   _TestOperations.sh
#
# Notes:
#   - Uses TestFramework.sh for test execution and assertions
#   - Mocks external commands (qm, pct, pvesh) for isolation
#   - Tests cluster-aware operations without requiring actual VMs/CTs
#   - Can be run locally or via RemoteRunAllTests.sh on Proxmox nodes
#
# Function Index:
#   - __setup_operations_mocks__
#   - __teardown_operations_mocks__
#   - test_vm_exists
#   - test_vm_get_status
#   - test_vm_is_running
#   - test_vm_start
#   - test_vm_stop
#   - test_ct_exists
#   - test_ct_get_status
#   - test_ct_is_running
#   - test_ct_start
#   - test_ct_stop
#   - test_vm_get_config
#   - test_ct_get_config
#

set -euo pipefail

################################################################################
# _TestOperations.sh - Test suite for Operations.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"
export LOG_LEVEL=ERROR
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"

# Mock setup for operations
__setup_operations_mocks__() {
    # Mock qm commands
    mock_command "qm" "status: running" 0

    # Mock pct commands
    mock_command "pct" "status: running" 0

    # Mock pvesh for API calls
    mock_command "pvesh" '{"data":{"status":"running","vmid":100}}' 0
}

__teardown_operations_mocks__() {
    restore_all_mocks
}

################################################################################
# TEST: VM Exists
################################################################################

test_vm_exists() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __vm_exists__ >/dev/null 2>&1; then
        # Mock __get_vm_node__ to return a node
        __get_vm_node__() {
            echo "node1"
            return 0
        }

        __vm_exists__ "100" 2>/dev/null
        assert_exit_code 0 $? "Should confirm VM exists"

        # Mock __get_vm_node__ to return empty
        __get_vm_node__() {
            echo ""
            return 1
        }

        ! __vm_exists__ "999" 2>/dev/null
        assert_exit_code 0 $? "Should return false for nonexistent VM"
    else
        skip_test "Function __vm_exists__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: VM Get Status
################################################################################

test_vm_get_status() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __vm_get_status__ >/dev/null 2>&1; then
        # Mock the underlying command
        qm() {
            echo "status: running"
            return 0
        }
        export -f qm

        local status
        status=$(__vm_get_status__ "100" 2>/dev/null || echo "")
        assert_contains "$status" "running" "Should return VM status"
    else
        skip_test "Function __vm_get_status__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: VM Is Running
################################################################################

test_vm_is_running() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __vm_is_running__ >/dev/null 2>&1; then
        # Mock status function
        __vm_get_status__() {
            echo "running"
            return 0
        }

        __vm_is_running__ "100" 2>/dev/null
        assert_exit_code 0 $? "Should confirm VM is running"

        # Mock stopped status
        __vm_get_status__() {
            echo "stopped"
            return 0
        }

        ! __vm_is_running__ "100" 2>/dev/null
        assert_exit_code 0 $? "Should return false for stopped VM"
    else
        skip_test "Function __vm_is_running__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: VM Start
################################################################################

test_vm_start() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __vm_start__ >/dev/null 2>&1; then
        # Mock qm start to succeed
        qm() { return 0; }
        __get_vm_node__() { echo "node1"; }
        export -f qm __get_vm_node__

        __vm_start__ "100" 2>/dev/null
        assert_exit_code 0 $? "Should successfully start VM"
    else
        skip_test "Function __vm_start__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: VM Stop
################################################################################

test_vm_stop() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __vm_stop__ >/dev/null 2>&1; then
        # Mock qm stop to succeed
        qm() { return 0; }
        __get_vm_node__() { echo "node1"; }
        export -f qm __get_vm_node__

        __vm_stop__ "100" 2>/dev/null
        assert_exit_code 0 $? "Should successfully stop VM"
    else
        skip_test "Function __vm_stop__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: CT Exists
################################################################################

test_ct_exists() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __ct_exists__ >/dev/null 2>&1; then
        # Mock __get_vm_node__ to return a node
        __get_vm_node__() {
            echo "node1"
            return 0
        }

        __ct_exists__ "200" 2>/dev/null
        assert_exit_code 0 $? "Should confirm CT exists"
    else
        skip_test "Function __ct_exists__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: CT Get Status
################################################################################

test_ct_get_status() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __ct_get_status__ >/dev/null 2>&1; then
        # Mock pct status
        pct() {
            echo "status: running"
            return 0
        }
        export -f pct

        local status
        status=$(__ct_get_status__ "200" 2>/dev/null || echo "")
        assert_contains "$status" "running" "Should return CT status"
    else
        skip_test "Function __ct_get_status__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: CT Is Running
################################################################################

test_ct_is_running() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __ct_is_running__ >/dev/null 2>&1; then
        # Mock status function
        __ct_get_status__() {
            echo "running"
            return 0
        }

        __ct_is_running__ "200" 2>/dev/null
        assert_exit_code 0 $? "Should confirm CT is running"
    else
        skip_test "Function __ct_is_running__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: CT Start
################################################################################

test_ct_start() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __ct_start__ >/dev/null 2>&1; then
        # Mock pct start to succeed
        pct() { return 0; }
        __get_vm_node__() { echo "node1"; }
        export -f pct __get_vm_node__

        __ct_start__ "200" 2>/dev/null
        assert_exit_code 0 $? "Should successfully start CT"
    else
        skip_test "Function __ct_start__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: CT Stop
################################################################################

test_ct_stop() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __ct_stop__ >/dev/null 2>&1; then
        # Mock pct stop to succeed
        pct() { return 0; }
        __get_vm_node__() { echo "node1"; }
        export -f pct __get_vm_node__

        __ct_stop__ "200" 2>/dev/null
        assert_exit_code 0 $? "Should successfully stop CT"
    else
        skip_test "Function __ct_stop__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: VM Get Config
################################################################################

test_vm_get_config() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __vm_get_config__ >/dev/null 2>&1; then
        # Mock qm config
        qm() {
            echo "memory: 2048\ncores: 2"
            return 0
        }
        __get_vm_node__() { echo "node1"; }
        export -f qm __get_vm_node__

        local config
        config=$(__vm_get_config__ "100" 2>/dev/null || echo "")
        assert_contains "$config" "memory" "Should return VM config"
    else
        skip_test "Function __vm_get_config__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# TEST: CT Get Config
################################################################################

test_ct_get_config() {
    __setup_operations_mocks__
    source "${SCRIPT_DIR}/Operations.sh" 2>/dev/null || true

    if declare -f __ct_get_config__ >/dev/null 2>&1; then
        # Mock pct config
        pct() {
            echo "memory: 1024\ncores: 1"
            return 0
        }
        __get_vm_node__() { echo "node1"; }
        export -f pct __get_vm_node__

        local config
        config=$(__ct_get_config__ "200" 2>/dev/null || echo "")
        assert_contains "$config" "memory" "Should return CT config"
    else
        skip_test "Function __ct_get_config__ not available"
    fi

    __teardown_operations_mocks__
}

################################################################################
# RUN TESTS
################################################################################

run_test_suite "Operations.sh Tests" \
    test_vm_exists \
    test_vm_get_status \
    test_vm_is_running \
    test_vm_start \
    test_vm_stop \
    test_ct_exists \
    test_ct_get_status \
    test_ct_is_running \
    test_ct_start \
    test_ct_stop \
    test_vm_get_config \
    test_ct_get_config

exit $?
