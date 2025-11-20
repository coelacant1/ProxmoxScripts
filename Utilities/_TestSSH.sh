#!/bin/bash
#
# Function Index:
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

# Skip install checks during testing
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"

# Initialize test framework to set up mocking infrastructure
test_framework_init

###############################################################################
# MOCK FUNCTIONS USING PATH
###############################################################################

# Create mock scripts in PATH
mkdir -p "$TEST_TEMP_DIR/bin"
export PATH="$TEST_TEMP_DIR/bin:$PATH"

# Mock ssh command
cat >"$TEST_TEMP_DIR/bin/ssh" <<'MOCK_SSH'
#!/bin/bash
echo "test output"
exit 0
MOCK_SSH
chmod +x "$TEST_TEMP_DIR/bin/ssh"

# Mock scp command
cat >"$TEST_TEMP_DIR/bin/scp" <<'MOCK_SCP'
#!/bin/bash
exit 0
MOCK_SCP
chmod +x "$TEST_TEMP_DIR/bin/scp"

# Mock sshpass command
cat >"$TEST_TEMP_DIR/bin/sshpass" <<'MOCK_SSHPASS'
#!/bin/bash
# Skip the -p password argument and execute the rest
shift 2
exec "$@"
MOCK_SSHPASS
chmod +x "$TEST_TEMP_DIR/bin/sshpass"

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
    echo "test" >"$tmpfile"

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

test_framework_init

run_test_suite "SSH Functions" \
    test_ssh_execute \
    test_ssh_copy_to_remote \
    test_ssh_copy_from_remote \
    test_ssh_test_connection

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

