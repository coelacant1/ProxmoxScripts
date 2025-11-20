#!/bin/bash
#
# RunAllTests.sh
#
# Master test runner for all Proxmox Scripts utilities. Runs test suites
# with options for filtering, reporting, and categorization (unit/integration/special).
#
# Usage:
#   RunAllTests.sh
#   RunAllTests.sh --unit-only
#   RunAllTests.sh --verbose
#   RunAllTests.sh _TestOperations.sh
#   RunAllTests.sh --report junit --output ./reports
#   RunAllTests.sh --filter "network"
#   RunAllTests.sh --all
#   RunAllTests.sh --list
#
# Options:
#   -v, --verbose           Enable verbose test output
#   -s, --stop-on-failure   Stop execution on first test failure
#   -r, --report FORMAT     Generate test report (console, junit, json, markdown)
#   -o, --output DIR        Output directory for reports (default: ../test-reports)
#   -f, --filter PATTERN    Only run tests matching pattern
#   -l, --list              List all available test suites
#   -u, --unit-only         Run only unit tests (safest)
#   -i, --integration-only  Run only integration tests
#   -a, --all               Run all tests including special environment tests
#
# Notes:
#   - Unit tests can run anywhere (no external dependencies)
#   - Integration tests need Proxmox environment or use mocking
#   - Special tests need root, SSH, or remote nodes
#   - Automatically sets UTILITYPATH and SKIP_INSTALL_CHECKS
#   - Suppresses verbose logging by default (LOG_LEVEL=ERROR)
#
# Function Index:
#   - list_test_suites
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export UTILITYPATH="${SCRIPT_DIR}"

# Skip install checks in test environment
export SKIP_INSTALL_CHECKS=true

# Suppress verbose logging by default (tests can override)
export LOG_LEVEL="${LOG_LEVEL:-ERROR}"

source "${SCRIPT_DIR}/TestFramework.sh"

# Configuration
VERBOSE_TESTS=false
STOP_ON_FAILURE=false
GENERATE_REPORTS=false
REPORT_FORMAT="console"
REPORT_DIR="${SCRIPT_DIR}/../test-reports"

# Test files to run (categorized)
# Unit tests - can run anywhere
UNIT_TESTS=(
    "_TestArgumentParser.sh"
    "_TestColors.sh"
    "_TestCommunication.sh"
    "_TestConversion.sh"
    "_TestConfigManager.sh"
    "_TestDisplay.sh"
    "_TestMenu.sh"
    "_TestManualViewer.sh"
)

# Integration tests - need Proxmox environment or mocking
INTEGRATION_TESTS=(
    "_TestCluster.sh"
    "_TestDiscovery.sh"
    "_TestOperations.sh"
    "_TestNodeSelection.sh"
    "_TestProxmoxAPI.sh"
    "_TestIntegrationExample.sh"
    "_TestQueries.sh"
    "_TestBulkOperations.sh"
    "_TestStateManager.sh"
    "_TestNetwork.sh"
)

# Special environment tests
SPECIAL_TESTS=(
    "_TestPrompts.sh"    # Needs root
    "_TestSSH.sh"        # Needs SSH
    "_TestRemoteExec.sh" # Needs remote nodes
)

# Default: run unit + integration tests
TEST_FILES=("${UNIT_TESTS[@]}" "${INTEGRATION_TESTS[@]}")

################################################################################
# PARSE ARGUMENTS
################################################################################

list_test_suites() {
    echo "${BOLD}${BLUE}Available Test Suites:${NC}"
    echo ""
    echo "${BOLD}${GREEN}Unit Tests (Always Safe):${NC}"
    for test_file in "${UNIT_TESTS[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${test_file}" ]]; then
            local suite_name=$(grep -m 1 "run_test_suite" "${SCRIPT_DIR}/${test_file}" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || echo "No suite name")
            echo "  ${GREEN}✓${NC} ${test_file} - ${suite_name}"
        else
            echo "  ${RED}✗${NC} ${test_file} - ${DIM}Not found${NC}"
        fi
    done
    echo ""
    echo "${BOLD}${YELLOW}Integration Tests (Need Proxmox or Mocks):${NC}"
    for test_file in "${INTEGRATION_TESTS[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${test_file}" ]]; then
            local suite_name=$(grep -m 1 "run_test_suite" "${SCRIPT_DIR}/${test_file}" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || echo "No suite name")
            echo "  ${YELLOW}⚠${NC} ${test_file} - ${suite_name}"
        else
            echo "  ${RED}✗${NC} ${test_file} - ${DIM}Not found${NC}"
        fi
    done
    echo ""
    echo "${BOLD}${RED}Special Environment Tests:${NC}"
    for test_file in "${SPECIAL_TESTS[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${test_file}" ]]; then
            local suite_name=$(grep -m 1 "run_test_suite" "${SCRIPT_DIR}/${test_file}" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || echo "No suite name")
            echo "  ${RED}!${NC} ${test_file} - ${suite_name}"
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
RUN_MODE="default" # default, unit-only, integration-only, all

while [[ $# -gt 0 ]]; do
    case $1 in
        -v | --verbose)
            VERBOSE_TESTS=true
            export LOG_LEVEL="INFO"
            shift
            ;;
        -s | --stop-on-failure)
            STOP_ON_FAILURE=true
            shift
            ;;
        -r | --report)
            GENERATE_REPORTS=true
            REPORT_FORMAT="$2"
            shift 2
            ;;
        -o | --output)
            REPORT_DIR="$2"
            shift 2
            ;;
        -f | --filter)
            FILTER_PATTERN="$2"
            shift 2
            ;;
        -l | --list)
            LIST_ONLY=true
            shift
            ;;
        -u | --unit-only)
            RUN_MODE="unit-only"
            TEST_FILES=("${UNIT_TESTS[@]}")
            shift
            ;;
        -i | --integration-only)
            RUN_MODE="integration-only"
            TEST_FILES=("${INTEGRATION_TESTS[@]}")
            shift
            ;;
        -a | --all)
            RUN_MODE="all"
            TEST_FILES=("${UNIT_TESTS[@]}" "${INTEGRATION_TESTS[@]}" "${SPECIAL_TESTS[@]}")
            shift
            ;;
        -h | --help)
            # Show usage from header
            head -35 "$0" | grep -E "^#" | sed 's/^# //'
            exit 0
            ;;
        _Test*.sh)
            SELECTED_TESTS+=("$1")
            shift
            ;;
        *)
            echo "${RED}Error:${NC} Unknown option: $1"
            echo "Use --help for usage information"
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

# Print environment info
echo ""
echo "${BOLD}${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo "${BOLD}${BLUE}║${NC} ${BOLD}Proxmox Scripts - Test Suite Runner${NC}"
echo "${BOLD}${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${DIM}Environment:${NC}"
echo "  Hostname: $(hostname)"
echo "  Mode: $RUN_MODE"
echo "  SKIP_INSTALL_CHECKS: ${SKIP_INSTALL_CHECKS:-false}"
echo "  LOG_LEVEL: ${LOG_LEVEL:-INFO}"
echo ""

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

    ((TOTAL_SUITES += 1))

    # Reset test counters for this suite
    TEST_TOTAL=0
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_SKIPPED=0
    TEST_RESULTS=()
    FAILED_TESTS=()

    # Run the test file
    if bash "$test_path"; then
        ((PASSED_SUITES += 1))
    else
        ((FAILED_SUITES += 1))

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

