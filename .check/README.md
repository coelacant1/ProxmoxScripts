# Static Analysis Tools for ProxmoxScripts

This directory contains static analysis tools to ensure code quality, security, and consistency across all bash scripts in the repository.

## Automated Checks

The repository checks run automatically on:
- **Push to main branch** - Ensures all merged code passes quality checks
- **Pull requests** - Validates changes before merging
- **Manual trigger** - Can be run on-demand via GitHub Actions UI

View the workflow status on the [Actions tab](../../actions/workflows/checks.yml) of the repository.

## Dependencies

### Python Requirements
- **Python 3.x** (standard library only)
- No pip packages required
- All checks use built-in modules

### External Tools (Optional)
These tools enhance functionality but aren't strictly required. The GitHub Actions workflow installs them automatically.

- **shellcheck** - Shell script static analysis (apt-get install shellcheck)
- **shfmt** - Shell script formatting ([download](https://github.com/mvdan/sh/releases))
- **shellharden** - Enhanced security analysis ([download](https://github.com/anordal/shellharden/releases))

Each check script includes fallback logic when tools are unavailable.

## Quick Start

Run all checks:
```bash
./.check/_RunChecks.sh
```

Run checks without auto-fixing:
```bash
./.check/_RunChecks.sh --no-fix
```

Run only essential checks (fast):
```bash
./.check/_RunChecks.sh --quick
```

Run all checks in strict mode:
```bash
./.check/_RunChecks.sh --strict
```

## Available Checks

### 1. **ConvertLineEndings.py**
Converts Windows-style (CRLF) line endings to Unix-style (LF).

**Usage:**
```bash
python3 .check/ConvertLineEndings.py ./
```

**What it does:**
- Recursively scans all files
- Converts `\r\n` to `\n`
- Skips binary files and git directories

---

### 2. **UpdateFunctionIndex.py**
Maintains function index comments in script headers.

**Usage:**
```bash
python3 .check/UpdateFunctionIndex.py ./
```

**What it does:**
- Scans each script for function definitions
- Updates the "Function Index:" section in headers
- Keeps documentation synchronized with code

---

### 3. **VerifySourceCalls.py**
Verifies that function calls have corresponding source statements.

**Usage:**
```bash
python3 .check/VerifySourceCalls.py [--fix] [--dry-run]
```

**Options:**
- `--fix`: Automatically add missing source statements
- `--dry-run`: Report issues without making changes

**What it does:**
- Identifies function calls
- Checks if required utility files are sourced
- Detects unused source statements
- Can automatically fix missing sources

---

### 4. **FormatCheck.py**
Checks and fixes code formatting.

**Usage:**
```bash
python3 .check/FormatCheck.py ./ [--fix] [--diff]
```

**Options:**
- `--fix`: Automatically fix formatting issues
- `--diff`: Show formatting differences

**Requirements for full functionality:**
```bash
# Install shfmt (optional, falls back to basic checks)
go install mvdan.cc/sh/v3/cmd/shfmt@latest
```

**What it checks:**
- Consistent indentation (tabs)
- Binary operators at start of line
- Trailing whitespace
- Multiple consecutive blank lines
- Final newline

---

### 5. **SecurityCheck.py**
Performs security-focused static analysis.

**Usage:**
```bash
python3 .check/SecurityCheck.py ./ [--fix]
```

**Options:**
- `--fix`: Automatically fix issues (requires shellharden)

**Requirements for full functionality:**
```bash
# Install shellharden (optional, falls back to pattern matching)
cargo install shellharden
```

**What it checks:**
- Unquoted variable expansions
- Command substitutions without quotes
- Unsafe use of eval
- Hardcoded credentials patterns
- World-writable file operations
- Dangerous command patterns (rm -rf)
- Unsafe temp file creation
- Missing set options (set -e, set -u, set -o pipefail)

**Severity Levels:**
- **CRITICAL**: Hardcoded passwords/keys, `rm -rf /`
- **HIGH**: Dangerous eval, unprotected rm -rf
- **MEDIUM**: Unquoted variables, command substitutions
- **LOW**: Minor security considerations

---

### 6. **DeadCodeCheck.py**
Detects unused (dead) code.

**Usage:**
```bash
python3 .check/DeadCodeCheck.py ./ [--verbose]
```

**Options:**
- `--verbose`: Show detailed information

**What it detects:**
- Functions defined but never called
- Variables declared but never referenced
- Distinguishes between library and entry-point scripts

**Note:** Some findings may be false positives for:
- Functions/variables used dynamically
- Functions defined for future use
- Callback functions passed as parameters

---

### 7. **DependencyCycleCheck.py**
Detects circular dependencies in source statements.

**Usage:**
```bash
python3 .check/DependencyCycleCheck.py ./ [--verbose]
```

**Options:**
- `--verbose`: Show detailed dependency tree and statistics

**What it detects:**
- Circular source dependencies (A sources B, B sources C, C sources A)
- Uses Tarjan's algorithm for strongly connected components
- Visualizes dependency tree

**Why it matters:**
- Circular dependencies can cause infinite loops
- Makes initialization order unpredictable
- Creates difficult-to-debug issues

---

### 8. **DocumentationCheck.py**
Verifies documentation completeness.

**Usage:**
```bash
python3 .check/DocumentationCheck.py ./ [--strict]
```

**Options:**
- `--strict`: Require examples and stricter standards

**What it checks:**
- File header with description
- Usage information
- Function documentation comments
- Function Index accuracy
- Examples (in strict mode)

**Documentation standards:**
- Every script needs a header block
- Usage section with syntax
- Each function should have a brief description above it
- Function Index must match actual functions

---

### 9. **ErrorHandlingCheck.py**
Verifies proper error handling.

**Usage:**
```bash
python3 .check/ErrorHandlingCheck.py ./ [--strict]
```

**Options:**
- `--strict`: Require all error handling best practices

**What it checks:**
- Use of `set -e` (exit on error)
- Use of `set -u` (treat unset vars as error)
- Use of `set -o pipefail` (catch pipeline failures)
- Error traps (`trap ERR`)
- Critical commands followed by error checks
- Functions return proper exit codes (strict mode)
- Command substitution error propagation (strict mode)

**Critical commands monitored:**
- File operations: `rm`, `mv`, `cp`, `dd`
- Package managers: `apt`, `yum`, `dnf`
- System: `systemctl`, `fdisk`, `parted`
- Proxmox: `pvecm`, `pvesh`, `qm`, `pct`
- Network: `curl`, `wget`, `rsync`

---

### 10. **ShellCheck.py**
Runs ShellCheck static analysis.

**Usage:**
```bash
python3 .check/ShellCheck.py ./
```

**Requirements:**
```bash
# Install shellcheck
sudo apt install shellcheck  # Debian/Ubuntu
sudo pacman -S shellcheck    # Arch
brew install shellcheck      # macOS
```

**What it does:**
- Runs shellcheck on all .sh files
- Falls back to basic checks if shellcheck not installed
- Checks for common bash pitfalls

---

## The Main Runner: _RunChecks.sh

The `_RunChecks.sh` script orchestrates all checks.

**All Options:**
```bash
--skip-shellcheck    # Skip ShellCheck (faster)
--no-fix             # Report issues without auto-fixing
--skip-format        # Skip code formatting checks
--skip-security      # Skip security analysis
--skip-deadcode      # Skip dead code detection
--skip-cycles        # Skip dependency cycle detection
--skip-docs          # Skip documentation checks
--skip-errors        # Skip error handling checks
--strict             # Enable strict mode for all checks
--quick              # Run only essential checks
```

**Examples:**
```bash
# Quick check before commit
./.check/_RunChecks.sh --quick

# Full analysis with strict mode
./.check/_RunChecks.sh --strict

# Security and error handling only
./.check/_RunChecks.sh --quick --skip-format --skip-deadcode --skip-cycles --skip-docs

# Check everything except ShellCheck
./.check/_RunChecks.sh --skip-shellcheck
```

---

## Integration with CI/CD

The checks can be integrated into your CI/CD pipeline:

**.github/workflows/checks.yml example:**
```yaml
name: Code Quality Checks

on: [push, pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck python3
      
      - name: Run checks
        run: |
          cd .check
          ./_RunChecks.sh --no-fix --skip-format --skip-security
```

---

## Tool Installation Guide

### Optional: Install all enhancement tools

```bash
# ShellCheck (highly recommended)
sudo apt install shellcheck

# shfmt for advanced formatting
go install mvdan.cc/sh/v3/cmd/shfmt@latest

# shellharden for security fixes
cargo install shellharden
```

**Without these tools:** All checks still work with fallback implementations!

---

## Check Results Interpretation

### Exit Codes
- **0**: All checks passed
- **1**: Some checks failed (review output)

### Check Severity
- **FAILED**: Critical issue, must be fixed
- **Warning**: Issue found, review recommended
- **Info**: Informational, may be false positive

---

## Best Practices

1. **Run `--quick` before every commit**
   ```bash
   ./.check/_RunChecks.sh --quick
   ```

2. **Run full checks before pull requests**
   ```bash
   ./.check/_RunChecks.sh --strict
   ```

3. **Use `--no-fix` to see issues first**
   ```bash
   ./.check/_RunChecks.sh --no-fix
   ```

4. **Fix issues incrementally**
   - Start with critical issues (security, cycles)
   - Then format and documentation
   - Finally address dead code warnings

5. **Review auto-fixes before committing**
   ```bash
   git diff
   ```

---

## Troubleshooting

### "Permission denied"
```bash
chmod +x .check/*.py .check/_RunChecks.sh
```

### "ModuleNotFoundError"
All scripts use Python 3 standard library only. Ensure Python 3 is installed:
```bash
python3 --version
```

### False Positives
- **Dead code**: Functions used dynamically may be flagged
- **Security**: Template strings and intentional patterns may be flagged
- **Documentation**: Auto-generated or minimal scripts may need adjustments

Use skip flags to ignore specific checks if they're not applicable to your workflow.

---

## Contributing New Checks

To add a new check:

1. Create `NewCheck.py` in `.check/` directory
2. Follow the existing script structure (argparse, progress indicators)
3. Add to `_RunChecks.sh` with appropriate skip flag
4. Update this README
5. Test with `python3 .check/NewCheck.py ./`

---

## Summary Table

| Check | Purpose | Auto-Fix | Required Tools | Strict Mode |
|-------|---------|----------|----------------|-------------|
| ConvertLineEndings | CRLF -> LF | Yes | None | N/A |
| UpdateFunctionIndex | Sync function docs | Yes | None | N/A |
| VerifySourceCalls | Check dependencies | Yes | None | N/A |
| FormatCheck | Code style | Yes | shfmt (opt) | No |
| SecurityCheck | Security issues | Yes* | shellharden (opt) | No |
| DeadCodeCheck | Unused code | No | None | No |
| DependencyCycleCheck | Circular deps | No | None | No |
| DocumentationCheck | Doc completeness | No | None | Yes |
| ErrorHandlingCheck | Error handling | No | None | Yes |
| ShellCheck | Shell linting | No | shellcheck (opt) | No |

\* Requires shellharden for auto-fix
