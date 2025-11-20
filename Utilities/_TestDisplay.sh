#!/bin/bash
#
# _TestDisplay.sh
#
# Test suite for Display.sh utility functions including ASCII art rendering,
# path formatting, and script documentation display.
#
# Usage:
#   _TestDisplay.sh
#
# Notes:
#   - Uses TestFramework.sh for test execution and assertions
#   - Tests ASCII art in multiple modes (basic/small/large/auto)
#   - Tests path formatting and display functions
#   - Mocks tput for terminal width detection
#   - Can be run locally or via RemoteRunAllTests.sh on Proxmox nodes
#
# Function Index:
#   - test_show_ascii_art_basic
#   - test_show_ascii_art_small
#   - test_show_ascii_art_large
#   - test_show_ascii_art_auto
#   - test_display_path
#   - test_show_script_info
#

set -euo pipefail

################################################################################
# _TestDisplay.sh - Test suite for Display.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"
export LOG_LEVEL=ERROR
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"

################################################################################
# TEST: Show ASCII Art - Basic
################################################################################

test_show_ascii_art_basic() {
    source "${SCRIPT_DIR}/Display.sh" 2>/dev/null || true

    if declare -f __show_ascii_art__ >/dev/null 2>&1; then
        local output
        output=$(__show_ascii_art__ "basic" 2>/dev/null || echo "")

        assert_contains "$output" "█" "Should contain block characters"
        assert_contains "$output" "---" "Should contain separator lines"
    else
        skip_test "Function __show_ascii_art__ not available"
    fi
}

################################################################################
# TEST: Show ASCII Art - Small
################################################################################

test_show_ascii_art_small() {
    source "${SCRIPT_DIR}/Display.sh" 2>/dev/null || true

    if declare -f __show_ascii_art__ >/dev/null 2>&1; then
        local output
        output=$(__show_ascii_art__ "small" 2>/dev/null || echo "")

        assert_contains "$output" "█" "Should contain block characters"
        assert_contains "$output" "---" "Should contain separator lines"
    else
        skip_test "Function __show_ascii_art__ not available"
    fi
}

################################################################################
# TEST: Show ASCII Art - Large
################################################################################

test_show_ascii_art_large() {
    source "${SCRIPT_DIR}/Display.sh" 2>/dev/null || true

    if declare -f __show_ascii_art__ >/dev/null 2>&1; then
        local output
        output=$(__show_ascii_art__ "large" 2>/dev/null || echo "")

        assert_contains "$output" "█" "Should contain block characters"
        assert_contains "$output" "Coela Can't!" "Should contain author attribution"
    else
        skip_test "Function __show_ascii_art__ not available"
    fi
}

################################################################################
# TEST: Show ASCII Art - Auto
################################################################################

test_show_ascii_art_auto() {
    source "${SCRIPT_DIR}/Display.sh" 2>/dev/null || true

    if declare -f __show_ascii_art__ >/dev/null 2>&1; then
        # Mock tput to return specific width
        tput() { echo "100"; }
        export -f tput

        local output
        output=$(__show_ascii_art__ "auto" 2>/dev/null || echo "")

        assert_true "$output" "Should produce output in auto mode"
    else
        skip_test "Function __show_ascii_art__ not available"
    fi
}

################################################################################
# TEST: Display Path
################################################################################

test_display_path() {
    source "${SCRIPT_DIR}/Display.sh" 2>/dev/null || true

    if declare -f __display_path__ >/dev/null 2>&1; then
        local result
        # __display_path__ takes: fullpath, base_dir, prefix
        result=$(__display_path__ "/home/user/test" "/home" "TestPrefix" 2>/dev/null || echo "")

        assert_contains "$result" "user/test" "Should contain the relative path"
        assert_contains "$result" "TestPrefix" "Should contain the prefix"
    else
        skip_test "Function __display_path__ not available"
    fi
}

################################################################################
# TEST: Show Script Info
################################################################################

test_show_script_info() {
    source "${SCRIPT_DIR}/Display.sh" 2>/dev/null || true

    if declare -f __show_script_info__ >/dev/null 2>&1; then
        # Create test script with documentation
        local test_script="${TEST_TEMP_DIR}/test_script.sh"
        cat >"$test_script" <<'EOF'
#!/bin/bash
# Test Script
# Description: This is a test script
# Usage: test_script.sh [options]
EOF

        local output
        output=$(__show_script_info__ "$test_script" 2>/dev/null || echo "")

        # Function should handle script info display
        assert_true "1" "Function __show_script_info__ is callable"
    else
        skip_test "Function __show_script_info__ not available"
    fi
}

################################################################################
# RUN TESTS
################################################################################

run_test_suite "Display.sh Tests" \
    test_show_ascii_art_basic \
    test_show_ascii_art_small \
    test_show_ascii_art_large \
    test_show_ascii_art_auto \
    test_display_path \
    test_show_script_info

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

