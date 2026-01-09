#!/bin/bash
#
# _RunChecks.sh
#
# Runs all repository validation checks in sequence.
# These checks ensure code quality, consistency, and proper structure.
#
# Usage:
#   ./_RunChecks.sh [OPTIONS]
#
# Options:
#   --skip-shellcheck    Skip running ShellCheck (faster)
#   --no-fix             Run checks in report-only mode (no auto-fixes)
#   --skip-format        Skip code formatting checks
#   --skip-security      Skip security analysis
#   --skip-deadcode      Skip dead code detection
#   --skip-cycles        Skip dependency cycle detection
#   --skip-docs          Skip documentation checks
#   --skip-errors        Skip error handling checks
#   --strict             Enable strict mode for all checks
#   --quick              Run only essential checks (line endings, function index, sources)
#   --verbose, -v        Show detailed output for all checks
#
# Checks performed:
#   1. Convert line endings (CRLF -> LF)
#   2. Update function indices in scripts
#   2b. Update utility documentation
#   2c. Validate script notes format
#   3. Verify source calls are correct
#   4. Format check (shfmt or basic)
#   5. Security check (shellharden or basic patterns)
#   6. Dead code detection
#   7. Dependency cycle detection
#   8. Documentation completeness
#   9. Error handling verification
#   10. Optional: ShellCheck on all scripts
#

# Parse arguments
SKIP_SHELLCHECK=false
NO_FIX=false
SKIP_FORMAT=false
SKIP_SECURITY=false
SKIP_DEADCODE=false
SKIP_CYCLES=false
SKIP_DOCS=false
SKIP_ERRORS=false
STRICT_MODE=false
QUICK_MODE=false
VERBOSE=false

for arg in "$@"; do
    case $arg in
        --skip-shellcheck)
            SKIP_SHELLCHECK=true
            ;;
        --no-fix)
            NO_FIX=true
            ;;
        --skip-format)
            SKIP_FORMAT=true
            ;;
        --skip-security)
            SKIP_SECURITY=true
            ;;
        --skip-deadcode)
            SKIP_DEADCODE=true
            ;;
        --skip-cycles)
            SKIP_CYCLES=true
            ;;
        --skip-docs)
            SKIP_DOCS=true
            ;;
        --skip-errors)
            SKIP_ERRORS=true
            ;;
        --strict)
            STRICT_MODE=true
            ;;
        --quick)
            QUICK_MODE=true
            SKIP_SHELLCHECK=true
            SKIP_FORMAT=true
            SKIP_SECURITY=true
            SKIP_DEADCODE=true
            SKIP_CYCLES=true
            SKIP_DOCS=true
            SKIP_ERRORS=true
            ;;
        --verbose|-v)
            VERBOSE=true
            ;;
        --help|-h)
            grep "^#" "$0" | grep -v "^#!/" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "================================================================================"
echo "-                  RUNNING REPOSITORY CHECKS"
echo "================================================================================"
echo ""

# Track results
CHECKS_RUN=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_RECOMMENDATIONS=0

# Check 1: Convert line endings
echo "1. Converting line endings (CRLF -> LF)..."
if python3 .check/ConvertLineEndings.py ./ >/dev/null 2>&1; then
    echo "- Line endings converted"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo "- FAILED: Line ending conversion"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi
CHECKS_RUN=$((CHECKS_RUN + 1))
echo ""

# Check 1a: Basic shell syntax validation
echo "1a. Validating shell syntax (bash -n)..."
SYNTAX_ERRORS=0
SYNTAX_FILES=()
while IFS= read -r -d '' file; do
    if ! bash -n "$file" 2>/dev/null; then
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        SYNTAX_FILES+=("$file")
    fi
done < <(find . -name "*.sh" -not -path "*/.git/*" -not -path "*/.check/*" -print0)

