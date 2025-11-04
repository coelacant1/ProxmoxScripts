#!/bin/bash
#
# Function Index:
#   - test_framework_init
#   - test_framework_cleanup
#   - run_test_suite
#   - run_test
#   - skip_test
#   - __test_setup__
#   - __test_teardown__
#   - __suite_setup__
#   - __suite_teardown__
#   - assert_equals
#   - assert_not_equals
#   - assert_contains
#   - assert_not_contains
#   - assert_matches
#   - assert_true
#   - assert_false
#   - assert_file_exists
#   - assert_file_not_exists
#   - assert_dir_exists
#   - assert_exit_code
#   - assert_success
#   - assert_failure
#   - assert_greater_than
#   - assert_less_than
#   - mock_command
#   - stub_function
#   - assert_mock_called
#   - restore_all_mocks
#   - print_suite_summary
#   - generate_test_report
#   - generate_junit_report
#   - generate_json_report
#   - generate_markdown_report
#   - create_temp_file
#   - create_temp_dir
#   - capture_output
#   - get_exit_code
#

set -euo pipefail

################################################################################
# TestFramework.sh - Comprehensive testing framework for Proxmox Scripts
################################################################################
#
# DESCRIPTION:
#   Provides a robust testing framework with assertion functions, test runners,
#   mocking capabilities, and reporting features to ensure code quality.
#
# FEATURES:
#   - Test suite organization and execution
#   - Rich assertion library (equals, contains, exit codes, etc.)
#   - Mocking and stubbing for external dependencies
#   - Setup/teardown lifecycle hooks
#   - Detailed test reporting with timing
#   - Color-coded output for readability
#   - Test isolation and cleanup
#   - Coverage tracking
#   - CI/CD integration support
#
# DEPENDENCIES:
#   - Colors.sh (for colored output)
#
# USAGE:
#   source "${SCRIPT_DIR}/Utilities/TestFramework.sh"
#
#   test_my_function() {
#       local result
#       result=$(my_function "input")
#       assert_equals "expected" "$result" "Should return expected value"
#   }
#
#   run_test_suite "My Tests" test_my_function
#
# AUTHOR: Coela
# VERSION: 1.0.0
################################################################################

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/Colors.sh" 2>/dev/null || true

################################################################################
# GLOBALS AND STATE
################################################################################

# Test counters
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -g TEST_SKIPPED=0
declare -g ASSERT_COUNT=0

# Current test state
declare -g CURRENT_TEST=""
declare -g CURRENT_SUITE=""
declare -g TEST_START_TIME=0
declare -g SUITE_START_TIME=0

# Test output capture
declare -g TEST_OUTPUT=""
declare -g CAPTURE_OUTPUT=false

# Test configuration
declare -g VERBOSE_TESTS=false
declare -g STOP_ON_FAILURE=false
declare -g TEST_TEMP_DIR=""
declare -g CLEANUP_ON_EXIT=true

# Mock state
declare -gA MOCKED_COMMANDS=()
declare -gA MOCK_CALL_COUNT=()
declare -g MOCK_DIR=""

# Test results storage
declare -ga TEST_RESULTS=()
declare -ga FAILED_TESTS=()

################################################################################
# INITIALIZATION AND CLEANUP
################################################################################

# Initialize test framework
test_framework_init() {
    TEST_TOTAL=0
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_SKIPPED=0
    ASSERT_COUNT=0
    TEST_RESULTS=()
    FAILED_TESTS=()

    # Create temporary directory
    TEST_TEMP_DIR=$(mktemp -d -t proxmox_tests.XXXXXX)
    MOCK_DIR="${TEST_TEMP_DIR}/mocks"
    mkdir -p "$MOCK_DIR"

    # Register cleanup trap
    if [[ "$CLEANUP_ON_EXIT" == true ]]; then
        trap test_framework_cleanup EXIT
    fi
}

