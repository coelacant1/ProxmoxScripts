#!/bin/bash
#
# Function Index:
#   - __suite_setup__
#   - __suite_teardown__
#   - __test_setup__
#   - __test_teardown__
#   - test_basic_assertions
#   - test_file_operations
#   - test_exit_codes
#   - test_numeric_comparisons
#   - test_mocking_commands
#   - test_error_handling
#   - test_output_format
#   - test_multiple_mocks
#   - test_config_file_generation
#   - test_experimental_feature
#   - test_data_validation
#   - test_command_chains
#

set -euo pipefail

################################################################################
# Integration Example: Complete Testing Workflow
################################################################################
#
# This example demonstrates how to use the TestFramework with all features:
# - Setup/teardown lifecycle
# - Multiple test functions
# - Various assertion types
# - Mocking external commands
# - Temporary file management
# - Error handling tests
#
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/TestFramework.sh"
source "${SCRIPT_DIR}/ProxmoxAPI.sh"

################################################################################
# TEST CONFIGURATION
################################################################################

# Uncomment to enable verbose output
# VERBOSE_TESTS=true

# Uncomment to stop on first failure
# STOP_ON_FAILURE=true

################################################################################
# SUITE SETUP/TEARDOWN
################################################################################

__suite_setup__() {
    echo "Initializing test environment..."
    # One-time setup for entire suite
}

__suite_teardown__() {
    echo "Cleaning up test environment..."
    # One-time cleanup for entire suite
}

################################################################################
# TEST SETUP/TEARDOWN
################################################################################

__test_setup__() {
    # Setup before each test
    TEST_VMID=999
    TEST_NODE="pve01"
    TEST_CONFIG_FILE=$(create_temp_file)

    # Mock common Proxmox commands
    mock_command "pvesh" "status: running" 0
    mock_command "qm" "success" 0
    mock_command "pct" "success" 0
}

__test_teardown__() {
    # Cleanup after each test
    restore_all_mocks
}

################################################################################
# EXAMPLE 1: BASIC ASSERTIONS
################################################################################

test_basic_assertions() {
    # Equality tests
    local result="success"
    assert_equals "success" "$result" "Should return success"
    assert_not_equals "failure" "$result" "Should not return failure"

    # String tests
    local output="VM 100 is running"
    assert_contains "$output" "running" "Output should contain 'running'"
    assert_not_contains "$output" "stopped" "Output should not contain 'stopped'"

    # Pattern matching
    local ip="192.168.1.100"
    assert_matches "$ip" "^[0-9.]+$" "Should be valid IP format"

    # Boolean tests
    local enabled=true
    assert_true "$enabled" "Feature should be enabled"

    local disabled=""
    assert_false "$disabled" "Feature should be disabled"
}

################################################################################
# EXAMPLE 2: FILE SYSTEM ASSERTIONS
################################################################################

test_file_operations() {
    # Create temporary file
    local temp_file
    temp_file=$(create_temp_file "test content")

    # Test file exists
    assert_file_exists "$temp_file" "Temp file should exist"

    # Verify content
    local content
    content=$(cat "$temp_file")
    assert_equals "test content" "$content" "Content should match"

    # Create directory
    local temp_dir
    temp_dir=$(create_temp_dir)
    assert_dir_exists "$temp_dir" "Temp directory should exist"

    # File cleanup happens automatically via __test_teardown__
}

################################################################################
# EXAMPLE 3: EXIT CODE TESTING
################################################################################

test_exit_codes() {
    # Test successful command
    true
    assert_exit_code 0 $? "True should return 0"

    # Test failed command
    local exit_code
    false || exit_code=$?
    assert_exit_code 1 $exit_code "False should return 1"

    # Test command that should succeed
    echo "test" > /dev/null
    assert_exit_code 0 $? "Echo should succeed"
}

################################################################################
# EXAMPLE 4: NUMERIC COMPARISONS
################################################################################

test_numeric_comparisons() {
    local cpu_count=4
    local memory_mb=8192

    # Greater than tests
    assert_greater_than $cpu_count 0 "Should have at least 1 CPU"
    assert_greater_than $memory_mb 1024 "Should have more than 1GB RAM"

    # Less than tests
    assert_less_than $cpu_count 128 "Should have less than 128 CPUs"
    assert_less_than $memory_mb 65536 "Should have less than 64GB RAM"
}

################################################################################
# EXAMPLE 5: MOCKING EXTERNAL COMMANDS
################################################################################

test_mocking_commands() {
    # Mock pvesh to return specific VM status
    mock_command "pvesh" '{"status":"running","uptime":12345}' 0

    # Call function that uses pvesh
    local output
    output=$(pvesh get /nodes/pve01/qemu/100/status/current)

    # Verify output
    assert_contains "$output" "running" "Should return running status"
    assert_contains "$output" "12345" "Should include uptime"

    # Verify mock was called
    assert_mock_called "pvesh" 1 "Should call pvesh once"

    # Restore for next test
    restore_all_mocks
}

