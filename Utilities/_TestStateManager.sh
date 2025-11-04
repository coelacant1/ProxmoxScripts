#!/bin/bash
#
# Function Index:
#   - __get_vm_node__
#   - qm
#   - pct
#   - __info__
#   - __update__
#   - __ok__
#   - __warn__
#   - __err__
#   - test_vm_state_save_basic
#   - test_vm_state_save_content
#   - test_ct_state_save_basic
#   - test_ct_state_save_content
#   - test_vm_state_restore_success
#   - test_vm_state_restore_missing
#   - test_state_compare_identical
#   - test_state_compare_different
#

set -euo pipefail

################################################################################
# _TestStateManager.sh - Test suite for StateManager.sh
################################################################################
#
# Test suite for StateManager.sh functions.
# Tests state save/restore, comparison, and validation.
#
# Usage: ./_TestStateManager.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/TestFramework.sh"

###############################################################################
# MOCK FUNCTIONS
###############################################################################

__get_vm_node__() {
    local vmid="$1"
    if (( vmid >= 100 && vmid <= 120 )); then
        echo "node1"
    else
        return 1
    fi
}

qm() {
    case "$1" in
        config)
            echo "memory: 2048"
            echo "cores: 4"
            echo "name: vm${2}"
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

pct() {
    case "$1" in
        config)
            if (( $2 >= 200 && $2 <= 210 )); then
                echo "memory: 1024"
                echo "cores: 2"
                echo "hostname: ct${2}"
                return 0
            else
                return 1
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

__info__() { : ; }
__update__() { : ; }
__ok__() { : ; }
__warn__() { : ; }
__err__() { : ; }

export -f __get_vm_node__
export -f qm
export -f pct
export -f __info__
export -f __update__
export -f __ok__
export -f __warn__
export -f __err__

source "${UTILITYPATH}/StateManager.sh"

################################################################################
# TEST: VM STATE SAVE
################################################################################

test_vm_state_save_basic() {
    local statefile=$(create_temp_file)

    __vm_state_save__ 100 "$statefile" 2>/dev/null
    assert_exit_code 0 $? "Should save VM state"
    assert_file_exists "$statefile" "State file should exist"
}

test_vm_state_save_content() {
    local statefile=$(create_temp_file)

    __vm_state_save__ 100 "$statefile" 2>/dev/null
    local content=$(cat "$statefile")

    assert_contains "$content" "memory" "Should contain memory"
    assert_contains "$content" "cores" "Should contain cores"
}

################################################################################
# TEST: CT STATE SAVE
################################################################################

test_ct_state_save_basic() {
    local statefile=$(create_temp_file)

    __ct_state_save__ 200 "$statefile" 2>/dev/null
    assert_exit_code 0 $? "Should save CT state"
    assert_file_exists "$statefile" "State file should exist"
}

test_ct_state_save_content() {
    local statefile=$(create_temp_file)

    __ct_state_save__ 200 "$statefile" 2>/dev/null
    local content=$(cat "$statefile")

    assert_contains "$content" "memory" "Should contain memory"
    assert_contains "$content" "hostname" "Should contain hostname"
}

################################################################################
# TEST: VM STATE RESTORE
################################################################################

test_vm_state_restore_success() {
    local statefile=$(create_temp_file)
    echo "memory: 4096" > "$statefile"
    echo "cores: 8" >> "$statefile"

    __vm_state_restore__ 101 "$statefile" 2>/dev/null
    assert_exit_code 0 $? "Should restore VM state"
}

test_vm_state_restore_missing() {
    local result
    __vm_state_restore__ 101 "/nonexistent/file" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Should fail for missing file"
}

################################################################################
# TEST: STATE COMPARE
################################################################################

test_state_compare_identical() {
    local file1=$(create_temp_file)
    local file2=$(create_temp_file)

    echo "memory: 2048" > "$file1"
    echo "cores: 4" >> "$file1"

    echo "memory: 2048" > "$file2"
    echo "cores: 4" >> "$file2"

    __state_compare__ "$file1" "$file2" 2>/dev/null
    assert_exit_code 0 $? "Identical states should match"
}

test_state_compare_different() {
    local file1=$(create_temp_file)
    local file2=$(create_temp_file)

    echo "memory: 2048" > "$file1"
    echo "memory: 4096" > "$file2"

    local result
    __state_compare__ "$file1" "$file2" 2>/dev/null && result=0 || result=$?
    assert_not_equals 0 $result "Different states should not match"
}

################################################################################
# RUN TEST SUITE
################################################################################

run_test_suite "StateManager - VM State Save" \
    test_vm_state_save_basic \
    test_vm_state_save_content

run_test_suite "StateManager - CT State Save" \
    test_ct_state_save_basic \
    test_ct_state_save_content

run_test_suite "StateManager - VM State Restore" \
    test_vm_state_restore_success \
    test_vm_state_restore_missing

run_test_suite "StateManager - State Compare" \
    test_state_compare_identical \
    test_state_compare_different

exit $?