if [ $SYNTAX_ERRORS -eq 0 ]; then
    echo "- All shell scripts have valid syntax"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo "- FAILED: $SYNTAX_ERRORS file(s) with syntax errors"
    if [ "$VERBOSE" = true ] || [ $SYNTAX_ERRORS -le 5 ]; then
        for file in "${SYNTAX_FILES[@]}"; do
            echo "    $file"
            bash -n "$file" 2>&1 | head -3 | sed 's/^/      /'
        done
    fi
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi
CHECKS_RUN=$((CHECKS_RUN + 1))
echo ""

# Check 2: Update function indices
echo "2. Updating function indices..."
python3 .check/UpdateFunctionIndex.py ./ 2>&1 | tail -3
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "- Function indices updated"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo "- FAILED: Function index update"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi
CHECKS_RUN=$((CHECKS_RUN + 1))
echo ""

# Check 2b: Update utility documentation
echo "2b. Updating utility documentation..."
if python3 .check/UpdateUtilityDocumentation.py >/dev/null 2>&1; then
    echo "- Utility documentation updated"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
else
    echo "- FAILED: Utility documentation update"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi
CHECKS_RUN=$((CHECKS_RUN + 1))
echo ""

# Check 2c: Validate script notes format
echo "2c. Validating script notes format..."
if [ "$NO_FIX" = true ]; then
    # Dry-run mode
    set +e
    TEMP_OUTPUT=$(mktemp)
    python3 .check/ValidateScriptNotes.py ./ > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?
    set -e

    if [ "$VERBOSE" = true ]; then
        cat "$TEMP_OUTPUT"
    else
        # Show summary only
        sed -n '/^Scripts found:/p; /^Summary/,/^  ✓/p' "$TEMP_OUTPUT"
    fi

    if [ $EXIT_CODE -eq 0 ]; then
        echo "- Script notes validated"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "- Script notes issues found (run without --no-fix to auto-fix)"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi

    rm -f "$TEMP_OUTPUT"
else
    # Fix mode
    set +e
    TEMP_OUTPUT=$(mktemp)
    python3 .check/ValidateScriptNotes.py ./ --fix > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?
    set -e

    if [ "$VERBOSE" = true ]; then
        cat "$TEMP_OUTPUT"
    else
        # Show fixed files and summary
        grep -E "^✓|^Scripts found:|^Summary|^  ✓|^  ✗" "$TEMP_OUTPUT" || true
    fi

    echo "- Script notes validated and fixed"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))

    rm -f "$TEMP_OUTPUT"
fi
CHECKS_RUN=$((CHECKS_RUN + 1))
echo ""

# Check 3: Verify source calls
echo "3. Verifying source calls..."
if [ "$NO_FIX" = true ]; then
    if python3 .check/VerifySourceCalls.py >/dev/null 2>&1; then
        echo "- Source calls verified"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "- Source call issues found (run without --no-fix to auto-fix)"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
else
    # Run with automatic yes responses
    # Temporarily disable pipefail and errexit to handle SIGPIPE and non-zero exit from yes
    set +o pipefail
    set +e
    (yes 2>/dev/null || true) | python3 .check/VerifySourceCalls.py --fix >/dev/null 2>&1
    # Re-enable errexit and pipefail
    set -e
    set -o pipefail

    echo "- Source calls verified and fixed"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
fi
CHECKS_RUN=$((CHECKS_RUN + 1))
echo ""

# Check 4: Format check
if [ "$SKIP_FORMAT" = false ]; then
    echo "4. Checking code formatting..."
    set +e
    TEMP_OUTPUT=$(mktemp)
    python3 .check/FormatCheck.py ./ > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?
    set -e

    if [ "$VERBOSE" = true ]; then
        # Show full output in verbose mode
        cat "$TEMP_OUTPUT"
    else
        # Show summary lines only
        grep -E "^(WARNING:|Total files checked:|Files with formatting issues:|All files are properly formatted)" "$TEMP_OUTPUT" || true
    fi
    rm -f "$TEMP_OUTPUT"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "- Code formatting verified"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        if [ "$STRICT_MODE" = true ]; then
            echo "- FAILED: Formatting issues (strict mode)"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        else
            echo "- Formatting issues found (run with --fix to auto-fix)"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            CHECKS_RECOMMENDATIONS=$((CHECKS_RECOMMENDATIONS + 1))
        fi
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
    echo ""
