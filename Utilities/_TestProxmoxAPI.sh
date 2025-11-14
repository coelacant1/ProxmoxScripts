#!/bin/bash
#
# Function Index:
#   - __get_vm_node__
#   - qm
#   - pct
#   - test_vm_exists_valid
#   - test_vm_exists_invalid
#   - test_vm_get_status_running
#   - test_vm_is_running_true
#   - test_vm_start
#   - test_vm_stop
#   - test_vm_get_config_memory
#   - test_ct_exists_valid
#   - test_ct_exists_invalid
#   - test_ct_get_status_running
#   - test_ct_is_running_true
#   - test_ct_start
#   - test_ct_stop
#   - test_ct_get_config_memory
#

set -euo pipefail

################################################################################
# _TestOperations.sh - Test suite for Operations.sh
################################################################################
#
# Test suite for Operations.sh functions.
# Tests validation, error handling, and function behavior with mocked commands.
#
# Usage: ./_TestOperations.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/TestFramework.sh"

###############################################################################
# MOCK FUNCTIONS
###############################################################################

__get_vm_node__() {
    local vmid="$1"
    if (( vmid >= 100 && vmid <= 110 )); then
        echo "node1"
    elif (( vmid >= 111 && vmid <= 120 )); then
        echo "node2"
    else
        return 1
    fi
}

qm() {
    local action="$1"
    local vmid="$2"

    case "$action" in
        status)
            if (( vmid >= 100 && vmid <= 105 )); then
                echo "status: running"
            else
                echo "status: stopped"
            fi
            return 0
            ;;
        config)
            echo "memory: 2048"
            echo "cores: 4"
            return 0
            ;;
        start|stop|shutdown)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

pct() {
    local action="$1"
    local ctid="$2"

    case "$action" in
        config)
            if (( ctid >= 200 && ctid <= 210 )); then
                echo "memory: 1024"
                echo "hostname: ct${ctid}"
                return 0
            else
                return 1
            fi
            ;;
        status)
            if (( ctid >= 200 && ctid <= 205 )); then
                echo "status: running"
            else
                echo "status: stopped"
            fi
            return 0
            ;;
        start|stop|shutdown)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

export -f __get_vm_node__
export -f qm
export -f pct

source "${UTILITYPATH}/Operations.sh"

################################################################################
# TEST: VM EXISTS
################################################################################

test_vm_exists_valid() {
    __vm_exists__ 100 2>/dev/null
    assert_exit_code 0 $? "VM 100 should exist"
}

test_vm_exists_invalid() {
    local result
    __vm_exists__ 999 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "VM 999 should not exist"
}

################################################################################
# TEST: VM STATUS
################################################################################

test_vm_get_status_running() {
    local status
    status=$(__vm_get_status__ 100 2>/dev/null)
    assert_equals "running" "$status" "VM 100 should be running"
}

test_vm_is_running_true() {
    __vm_is_running__ 100 2>/dev/null
    assert_exit_code 0 $? "VM 100 should be running"
}

################################################################################
# TEST: VM OPERATIONS
################################################################################

test_vm_start() {
    __vm_start__ 106 2>/dev/null
    assert_exit_code 0 $? "Should start VM 106"
}

test_vm_stop() {
    __vm_stop__ 100 2>/dev/null
    assert_exit_code 0 $? "Should stop VM 100"
}

################################################################################
# TEST: VM CONFIG
################################################################################

test_vm_get_config_memory() {
    local memory
    memory=$(__vm_get_config__ 100 "memory" 2>/dev/null)
    assert_equals "2048" "$memory" "Should get VM memory"
}

################################################################################
# TEST: CT EXISTS
################################################################################

test_ct_exists_valid() {
    __ct_exists__ 200 2>/dev/null
    assert_exit_code 0 $? "CT 200 should exist"
}

test_ct_exists_invalid() {
    local result
    __ct_exists__ 999 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "CT 999 should not exist"
}

################################################################################
# TEST: CT STATUS
################################################################################

test_ct_get_status_running() {
    local status
    status=$(__ct_get_status__ 200 2>/dev/null)
    assert_equals "running" "$status" "CT 200 should be running"
}

test_ct_is_running_true() {
    __ct_is_running__ 200 2>/dev/null
    assert_exit_code 0 $? "CT 200 should be running"
}

################################################################################
# TEST: CT OPERATIONS
################################################################################

test_ct_start() {
    __ct_start__ 206 2>/dev/null
    assert_exit_code 0 $? "Should start CT 206"
}

test_ct_stop() {
    __ct_stop__ 200 2>/dev/null
    assert_exit_code 0 $? "Should stop CT 200"
}

################################################################################
# TEST: CT CONFIG
################################################################################

test_ct_get_config_memory() {
    local memory
    memory=$(__ct_get_config__ 200 "memory" 2>/dev/null)
    assert_equals "1024" "$memory" "Should get CT memory"
}

################################################################################
# RUN TEST SUITE
################################################################################

run_test_suite "ProxmoxAPI - VM" \
    test_vm_exists_valid \
    test_vm_exists_invalid \
    test_vm_get_status_running \
    test_vm_is_running_true \
    test_vm_start \
    test_vm_stop \
    test_vm_get_config_memory

run_test_suite "ProxmoxAPI - CT" \
    test_ct_exists_valid \
    test_ct_exists_invalid \
    test_ct_get_status_running \
    test_ct_is_running_true \
    test_ct_start \
    test_ct_stop \
    test_ct_get_config_memory

exit $?
