#!/bin/bash
#
# _TestMenu.sh
#
# Test suite for Menu.sh utility functions including menu rendering,
# navigation handling, and user interaction.
#
# Usage:
#   _TestMenu.sh
#
# Notes:
#   - Uses TestFramework.sh for test execution and assertions
#   - Tests menu header/footer rendering with borders
#   - Tests numbered menu item display
#   - Tests navigation choice handling (help/back/exit/custom)
#   - Can be run locally or via RemoteRunAllTests.sh on Proxmox nodes
#
# Function Index:
#   - __line_rgb__
#   - test_menu_header
#   - test_menu_footer
#   - test_menu_display_numbered
#   - test_menu_choice_help
#   - test_menu_choice_back
#   - test_menu_choice_exit
#   - test_menu_choice_unhandled
#

set -euo pipefail

################################################################################
# _TestMenu.sh - Test suite for Menu.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"
export LOG_LEVEL=ERROR
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"

# Mock Colors.sh functions if not available
__line_rgb__() {
    echo "$1"
}

################################################################################
# TEST: Menu Header
################################################################################

test_menu_header() {
    source "${SCRIPT_DIR}/Menu.sh" 2>/dev/null || true

    if declare -f __menu_header__ >/dev/null 2>&1; then
        local output
        output=$(__menu_header__ "Test Menu" 2>/dev/null)

        assert_contains "$output" "Test Menu" "Should contain menu title"
        assert_contains "$output" "---" "Should contain separator"
    else
        skip_test "Function __menu_header__ not available"
    fi
}

################################################################################
# TEST: Menu Footer
################################################################################

test_menu_footer() {
    source "${SCRIPT_DIR}/Menu.sh" 2>/dev/null || true

    if declare -f __menu_footer__ >/dev/null 2>&1; then
        local output

        # Test with all options enabled (default)
        output=$(__menu_footer__ 2>/dev/null)
        assert_contains "$output" "help" "Should show help option"
        assert_contains "$output" "back" "Should show back option"
        assert_contains "$output" "exit" "Should show exit option"

        # Test with selective options
        output=$(__menu_footer__ "false" "true" "false" 2>/dev/null)
        assert_not_contains "$output" "help" "Should not show help option"
        assert_contains "$output" "back" "Should show back option"
        assert_not_contains "$output" "exit" "Should not show exit option"
    else
        skip_test "Function __menu_footer__ not available"
    fi
}

################################################################################
# TEST: Menu Display - Numbered
################################################################################

test_menu_display_numbered() {
    source "${SCRIPT_DIR}/Menu.sh" 2>/dev/null || true

    if declare -f __menu_display__ >/dev/null 2>&1; then
        local output
        output=$(__menu_display__ "numbered" "Option 1" "Option 2" "Option 3" 2>/dev/null)

        assert_contains "$output" "1)" "Should have number 1"
        assert_contains "$output" "2)" "Should have number 2"
        assert_contains "$output" "3)" "Should have number 3"
        assert_contains "$output" "Option 1" "Should contain first option"
        assert_contains "$output" "Option 2" "Should contain second option"
        assert_contains "$output" "Option 3" "Should contain third option"
    else
        skip_test "Function __menu_display__ not available"
    fi
}

################################################################################
# TEST: Menu Choice - Help
################################################################################

test_menu_choice_help() {
    source "${SCRIPT_DIR}/Menu.sh" 2>/dev/null || true

    if declare -f __menu_choice__ >/dev/null 2>&1; then
        # Test 'h' for help
        __menu_choice__ "h" 2>/dev/null
        local result=$?
        assert_exit_code 3 $result "Should return 3 for help (h)"

        # Test '?' for help
        __menu_choice__ "?" 2>/dev/null
        result=$?
        assert_exit_code 3 $result "Should return 3 for help (?)"
    else
        skip_test "Function __menu_choice__ not available"
    fi
}

################################################################################
# TEST: Menu Choice - Back
################################################################################

test_menu_choice_back() {
    source "${SCRIPT_DIR}/Menu.sh" 2>/dev/null || true

    if declare -f __menu_choice__ >/dev/null 2>&1; then
        # Test lowercase 'b' for back
        __menu_choice__ "b" 2>/dev/null
        local result=$?
        assert_exit_code 1 $result "Should return 1 for back (b)"

        # Test uppercase 'B' for back
        __menu_choice__ "B" 2>/dev/null
        result=$?
        assert_exit_code 1 $result "Should return 1 for back (B)"
    else
        skip_test "Function __menu_choice__ not available"
    fi
}

################################################################################
# TEST: Menu Choice - Exit
################################################################################

test_menu_choice_exit() {
    source "${SCRIPT_DIR}/Menu.sh" 2>/dev/null || true

    if declare -f __menu_choice__ >/dev/null 2>&1; then
        # Test lowercase 'e' for exit
        __menu_choice__ "e" 2>/dev/null
        local result=$?
        assert_exit_code 2 $result "Should return 2 for exit (e)"

        # Test uppercase 'E' for exit
        __menu_choice__ "E" 2>/dev/null
        result=$?
        assert_exit_code 2 $result "Should return 2 for exit (E)"
    else
        skip_test "Function __menu_choice__ not available"
    fi
}

################################################################################
# TEST: Menu Choice - Unhandled
################################################################################

test_menu_choice_unhandled() {
    source "${SCRIPT_DIR}/Menu.sh" 2>/dev/null || true

    if declare -f __menu_choice__ >/dev/null 2>&1; then
        # Test numeric choice (should be unhandled)
        __menu_choice__ "1" 2>/dev/null
        local result=$?
        assert_exit_code 4 $result "Should return 4 for unhandled choice"

        # Test arbitrary text (should be unhandled)
        __menu_choice__ "custom" 2>/dev/null
        result=$?
        assert_exit_code 4 $result "Should return 4 for custom choice"
    else
        skip_test "Function __menu_choice__ not available"
    fi
}

################################################################################
# RUN TESTS
################################################################################

run_test_suite "Menu.sh Tests" \
    test_menu_header \
    test_menu_footer \
    test_menu_display_numbered \
    test_menu_choice_help \
    test_menu_choice_back \
    test_menu_choice_exit \
    test_menu_choice_unhandled

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

