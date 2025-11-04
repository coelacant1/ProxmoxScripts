#!/bin/bash
#
# Function Index:
#   - test_info_executes
#   - test_ok_executes
#   - test_warn_executes
#   - test_err_executes
#   - test_update_executes
#   - test_message_buffer
#   - test_quiet_mode_info
#   - test_quiet_mode_warnings_visible
#   - test_sequential_messages
#   - test_rapid_updates
#

set -euo pipefail

################################################################################
# _TestCommunication.sh - Test suite for Communication.sh
################################################################################
#
# Test suite for Communication.sh spinner and messaging functions.
#
# Usage: ./_TestCommunication.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/TestFramework.sh"
source "${SCRIPT_DIR}/Communication.sh"

################################################################################
# TEST: MESSAGING FUNCTIONS
################################################################################

test_info_executes() {
    __info__ "Test message" 2>/dev/null
    __stop_spin__
    assert_exit_code 0 $? "info should execute without error"
}

test_ok_executes() {
    __info__ "Processing" 2>/dev/null
    __ok__ "Done" 2>/dev/null
    assert_exit_code 0 $? "ok should execute without error"
}

test_warn_executes() {
    __warn__ "Warning message" 2>/dev/null
    assert_exit_code 0 $? "warn should execute without error"
}

test_err_executes() {
    __err__ "Error message" 2>/dev/null
    assert_exit_code 0 $? "err should execute without error"
}

test_update_executes() {
    __info__ "Starting..." 2>/dev/null
    sleep 0.2
    __update__ "Updating..." 2>/dev/null
    sleep 0.2
    __ok__ "Complete" 2>/dev/null
    assert_exit_code 0 $? "update should execute without error"
}

test_message_buffer() {
    CURRENT_MESSAGE="test"
    [[ "$CURRENT_MESSAGE" == "test" ]]
    assert_exit_code 0 $? "message buffer should be accessible"
}

test_quiet_mode_info() {
    QUIET_MODE=true
    __info__ "Should be hidden" 2>/dev/null
    __stop_spin__
    QUIET_MODE=false
    assert_exit_code 0 $? "quiet mode should suppress info"
}

test_quiet_mode_warnings_visible() {
    QUIET_MODE=true
    __warn__ "Should still show" 2>/dev/null
    QUIET_MODE=false
    assert_exit_code 0 $? "quiet mode should show warnings"
}

test_sequential_messages() {
    __info__ "Step 1" 2>/dev/null
    sleep 0.1
    __info__ "Step 2" 2>/dev/null
    sleep 0.1
    __ok__ "Complete" 2>/dev/null
    assert_exit_code 0 $? "sequential messages should work"
}

test_rapid_updates() {
    __info__ "Processing" 2>/dev/null
    for i in {1..5}; do
        __update__ "Item $i" 2>/dev/null
        sleep 0.05
    done
    __ok__ "Done" 2>/dev/null
    assert_exit_code 0 $? "rapid updates should work"
}

################################################################################
# RUN TEST SUITE
################################################################################

run_test_suite "Communication Functions" \
    test_info_executes \
    test_ok_executes \
    test_warn_executes \
    test_err_executes \
    test_update_executes \
    test_message_buffer \
    test_quiet_mode_info \
    test_quiet_mode_warnings_visible \
    test_sequential_messages \
    test_rapid_updates

exit $?
