#!/bin/bash
#
# Function Index:
#   - print_usage
#   - list_test_suites
#

set -euo pipefail

################################################################################
# RunAllTests.sh - Master test runner for all Proxmox Scripts utilities
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/TestFramework.sh"

# Configuration
VERBOSE_TESTS=false
STOP_ON_FAILURE=false
GENERATE_REPORTS=false
REPORT_FORMAT="console"
REPORT_DIR="${SCRIPT_DIR}/../test-reports"

# Test files to run
TEST_FILES=(
    "_TestArgumentParser.sh"
    "_TestColors.sh"
    "_TestCommunication.sh"
    "_TestConversion.sh"
    "_TestPrompts.sh"
    "_TestQueries.sh"
    "_TestSSH.sh"
    "_TestProxmoxAPI.sh"
    "_TestBulkOperations.sh"
    "_TestStateManager.sh"
    "_TestNetworkHelper.sh"
)

################################################################################
# PARSE ARGUMENTS
################################################################################

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [TEST_FILES...]

Run all or specific test suites for Proxmox Scripts utilities.

OPTIONS:
    -v, --verbose           Enable verbose test output
    -s, --stop-on-failure   Stop execution on first test failure
    -r, --report FORMAT     Generate test report (console, junit, json, markdown)
    -o, --output DIR        Output directory for reports (default: ../test-reports)
    -f, --filter PATTERN    Only run tests matching pattern
    -l, --list              List all available test suites
    -h, --help              Show this help message

EXAMPLES:
    # Run all tests
    ./RunAllTests.sh

    # Run with verbose output
    ./RunAllTests.sh -v

    # Run specific test file
    ./RunAllTests.sh _TestProxmoxAPI.sh

    # Generate JUnit report
    ./RunAllTests.sh -r junit -o ./reports

    # Run tests matching pattern
    ./RunAllTests.sh -f "network"

EOF
}

list_test_suites() {
    echo "${BOLD}${BLUE}Available Test Suites:${NC}"
    echo ""
    for test_file in "${TEST_FILES[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${test_file}" ]]; then
            local suite_name=$(grep -m 1 "run_test_suite" "${SCRIPT_DIR}/${test_file}" | sed -E 's/.*"([^"]+)".*/\1/')
            echo "  ${GREEN}✓${NC} ${test_file} - ${suite_name}"
        else
            echo "  ${RED}✗${NC} ${test_file} - ${DIM}Not found${NC}"
        fi
    done
    echo ""
}

# Parse command line arguments
FILTER_PATTERN=""
LIST_ONLY=false
SELECTED_TESTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE_TESTS=true
            shift
            ;;
        -s|--stop-on-failure)
            STOP_ON_FAILURE=true
            shift
            ;;
        -r|--report)
            GENERATE_REPORTS=true
            REPORT_FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            REPORT_DIR="$2"
            shift 2
            ;;
        -f|--filter)
            FILTER_PATTERN="$2"
            shift 2
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        _Test*.sh)
            SELECTED_TESTS+=("$1")
            shift
            ;;
        *)
            echo "${RED}Error:${NC} Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Handle list-only mode
if [[ "$LIST_ONLY" == true ]]; then
    list_test_suites
    exit 0
fi

################################################################################
# RUN TESTS
################################################################################

# Create report directory if needed
if [[ "$GENERATE_REPORTS" == true ]]; then
    mkdir -p "$REPORT_DIR"
fi

# Determine which tests to run
if [[ ${#SELECTED_TESTS[@]} -gt 0 ]]; then
    TESTS_TO_RUN=("${SELECTED_TESTS[@]}")
elif [[ -n "$FILTER_PATTERN" ]]; then
    TESTS_TO_RUN=()
    for test_file in "${TEST_FILES[@]}"; do
        if [[ "$test_file" == *"$FILTER_PATTERN"* ]]; then
            TESTS_TO_RUN+=("$test_file")
        fi
    done
else
    TESTS_TO_RUN=("${TEST_FILES[@]}")
fi

# Print header
echo ""
echo "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo "${BOLD}${BLUE}║${NC} ${BOLD}Proxmox Scripts - Test Suite Runner${NC}"
echo "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${DIM}Running ${#TESTS_TO_RUN[@]} test suite(s)...${NC}"
echo ""

# Track overall results
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
OVERALL_START_TIME=$(date +%s)

# Run each test suite
for test_file in "${TESTS_TO_RUN[@]}"; do
    test_path="${SCRIPT_DIR}/${test_file}"

    if [[ ! -f "$test_path" ]]; then
        echo "${YELLOW}⚠${NC} Skipping ${test_file} - File not found"
        continue
    fi

    ((TOTAL_SUITES++))

    # Reset test counters for this suite
    TEST_TOTAL=0
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_SKIPPED=0
    TEST_RESULTS=()
    FAILED_TESTS=()

    # Run the test file
    if bash "$test_path"; then
        ((PASSED_SUITES++))
    else
        ((FAILED_SUITES++))

        if [[ "$STOP_ON_FAILURE" == true ]]; then
            echo "${RED}${BOLD}Stopping on test suite failure${NC}"
            break
        fi
    fi

    # Generate report if requested
    if [[ "$GENERATE_REPORTS" == true ]]; then
        local report_name=$(basename "$test_file" .sh)
        generate_test_report "$REPORT_FORMAT" "${REPORT_DIR}/${report_name}.${REPORT_FORMAT}"
    fi
done

# Calculate overall duration
OVERALL_DURATION=$(($(date +%s) - OVERALL_START_TIME))

################################################################################
# PRINT OVERALL SUMMARY
################################################################################

echo ""
echo "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo "${BOLD}${BLUE}║${NC} ${BOLD}Overall Test Summary${NC}"
echo "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  ${BOLD}Total Suites:${NC}      $TOTAL_SUITES"
echo "  ${GREEN}${BOLD}Passed Suites:${NC}     $PASSED_SUITES"

if [[ $FAILED_SUITES -gt 0 ]]; then
    echo "  ${RED}${BOLD}Failed Suites:${NC}     $FAILED_SUITES"
fi

echo "  ${BOLD}Overall Duration:${NC}  ${OVERALL_DURATION}s"
echo ""

# Print report location if generated
if [[ "$GENERATE_REPORTS" == true ]]; then
    echo "${GREEN}✓${NC} Test reports generated in: ${REPORT_DIR}"
    echo ""
fi

# Exit with appropriate code
if [[ $FAILED_SUITES -gt 0 ]]; then
    echo "${RED}${BOLD}Some test suites failed${NC}"
    echo ""
    exit 1
else
    echo "${GREEN}${BOLD}All test suites passed!${NC}"
    echo ""
    exit 0
fi
