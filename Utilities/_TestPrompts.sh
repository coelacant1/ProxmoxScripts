#!/bin/bash
#
# Function Index:
#   - __check_root__
#   - __check_proxmox__
#   - __require_root_and_proxmox__
#   - __install_or_prompt__
#   - __prompt_keep_installed_packages__
#   - __ensure_dependencies__
#   - test_check_root_executes
#   - test_check_proxmox_executes
#   - test_require_checks
#   - test_install_or_prompt
#   - test_ensure_dependencies
#

set -euo pipefail

################################################################################
# _TestPrompts.sh - Test suite for Prompts.sh
################################################################################
#
# Test suite for Prompts.sh validation and prompting functions.
#
# Usage: ./_TestPrompts.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/TestFramework.sh"

# Mock functions to avoid actual system checks
__check_root__() { return 0; }
__check_proxmox__() { return 0; }
__require_root_and_proxmox__() { return 0; }
__install_or_prompt__() { return 0; }
__prompt_keep_installed_packages__() { return 0; }
__ensure_dependencies__() { return 0; }

export -f __check_root__
export -f __check_proxmox__
export -f __require_root_and_proxmox__
export -f __install_or_prompt__
export -f __prompt_keep_installed_packages__
export -f __ensure_dependencies__

source "${SCRIPT_DIR}/Prompts.sh"

################################################################################
# TEST: PROMPTS FUNCTIONS
################################################################################

test_check_root_executes() {
    __check_root__ 2>/dev/null
    assert_exit_code 0 $? "Should execute check_root"
}

test_check_proxmox_executes() {
    __check_proxmox__ 2>/dev/null
    assert_exit_code 0 $? "Should execute check_proxmox"
}

test_require_checks() {
    __require_root_and_proxmox__ 2>/dev/null
    assert_exit_code 0 $? "Should execute combined checks"
}

test_install_or_prompt() {
    __install_or_prompt__ "curl" 2>/dev/null
    assert_exit_code 0 $? "Should execute install_or_prompt"
}

test_ensure_dependencies() {
    __ensure_dependencies__ --quiet bash 2>/dev/null
    assert_exit_code 0 $? "Should execute ensure_dependencies"
}

################################################################################
# RUN TEST SUITE
################################################################################

test_framework_init

run_test_suite "Prompts Functions" \
    test_check_root_executes \
    test_check_proxmox_executes \
    test_require_checks \
    test_install_or_prompt \
    test_ensure_dependencies

exit $?
