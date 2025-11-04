#!/bin/bash
#
# Function Index:
#   - ssh
#   - scp
#   - test_ssh_execute
#   - test_ssh_copy_to_remote
#   - test_ssh_copy_from_remote
#   - test_ssh_test_connection
#

set -euo pipefail

################################################################################
# _TestSSH.sh - Test suite for SSH.sh
################################################################################
#
# Test suite for SSH.sh remote execution functions.
#
# Usage: ./_TestSSH.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/TestFramework.sh"

###############################################################################
# MOCK FUNCTIONS
###############################################################################

ssh() {
    echo "test output"
    return 0
}

scp() {
    return 0
}

export -f ssh
export -f scp

source "${SCRIPT_DIR}/SSH.sh"

################################################################################
# TEST: SSH FUNCTIONS
################################################################################

test_ssh_execute() {
    local result
    result=$(__ssh_execute__ "testhost" "echo test" 2>/dev/null)
    assert_exit_code 0 $? "Should execute SSH command"
}

test_ssh_copy_to_remote() {
    local tmpfile=$(create_temp_file)
    echo "test" > "$tmpfile"

    __ssh_copy_to_remote__ "$tmpfile" "testhost" "/tmp/test" 2>/dev/null
    assert_exit_code 0 $? "Should copy to remote"
}

test_ssh_copy_from_remote() {
    local tmpfile=$(create_temp_file)

    __ssh_copy_from_remote__ "testhost" "/tmp/test" "$tmpfile" 2>/dev/null
    assert_exit_code 0 $? "Should copy from remote"
}

test_ssh_test_connection() {
    __ssh_test_connection__ "testhost" 2>/dev/null
    assert_exit_code 0 $? "Should test connection"
}

################################################################################
# RUN TEST SUITE
################################################################################

run_test_suite "SSH Functions" \
    test_ssh_execute \
    test_ssh_copy_to_remote \
    test_ssh_copy_from_remote \
    test_ssh_test_connection

exit $?