else
    echo "4. Format check skipped"
    echo ""
fi

# Check 5: Security analysis
if [ "$SKIP_SECURITY" = false ]; then
    echo "5. Running security analysis..."
    # Clean Python cache to ensure latest version runs
    rm -rf .check/__pycache__ 2>/dev/null || true

    # Use temp file to avoid hanging with large output capture
    # Temporarily disable errexit to capture exit code
    set +e
    TEMP_OUTPUT=$(mktemp)
    python3 .check/SecurityCheck.py ./ > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?
    set -e

    # Show summary only, hide individual file checks
    if [ "$VERBOSE" = true ]; then
        # Show full output in verbose mode
        cat "$TEMP_OUTPUT"
    else
        # Show summary only
        sed -n '/^NOTE:/p; /^Note:/p; /^Scanning/p; /^=.*SUMMARY/,/^$/p' "$TEMP_OUTPUT"
    fi

    if [ $EXIT_CODE -eq 0 ]; then
        # Check if there are recommendations
        if grep -q "Files with security issues: 0" "$TEMP_OUTPUT"; then
            echo "- Security check passed"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
        else
            echo "- Security check passed (with recommendations)"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            CHECKS_RECOMMENDATIONS=$((CHECKS_RECOMMENDATIONS + 1))
        fi
    else
        if [ "$STRICT_MODE" = true ]; then
            echo "- FAILED: Critical security issues found"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        else
            echo "- FAILED: Security issues found"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        fi
    fi

    rm -f "$TEMP_OUTPUT"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    echo ""
else
    echo "5. Security check skipped"
    echo ""
fi

# Check 6: Dead code detection
if [ "$SKIP_DEADCODE" = false ]; then
    echo "6. Detecting dead code..."
    set +e
    TEMP_OUTPUT=$(mktemp)
    python3 .check/DeadCodeCheck.py ./ > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?
    set -e

    if [ "$VERBOSE" = true ]; then
        # Show full output in verbose mode
        cat "$TEMP_OUTPUT"
    else
        # Show summary only
        sed -n '/^Building/p; /^Analyzing/p; /^=.*SUMMARY/,/^$/p' "$TEMP_OUTPUT"
    fi
    rm -f "$TEMP_OUTPUT"

    echo "- Dead code check completed"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
    CHECKS_RUN=$((CHECKS_RUN + 1))
    echo ""
else
    echo "6. Dead code check skipped"
    echo ""
fi

# Check 7: Dependency cycles
if [ "$SKIP_CYCLES" = false ]; then
    echo "7. Checking for dependency cycles..."
    set +e
    TEMP_OUTPUT=$(mktemp)
    python3 .check/DependencyCycleCheck.py ./ > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?
    set -e

    if [ "$VERBOSE" = true ]; then
        # Show full output in verbose mode
        cat "$TEMP_OUTPUT"
    else
        # Show summary only
        sed -n '/^Building/p; /^Analyzed/p; /^\[OK\]/p; /^=.*SUMMARY/,/^$/p' "$TEMP_OUTPUT"
    fi
    rm -f "$TEMP_OUTPUT"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "- No dependency cycles found"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "- FAILED: Circular dependencies detected"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
    echo ""
else
    echo "7. Dependency cycle check skipped"
    echo ""
fi