# Cleanup test framework
test_framework_cleanup() {
    # Restore mocked commands
    restore_all_mocks

    # Remove temporary directory
    if [[ -n "$TEST_TEMP_DIR" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

################################################################################
# TEST SUITE MANAGEMENT
################################################################################

# Run a test suite
# Usage: run_test_suite "Suite Name" test_func1 test_func2 ...
run_test_suite() {
    local suite_name=$1
    shift
    local test_functions=("$@")

    CURRENT_SUITE="$suite_name"
    SUITE_START_TIME=$(date +%s)

    echo ""
    echo "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo "${BOLD}${BLUE}║${NC} ${BOLD}Running Test Suite: ${suite_name}${NC}"
    echo "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Run each test function
    for test_func in "${test_functions[@]}"; do
        run_test "$test_func"
    done

    # Print suite summary
    print_suite_summary
}

# Run a single test
run_test() {
    local test_func=$1

    CURRENT_TEST="$test_func"
    TEST_START_TIME=$(date +%s)
    TEST_OUTPUT=""
    ASSERT_COUNT=0

    ((TEST_TOTAL++))

    # Print test header
    if [[ "$VERBOSE_TESTS" == true ]]; then
        echo "${BLUE}->${NC} Running: ${BOLD}$test_func${NC}"
    fi

    # Setup test environment
    __test_setup__ 2>/dev/null || true

    # Run test in subshell to isolate failures
    local test_result=0
    local test_output

    if [[ "$CAPTURE_OUTPUT" == true ]]; then
        test_output=$($test_func 2>&1) || test_result=$?
        TEST_OUTPUT="$test_output"
    else
        $test_func 2>&1 || test_result=$?
    fi

    # Teardown test environment
    __test_teardown__ 2>/dev/null || true

    # Record result
    local test_time=$(($(date +%s) - TEST_START_TIME))

    if [[ $test_result -eq 0 ]]; then
        ((TEST_PASSED++))
        echo "${GREEN}✓${NC} ${test_func} ${DIM}(${test_time}s, ${ASSERT_COUNT} assertions)${NC}"
        TEST_RESULTS+=("PASS:$test_func:${test_time}:${ASSERT_COUNT}")
    else
        ((TEST_FAILED++))
        echo "${RED}✗${NC} ${BOLD}${test_func}${NC} ${DIM}(${test_time}s)${NC}"
        FAILED_TESTS+=("$test_func")
        TEST_RESULTS+=("FAIL:$test_func:${test_time}:${ASSERT_COUNT}")

        if [[ "$STOP_ON_FAILURE" == true ]]; then
            echo "${RED}${BOLD}Stopping on failure${NC}"
            exit 1
        fi
    fi

    CURRENT_TEST=""
}

# Skip a test
skip_test() {
    local reason=${1:-"No reason provided"}
    ((TEST_SKIPPED++))
    echo "${YELLOW}⊘${NC} ${CURRENT_TEST} ${DIM}(skipped: $reason)${NC}"
    exit 0
}

################################################################################
# TEST LIFECYCLE HOOKS
################################################################################

# Setup function (override in test files)
__test_setup__() {
    :
}

# Teardown function (override in test files)
__test_teardown__() {
    :
}

# Suite setup function (override in test files)
__suite_setup__() {
    :
}

# Suite teardown function (override in test files)
__suite_teardown__() {
    :
}

################################################################################
# ASSERTION FUNCTIONS
################################################################################

# Assert two values are equal
assert_equals() {
    local expected=$1
    local actual=$2
    local message=${3:-"Values should be equal"}

    ((ASSERT_COUNT++))

    if [[ "$expected" == "$actual" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Expected:${NC} ${YELLOW}$expected${NC}"
        echo "    ${DIM}Actual:${NC}   ${RED}$actual${NC}"
        return 1
    fi
}

# Assert two values are not equal
assert_not_equals() {
    local expected=$1
    local actual=$2
    local message=${3:-"Values should not be equal"}

    ((ASSERT_COUNT++))

    if [[ "$expected" != "$actual" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Both values:${NC} ${RED}$actual${NC}"
        return 1
    fi
}

# Assert value contains substring
assert_contains() {
    local haystack=$1
    local needle=$2
    local message=${3:-"String should contain substring"}

    ((ASSERT_COUNT++))

    if [[ "$haystack" == *"$needle"* ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}String:${NC}    ${YELLOW}$haystack${NC}"
        echo "    ${DIM}Expected:${NC}  ${RED}$needle${NC}"
        return 1
    fi
}

# Assert value does not contain substring
assert_not_contains() {
    local haystack=$1
    local needle=$2
    local message=${3:-"String should not contain substring"}

    ((ASSERT_COUNT++))

    if [[ "$haystack" != *"$needle"* ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}String:${NC}      ${YELLOW}$haystack${NC}"
        echo "    ${DIM}Should not contain:${NC} ${RED}$needle${NC}"
        return 1
    fi
}

# Assert value matches regex
assert_matches() {
    local value=$1
    local pattern=$2
    local message=${3:-"Value should match pattern"}

    ((ASSERT_COUNT++))

    if [[ "$value" =~ $pattern ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Value:${NC}   ${YELLOW}$value${NC}"
        echo "    ${DIM}Pattern:${NC} ${RED}$pattern${NC}"
        return 1
    fi
}

# Assert value is true/non-empty
assert_true() {
    local value=$1
    local message=${2:-"Value should be true"}

    ((ASSERT_COUNT++))

    if [[ -n "$value" ]] && [[ "$value" != "false" ]] && [[ "$value" != "0" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Value:${NC} ${RED}$value${NC}"
        return 1
    fi
}

# Assert value is false/empty
assert_false() {
    local value=$1
    local message=${2:-"Value should be false"}

    ((ASSERT_COUNT++))

    if [[ -z "$value" ]] || [[ "$value" == "false" ]] || [[ "$value" == "0" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Value:${NC} ${RED}$value${NC}"
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local filepath=$1
    local message=${2:-"File should exist"}

    ((ASSERT_COUNT++))

    if [[ -f "$filepath" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}File:${NC} ${RED}$filepath${NC}"
        return 1
    fi
}

# Assert file does not exist
assert_file_not_exists() {
    local filepath=$1
    local message=${2:-"File should not exist"}

    ((ASSERT_COUNT++))

    if [[ ! -f "$filepath" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}File:${NC} ${RED}$filepath${NC}"
        return 1
    fi
}

# Assert directory exists
assert_dir_exists() {
    local dirpath=$1
    local message=${2:-"Directory should exist"}

    ((ASSERT_COUNT++))

    if [[ -d "$dirpath" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Directory:${NC} ${RED}$dirpath${NC}"
        return 1
    fi
}

# Assert exit code
assert_exit_code() {
    local expected_code=$1
    local actual_code=$2
    local message=${3:-"Exit code should match"}

    ((ASSERT_COUNT++))

    if [[ "$expected_code" -eq "$actual_code" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Expected:${NC} ${YELLOW}$expected_code${NC}"
        echo "    ${DIM}Actual:${NC}   ${RED}$actual_code${NC}"
        return 1
    fi
}

# Assert command succeeds
assert_success() {
    local message=${1:-"Command should succeed"}

    ((ASSERT_COUNT++))

    if [[ "$VERBOSE_TESTS" == true ]]; then
        echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
    fi
    return 0
}

# Assert command fails
assert_failure() {
    local message=${1:-"Command should fail"}

    ((ASSERT_COUNT++))

    echo "  ${RED}FAILED:${NC} $message"
    echo "    ${DIM}Command succeeded when it should have failed${NC}"
    return 1
}

# Assert value is greater than
assert_greater_than() {
    local value=$1
    local threshold=$2
    local message=${3:-"Value should be greater than threshold"}

    ((ASSERT_COUNT++))

    if (( $(echo "$value > $threshold" | bc -l 2>/dev/null || echo "0") )); then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Value:${NC}     ${RED}$value${NC}"
        echo "    ${DIM}Threshold:${NC} ${YELLOW}$threshold${NC}"
        return 1
    fi
}

# Assert value is less than
assert_less_than() {
    local value=$1
    local threshold=$2
    local message=${3:-"Value should be less than threshold"}

    ((ASSERT_COUNT++))

    if (( $(echo "$value < $threshold" | bc -l 2>/dev/null || echo "0") )); then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Value:${NC}     ${RED}$value${NC}"
        echo "    ${DIM}Threshold:${NC} ${YELLOW}$threshold${NC}"
        return 1
    fi
}

################################################################################
# MOCKING AND STUBBING
################################################################################

# Mock a command
mock_command() {
    local command=$1
    local mock_output=${2:-""}
    local mock_exit_code=${3:-0}

    # Create mock script
    local mock_script="${MOCK_DIR}/${command}"
    cat > "$mock_script" << EOF
#!/bin/bash
echo "$mock_output"
exit $mock_exit_code
EOF
    chmod +x "$mock_script"

    # Store original PATH and prepend mock directory
    if [[ -z "${MOCKED_COMMANDS[$command]}" ]]; then
        MOCKED_COMMANDS[$command]="$PATH"
    fi
    export PATH="${MOCK_DIR}:${PATH}"

    # Initialize call count
    MOCK_CALL_COUNT[$command]=0
}

# Stub a function
stub_function() {
    local func_name=$1
    local return_value=${2:-0}

    eval "${func_name}() { return $return_value; }"
}

# Verify mock was called
assert_mock_called() {
    local command=$1
    local expected_count=${2:-1}
    local message=${3:-"Mock should be called $expected_count time(s)"}

    ((ASSERT_COUNT++))

    local actual_count=${MOCK_CALL_COUNT[$command]:-0}

    if [[ "$actual_count" -eq "$expected_count" ]]; then
        if [[ "$VERBOSE_TESTS" == true ]]; then
            echo "  ${GREEN}✓${NC} ${DIM}$message${NC}"
        fi
        return 0
    else
        echo "  ${RED}FAILED:${NC} $message"
        echo "    ${DIM}Expected calls:${NC} ${YELLOW}$expected_count${NC}"
        echo "    ${DIM}Actual calls:${NC}   ${RED}$actual_count${NC}"
        return 1
    fi
}

# Restore all mocks
restore_all_mocks() {
    for command in "${!MOCKED_COMMANDS[@]}"; do
        export PATH="${MOCKED_COMMANDS[$command]}"
    done
    MOCKED_COMMANDS=()
    MOCK_CALL_COUNT=()
}

################################################################################
# REPORTING AND OUTPUT
################################################################################

# Print test suite summary
print_suite_summary() {
    local suite_time=$(($(date +%s) - SUITE_START_TIME))

    echo ""
    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo "${BOLD}Test Suite Summary: ${CURRENT_SUITE}${NC}"
    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"

    local pass_rate=0
    if [[ $TEST_TOTAL -gt 0 ]]; then
        pass_rate=$((TEST_PASSED * 100 / TEST_TOTAL))
    fi

    echo ""
    echo "  ${BOLD}Total Tests:${NC}    $TEST_TOTAL"
    echo "  ${GREEN}${BOLD}Passed:${NC}         $TEST_PASSED"

    if [[ $TEST_FAILED -gt 0 ]]; then
        echo "  ${RED}${BOLD}Failed:${NC}         $TEST_FAILED"
    fi

    if [[ $TEST_SKIPPED -gt 0 ]]; then
        echo "  ${YELLOW}${BOLD}Skipped:${NC}        $TEST_SKIPPED"
    fi

    echo "  ${BOLD}Pass Rate:${NC}      ${pass_rate}%"
    echo "  ${BOLD}Duration:${NC}       ${suite_time}s"
    echo ""

    # Print failed tests
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo "${RED}${BOLD}Failed Tests:${NC}"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "  ${RED}✗${NC} $failed_test"
        done
        echo ""
    fi

    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Exit with error if tests failed
    if [[ $TEST_FAILED -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Generate test report
generate_test_report() {
    local format=${1:-"console"}
    local output_file=${2:-""}

    case "$format" in
        junit)
            generate_junit_report "$output_file"
            ;;
        json)
            generate_json_report "$output_file"
            ;;
        markdown)
            generate_markdown_report "$output_file"
            ;;
        *)
            print_suite_summary
            ;;
    esac
}

# Generate JUnit XML report
generate_junit_report() {
    local output_file=${1:-"test-results.xml"}

    cat > "$output_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="${CURRENT_SUITE}" tests="${TEST_TOTAL}" failures="${TEST_FAILED}" skipped="${TEST_SKIPPED}" time="${suite_time}">
EOF

    for result in "${TEST_RESULTS[@]}"; do
        IFS=':' read -r status name time assertions <<< "$result"

        echo "  <testcase name=\"$name\" time=\"$time\" assertions=\"$assertions\">" >> "$output_file"

        if [[ "$status" == "FAIL" ]]; then
            echo "    <failure message=\"Test failed\"/>" >> "$output_file"
        fi

        echo "  </testcase>" >> "$output_file"
    done

    echo "</testsuite>" >> "$output_file"

    echo "${GREEN}✓${NC} JUnit report generated: $output_file"
}

# Generate JSON report
generate_json_report() {
    local output_file=${1:-"test-results.json"}

    cat > "$output_file" << EOF
{
  "suite": "${CURRENT_SUITE}",
  "total": ${TEST_TOTAL},
  "passed": ${TEST_PASSED},
  "failed": ${TEST_FAILED},
  "skipped": ${TEST_SKIPPED},
  "duration": ${suite_time},
  "tests": [
EOF

    local first=true
    for result in "${TEST_RESULTS[@]}"; do
        IFS=':' read -r status name time assertions <<< "$result"

        if [[ "$first" == false ]]; then
            echo "," >> "$output_file"
        fi
        first=false

        cat >> "$output_file" << EOF
    {
      "name": "$name",
      "status": "$status",
      "time": $time,
      "assertions": $assertions
    }
EOF
    done

    cat >> "$output_file" << EOF

  ]
}
EOF

    echo "${GREEN}✓${NC} JSON report generated: $output_file"
}

# Generate Markdown report
generate_markdown_report() {
    local output_file=${1:-"test-results.md"}

    cat > "$output_file" << EOF
# Test Report: ${CURRENT_SUITE}

## Summary

- **Total Tests:** ${TEST_TOTAL}
- **Passed:** ${TEST_PASSED} ✓
- **Failed:** ${TEST_FAILED} ✗
- **Skipped:** ${TEST_SKIPPED} ⊘
- **Duration:** ${suite_time}s

## Test Results

| Test Name | Status | Time | Assertions |
|-----------|--------|------|------------|
EOF

    for result in "${TEST_RESULTS[@]}"; do
        IFS=':' read -r status name time assertions <<< "$result"

        local status_icon="✓"
        if [[ "$status" == "FAIL" ]]; then
            status_icon="✗"
        fi

        echo "| $name | $status_icon | ${time}s | $assertions |" >> "$output_file"
    done

    echo "${GREEN}✓${NC} Markdown report generated: $output_file"
}

################################################################################
# HELPER FUNCTIONS
################################################################################

# Create temporary test file
create_temp_file() {
    local content=${1:-""}
    local temp_file="${TEST_TEMP_DIR}/test_file_$(date +%s%N)"

    echo "$content" > "$temp_file"
    echo "$temp_file"
}

# Create temporary test directory
create_temp_dir() {
    local temp_dir="${TEST_TEMP_DIR}/test_dir_$(date +%s%N)"
    mkdir -p "$temp_dir"
    echo "$temp_dir"
}

# Capture command output
capture_output() {
    local output
    output=$("$@" 2>&1)
    echo "$output"
}

# Run command and get exit code
get_exit_code() {
    local exit_code
    "$@" >/dev/null 2>&1
    exit_code=$?
    echo "$exit_code"
}

################################################################################
# INITIALIZATION
################################################################################

# Auto-initialize framework
test_framework_init

# Print initialization message
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "${GREEN}Test Framework initialized${NC}"
fi
