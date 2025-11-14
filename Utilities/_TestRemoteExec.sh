#!/bin/bash
#
# _TestRemoteExec.sh
#
# Test suite for remote execution utility functions in Operations.sh
#
# Usage:
#   bash _TestRemoteExec.sh
#
# Function Index:
#   - test_node_exec_local
#   - test_node_exec_missing_params
#   - test_vm_node_exec_placeholder
#   - __vm_exists__
#   - __get_vm_node__
#   - __node_exec__
#   - test_vm_node_exec_nonexistent
#   - __vm_exists__
#   - test_vm_node_exec_invalid_vmid
#   - test_ct_node_exec_placeholder
#   - __ct_exists__
#   - __get_vm_node__
#   - __node_exec__
#   - test_ct_node_exec_nonexistent
#   - __ct_exists__
#   - test_pve_exec_vm_detection
#   - __vm_exists__
#   - __ct_exists__
#   - __vm_node_exec__
#   - test_pve_exec_ct_detection
#   - __vm_exists__
#   - __ct_exists__
#   - __ct_node_exec__
#   - test_pve_exec_nonexistent
#   - __vm_exists__
#   - __ct_exists__
#   - test_pve_exec_invalid_id
#   - test_command_passthrough_qm_destroy
#   - __vm_exists__
#   - __get_vm_node__
#   - __node_exec__
#   - test_command_passthrough_multiple_placeholders
#   - __vm_exists__
#   - __get_vm_node__
#   - __node_exec__
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITYPATH="$SCRIPT_DIR"

# Source the test framework
source "${UTILITYPATH}/TestFramework.sh"
source "${UTILITYPATH}/Operations.sh"

# --- Test: __node_exec__ basic functionality ---------------------------------
test_node_exec_local() {
    local hostname
    hostname=$(hostname)

    # Test local execution
    local result
    result=$(__node_exec__ "$hostname" "echo 'test'")

    assert_equals "$result" "test" "Local node execution should work"
}

test_node_exec_missing_params() {
    __node_exec__ "" "echo test" 2>/dev/null
    assert_exit_code 1 "Should fail with missing node parameter"

    __node_exec__ "node" "" 2>/dev/null
    assert_exit_code 1 "Should fail with missing command parameter"
}

# --- Test: __vm_node_exec__ functionality ------------------------------------
test_vm_node_exec_placeholder() {
    # Mock functions for testing
    __vm_exists__() { [[ "$1" == "100" ]]; }
    __get_vm_node__() { echo "testnode"; }
    __node_exec__() {
        # Verify the placeholder was replaced
        if [[ "$2" == "qm destroy 100 --purge" ]]; then
            return 0
        fi
        return 1
    }

    __vm_node_exec__ 100 "qm destroy {vmid} --purge"
    assert_exit_code 0 "Should replace {vmid} placeholder and execute"
}

test_vm_node_exec_nonexistent() {
    # Mock: VM doesn't exist
    __vm_exists__() { return 1; }

    __vm_node_exec__ 999 "qm stop {vmid}" 2>/dev/null
    assert_exit_code 1 "Should fail for nonexistent VM"
}

test_vm_node_exec_invalid_vmid() {
    __vm_node_exec__ "abc" "qm stop {vmid}" 2>/dev/null
    assert_exit_code 1 "Should fail with invalid VMID"
}

# --- Test: __ct_node_exec__ functionality ------------------------------------
test_ct_node_exec_placeholder() {
    # Mock functions for testing
    __ct_exists__() { [[ "$1" == "200" ]]; }
    __get_vm_node__() { echo "testnode"; }
    __node_exec__() {
        # Verify the placeholder was replaced
        if [[ "$2" == "pct destroy 200 --purge" ]]; then
            return 0
        fi
        return 1
    }

    __ct_node_exec__ 200 "pct destroy {ctid} --purge"
    assert_exit_code 0 "Should replace {ctid} placeholder and execute"
}

test_ct_node_exec_nonexistent() {
    # Mock: CT doesn't exist
    __ct_exists__() { return 1; }

    __ct_node_exec__ 999 "pct stop {ctid}" 2>/dev/null
    assert_exit_code 1 "Should fail for nonexistent CT"
}

# --- Test: __pve_exec__ auto-detection ---------------------------------------
test_pve_exec_vm_detection() {
    # Mock: ID 100 is a VM
    __vm_exists__() { [[ "$1" == "100" ]]; }
    __ct_exists__() { return 1; }
    __vm_node_exec__() { return 0; }

    __pve_exec__ 100 "qm stop 100"
    assert_exit_code 0 "Should detect VM and call __vm_node_exec__"
}

test_pve_exec_ct_detection() {
    # Mock: ID 200 is a CT
    __vm_exists__() { return 1; }
    __ct_exists__() { [[ "$1" == "200" ]]; }
    __ct_node_exec__() { return 0; }

    __pve_exec__ 200 "pct stop 200"
    assert_exit_code 0 "Should detect CT and call __ct_node_exec__"
}

test_pve_exec_nonexistent() {
    # Mock: ID doesn't exist
    __vm_exists__() { return 1; }
    __ct_exists__() { return 1; }

    __pve_exec__ 999 "qm stop 999" 2>/dev/null
    assert_exit_code 1 "Should fail for nonexistent VM/CT"
}

test_pve_exec_invalid_id() {
    __pve_exec__ "invalid" "qm stop invalid" 2>/dev/null
    assert_exit_code 1 "Should fail with invalid ID"
}

# --- Test: Command passthrough patterns --------------------------------------
test_command_passthrough_qm_destroy() {
    # Mock for testing the exact use case from BulkDelete.sh
    __vm_exists__() { [[ "$1" == "100" ]]; }
    __get_vm_node__() { echo "testnode"; }
    __node_exec__() {
        # Verify the exact command pattern
        if [[ "$1" == "testnode" ]] && [[ "$2" == "qm destroy 100 --skiplock --purge" ]]; then
            return 0
        fi
        return 1
    }

    __vm_node_exec__ 100 "qm destroy {vmid} --skiplock --purge"
    assert_exit_code 0 "Should work with qm destroy pattern from BulkDelete.sh"
}

test_command_passthrough_multiple_placeholders() {
    __vm_exists__() { [[ "$1" == "100" ]]; }
    __get_vm_node__() { echo "testnode"; }
    __node_exec__() {
        # Command should have all placeholders replaced
        if [[ "$2" == "qm set 100 --name vm-100" ]]; then
            return 0
        fi
        return 1
    }

    __vm_node_exec__ 100 "qm set {vmid} --name vm-{vmid}"
    assert_exit_code 0 "Should replace multiple placeholder instances"
}

# Run all tests
run_test_suite "Remote Execution Utilities" \
    test_node_exec_local \
    test_node_exec_missing_params \
    test_vm_node_exec_placeholder \
    test_vm_node_exec_nonexistent \
    test_vm_node_exec_invalid_vmid \
    test_ct_node_exec_placeholder \
    test_ct_node_exec_nonexistent \
    test_pve_exec_vm_detection \
    test_pve_exec_ct_detection \
    test_pve_exec_nonexistent \
    test_pve_exec_invalid_id \
    test_command_passthrough_qm_destroy \
    test_command_passthrough_multiple_placeholders