# Check 8: Documentation completeness
if [ "$SKIP_DOCS" = false ]; then
    echo "8. Verifying documentation..."
    DOCS_CMD="python3 .check/DocumentationCheck.py ./"
    if [ "$STRICT_MODE" = true ]; then
        DOCS_CMD="$DOCS_CMD --strict"
    fi

    set +e
    TEMP_OUTPUT=$(mktemp)
    $DOCS_CMD > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?

    # Show summary only (hide individual file issues unless there are few or verbose)
    FILE_COUNT=$(grep "^\[DOC\]" "$TEMP_OUTPUT" 2>/dev/null | wc -l)
    set -e

    if [ "$VERBOSE" = true ]; then
        # Show full output in verbose mode
        cat "$TEMP_OUTPUT"
    elif [ "$FILE_COUNT" -lt 5 ]; then
        # Show all if only a few files
        sed -n '/^\[DOC\]/,/^$/p; /^=.*SUMMARY/,/^$/p' "$TEMP_OUTPUT"
    else
        # Just show summary if many files
        sed -n '/^=.*SUMMARY/,/^$/p' "$TEMP_OUTPUT"
    fi
    rm -f "$TEMP_OUTPUT"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "- Documentation verified"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        if [ "$STRICT_MODE" = true ]; then
            echo "- FAILED: Documentation issues (strict mode)"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        else
            echo "- Documentation check passed (with recommendations)"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            CHECKS_RECOMMENDATIONS=$((CHECKS_RECOMMENDATIONS + 1))
        fi
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
    echo ""
else
    echo "8. Documentation check skipped"
    echo ""
fi

# Check 9: Error handling
if [ "$SKIP_ERRORS" = false ]; then
    echo "9. Checking error handling..."
    ERROR_CMD="python3 .check/ErrorHandlingCheck.py ./"
    if [ "$STRICT_MODE" = true ]; then
        ERROR_CMD="$ERROR_CMD --strict"
    fi

    set +e
    TEMP_OUTPUT=$(mktemp)
    $ERROR_CMD > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?
    set -e

    if [ "$VERBOSE" = true ]; then
        # Show full output in verbose mode
        cat "$TEMP_OUTPUT"
    else
        # Show summary only
        sed -n '/^Analyzing/p; /^=.*SUMMARY/,/^$/p' "$TEMP_OUTPUT"
    fi
    rm -f "$TEMP_OUTPUT"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "- Error handling verified"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        if [ "$STRICT_MODE" = true ]; then
            echo "- FAILED: Error handling issues (strict mode)"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        else
            echo "- Error handling check passed (with recommendations)"
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            CHECKS_RECOMMENDATIONS=$((CHECKS_RECOMMENDATIONS + 1))
        fi
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
    echo ""
else
    echo "9. Error handling check skipped"
    echo ""
fi

# Check 10: ShellCheck (optional)
if [ "$SKIP_SHELLCHECK" = false ]; then
    echo "10. Running ShellCheck..."
    set +e
    TEMP_OUTPUT=$(mktemp)
    python3 .check/ShellCheck.py ./ > "$TEMP_OUTPUT" 2>&1
    EXIT_CODE=$?
    set -e
    # Show summary only
    sed -n '/^Checking/p; /^=.*SUMMARY/,/^$/p' "$TEMP_OUTPUT"
    rm -f "$TEMP_OUTPUT"

    if [ $EXIT_CODE -eq 0 ]; then
        echo "- ShellCheck completed"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "- ShellCheck found issues (informational)"
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
    echo ""
else
    echo "10. ShellCheck skipped"
    echo ""
fi

# Summary
echo "================================================================================"
echo "-                       CHECKS COMPLETE"
echo "================================================================================"
echo ""
echo "Summary:"
echo "  Total checks: $CHECKS_RUN"
echo "  Passed: $CHECKS_PASSED"
echo "  Failed: $CHECKS_FAILED"
if [ $CHECKS_RECOMMENDATIONS -gt 0 ]; then
    echo "  With recommendations: $CHECKS_RECOMMENDATIONS"
fi
echo ""

if [ $CHECKS_FAILED -gt 0 ]; then
    echo "Some checks failed. Please review the output above."
    exit 1
else
    if [ $CHECKS_RECOMMENDATIONS -gt 0 ]; then
        echo "All checks passed! ($CHECKS_RECOMMENDATIONS with recommendations for improvement)"
    else
        echo "All checks passed successfully!"
    fi
    exit 0
fi
