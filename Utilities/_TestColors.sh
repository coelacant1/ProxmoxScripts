#!/bin/bash
#
# Function Index:
#   - test_gradient_print_executes
#   - test_gradient_print_multiline
#   - test_line_rgb_executes
#   - test_line_rgb_output
#   - test_line_gradient_executes
#   - test_line_gradient_output
#

set -euo pipefail

################################################################################
# _TestColors.sh - Test suite for Colors.sh
################################################################################
#
# Test suite for Colors.sh color and gradient functions.
#
# Usage: ./_TestColors.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

source "${SCRIPT_DIR}/TestFramework.sh"
source "${SCRIPT_DIR}/Colors.sh"

################################################################################
# TEST: GRADIENT PRINT
################################################################################

test_gradient_print_executes() {
    local text="Test Line"
    __gradient_print__ "$text" 38 2 128 0 255 255 2>/dev/null
    assert_exit_code 0 $? "Should execute gradient print"
}

test_gradient_print_multiline() {
    local text=$'Line 1\nLine 2\nLine 3'
    __gradient_print__ "$text" 38 2 128 0 255 255 2>/dev/null
    assert_exit_code 0 $? "Should handle multiline text"
}

################################################################################
# TEST: LINE RGB
################################################################################

test_line_rgb_executes() {
    __line_rgb__ "Test message" 255 128 0 2>/dev/null
    assert_exit_code 0 $? "Should execute line RGB"
}

test_line_rgb_output() {
    local output=$(__line_rgb__ "Test" 255 0 0 2>&1)
    assert_contains "$output" "Test" "Should contain text"
}

################################################################################
# TEST: LINE GRADIENT
################################################################################

test_line_gradient_executes() {
    __line_gradient__ "Test gradient" 255 0 0 0 255 0 2>/dev/null
    assert_exit_code 0 $? "Should execute line gradient"
}

test_line_gradient_output() {
    local output=$(__line_gradient__ "Gradient" 255 0 0 0 0 255 2>&1)
    assert_contains "$output" "Gradient" "Should contain text"
}

################################################################################
# RUN TEST SUITE
################################################################################

run_test_suite "Colors - Gradient Print" \
    test_gradient_print_executes \
    test_gradient_print_multiline

run_test_suite "Colors - Line RGB" \
    test_line_rgb_executes \
    test_line_rgb_output

run_test_suite "Colors - Line Gradient" \
    test_line_gradient_executes \
    test_line_gradient_output

exit $?
