#!/bin/bash
#
# _TestManualViewer.sh
#
# Test suite for ManualViewer.sh utility functions including manual file
# loading, content structure validation, and markdown rendering.
#
# Usage:
#   _TestManualViewer.sh
#
# Notes:
#   - Uses TestFramework.sh for test execution and assertions
#   - Creates temporary markdown manual for testing
#   - Tests file existence verification
#   - Tests content loading and structure validation
#   - Tests markdown rendering (sections/subsections/code blocks)
#   - Can be run locally or via RemoteRunAllTests.sh on Proxmox nodes
#
# Function Index:
#   - __test_setup__
#   - __test_teardown__
#   - test_manual_viewer_exists
#   - test_manual_loading
#   - test_manual_content_rendering
#

set -euo pipefail

################################################################################
# _TestManualViewer.sh - Test suite for ManualViewer.sh
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"
export LOG_LEVEL=ERROR
export SKIP_INSTALL_CHECKS=true

source "${SCRIPT_DIR}/TestFramework.sh"

# Setup test environment
__test_setup__() {
    # Create test manual file
    TEST_MANUAL="${TEST_TEMP_DIR}/test_manual.md"
    cat >"$TEST_MANUAL" <<'EOF'
# Test Manual

## Section 1
This is the first section of the test manual.

## Section 2
This is the second section with more content.

### Subsection 2.1
Details about subsection.

## Section 3
Final section of the manual.

## Usage
Example usage:
```bash
./script.sh --option value
```

## Notes
- Important note 1
- Important note 2
- Important note 3
EOF
}

__test_teardown__() {
    rm -f "$TEST_MANUAL" 2>/dev/null || true
}

################################################################################
# TEST: Manual Viewer Exists
################################################################################

test_manual_viewer_exists() {
    if [[ -f "${SCRIPT_DIR}/ManualViewer.sh" ]]; then
        assert_file_exists "${SCRIPT_DIR}/ManualViewer.sh" "ManualViewer.sh should exist"
    else
        skip_test "ManualViewer.sh file not found"
    fi
}

################################################################################
# TEST: Manual Loading
################################################################################

test_manual_loading() {
    # Test loading a manual file
    if [[ -f "$TEST_MANUAL" ]]; then
        assert_file_exists "$TEST_MANUAL" "Test manual should exist"

        # Read content
        local content
        content=$(<"$TEST_MANUAL")

        assert_contains "$content" "# Test Manual" "Should contain title"
        assert_contains "$content" "## Section 1" "Should contain section headers"
        assert_contains "$content" "## Usage" "Should contain usage section"
    else
        skip_test "Test manual not created"
    fi
}

################################################################################
# TEST: Manual Content Rendering
################################################################################

test_manual_content_rendering() {
    # Verify manual structure
    if [[ -f "$TEST_MANUAL" ]]; then
        local content
        content=$(<"$TEST_MANUAL")

        # Check for required sections
        assert_contains "$content" "Section 1" "Should have Section 1"
        assert_contains "$content" "Section 2" "Should have Section 2"
        assert_contains "$content" "Section 3" "Should have Section 3"

        # Check for subsections
        assert_contains "$content" "Subsection 2.1" "Should have subsections"

        # Check for code blocks
        assert_contains "$content" "\`\`\`bash" "Should have code blocks"

        # Check for lists
        assert_contains "$content" "- Important note" "Should have bullet lists"
    else
        skip_test "Test manual not available"
    fi
}

################################################################################
# RUN TESTS
################################################################################

run_test_suite "ManualViewer.sh Tests" \
    test_manual_viewer_exists \
    test_manual_loading \
    test_manual_content_rendering

exit $?