################################################################################
# EXAMPLE 6: TESTING ERROR HANDLING
################################################################################

test_error_handling() {
    # Mock command to fail
    mock_command "pvesh" "Error: VM not found" 1

    # Test that function handles error appropriately
    local exit_code
    pvesh get /nodes/pve01/qemu/999/status/current || exit_code=$?

    # Verify failure
    assert_not_equals 0 $exit_code "Should fail for non-existent VM"

    restore_all_mocks
}

################################################################################
# EXAMPLE 7: TESTING OUTPUT FORMAT
################################################################################

test_output_format() {
    # Test function output format
    local output="VMID: 100, Name: test-vm, Status: running"

    # Verify format with regex
    assert_matches "$output" "VMID: [0-9]+" "Should contain VMID"
    assert_matches "$output" "Name: [a-z-]+" "Should contain name"
    assert_matches "$output" "Status: [a-z]+" "Should contain status"

    # Verify specific values
    assert_contains "$output" "100" "Should show VM 100"
    assert_contains "$output" "test-vm" "Should show VM name"
    assert_contains "$output" "running" "Should show running status"
}

################################################################################
# EXAMPLE 8: TESTING WITH MULTIPLE MOCKS
################################################################################

test_multiple_mocks() {
    # Mock multiple commands
    mock_command "pvesh" "node: pve01" 0
    mock_command "qm" "VM 100 created" 0
    mock_command "pct" "CT 200 created" 0

    # Use all mocked commands
    pvesh get /nodes
    qm create 100
    pct create 200

    # Verify all were called
    assert_mock_called "pvesh" 1 "Should call pvesh"
    assert_mock_called "qm" 1 "Should call qm"
    assert_mock_called "pct" 1 "Should call pct"

    restore_all_mocks
}

################################################################################
# EXAMPLE 9: TESTING WITH TEMP FILES
################################################################################

test_config_file_generation() {
    local config_file
    config_file=$(create_temp_file)

    # Generate config (simulated)
    cat > "$config_file" << EOF
cores: 4
memory: 8192
name: test-vm
EOF

    # Verify file was created
    assert_file_exists "$config_file" "Config file should exist"

    # Verify content
    local content
    content=$(cat "$config_file")
    assert_contains "$content" "cores: 4" "Should have cores setting"
    assert_contains "$content" "memory: 8192" "Should have memory setting"
    assert_contains "$content" "name: test-vm" "Should have name setting"
}

################################################################################
# EXAMPLE 10: CONDITIONAL TEST SKIPPING
################################################################################

test_experimental_feature() {
    # Skip test if feature not available
    if [[ ! -f "/usr/bin/experimental_tool" ]]; then
        skip_test "Experimental tool not installed"
    fi

    # Test code only runs if condition passes
    # This test will be skipped in most environments
    experimental_tool --version
    assert_exit_code 0 $?
}

################################################################################
# EXAMPLE 11: TESTING DATA VALIDATION
################################################################################

test_data_validation() {
    # Test VMID validation
    local valid_vmid=100
    assert_greater_than $valid_vmid 99 "VMID should be >= 100"
    assert_less_than $valid_vmid 1000000 "VMID should be < 1000000"

    # Test IP validation (using regex)
    local ip="192.168.1.100"
    assert_matches "$ip" "^([0-9]{1,3}\.){3}[0-9]{1,3}$" "Should match IP format"

    # Test hostname validation
    local hostname="test-vm-01"
    assert_matches "$hostname" "^[a-z0-9-]+$" "Should match hostname format"
}

################################################################################
# EXAMPLE 12: TESTING COMMAND CHAINS
################################################################################

test_command_chains() {
    # Test multiple operations in sequence
    local step1 step2 step3

    # Step 1: Create VM
    mock_command "qm" "VM created" 0
    step1=$(qm create $TEST_VMID)
    assert_contains "$step1" "created" "Should create VM"

    # Step 2: Configure VM
    mock_command "qm" "VM configured" 0
    step2=$(qm set $TEST_VMID --cores 4)
    assert_contains "$step2" "configured" "Should configure VM"

    # Step 3: Start VM
    mock_command "qm" "VM started" 0
    step3=$(qm start $TEST_VMID)
    assert_contains "$step3" "started" "Should start VM"

    restore_all_mocks
}

################################################################################
# RUN ALL TESTS
################################################################################

run_test_suite "Integration Example Tests" \
    test_basic_assertions \
    test_file_operations \
    test_exit_codes \
    test_numeric_comparisons \
    test_mocking_commands \
    test_error_handling \
    test_output_format \
    test_multiple_mocks \
    test_config_file_generation \
    test_experimental_feature \
    test_data_validation \
    test_command_chains

# Return test suite exit code
exit $?
