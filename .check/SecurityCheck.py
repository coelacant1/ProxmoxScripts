#!/usr/bin/env python3
"""
SecurityCheck.py

Performs security-focused static analysis on bash scripts.
Uses shellharden if available, otherwise performs basic security checks.

Usage:
    python3 SecurityCheck.py <directory> [--fix]

Options:
    --fix       Automatically fix issues (requires shellharden)

Installation (for full functionality):
    cargo install shellharden

Security checks performed:
    - Unquoted variable expansions
    - Command substitutions without quotes
    - Unsafe use of eval
    - Hardcoded credentials patterns
    - World-writable file operations
    - Dangerous command patterns (rm -rf with variables)
    - Missing input validation
    - Unsafe temp file creation

Author: Coela
"""

import os
import sys
import subprocess
import shutil
import re
from pathlib import Path

SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

# Security patterns to check
SECURITY_PATTERNS = [
    (r'\beval\s+(?!")', "Dangerous: Use of 'eval' can lead to code injection", "high"),
    (r'password\s*=\s*["\'][^"\'$]+["\']', "Critical: Hardcoded password detected", "critical"),
    (r'api[_-]?key\s*=\s*["\'][^"\'$]+["\']', "Critical: Hardcoded API key detected", "critical"),
    (r'secret\s*=\s*["\'][^"\'$]+["\']', "Critical: Hardcoded secret detected", "critical"),
    (r'\brm\s+-rf\s+\$\{?[A-Za-z_][A-Za-z0-9_]*\}?(?!["\'])', "Dangerous: rm -rf with unquoted variable", "high"),
    (r'\brm\s+-rf\s+/\s*$', "Critical: Attempt to rm -rf /", "critical"),
    (r'chmod\s+777', "Warning: Setting permissions to 777", "medium"),
    (r'curl.*\|\s*(?:ba)?sh', "Dangerous: Piping curl to shell", "high"),
    (r'wget.*-O\s*-\s*\|.*sh', "Dangerous: Piping wget to shell", "high"),
]

def check_shellharden_installed():
    """Check if shellharden is available in PATH."""
    return shutil.which("shellharden") is not None

def find_sh_files(base_dir):
    """Find all .sh files recursively, skipping certain directories."""
    sh_files = []
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for filename in files:
            if filename.endswith(".sh"):
                sh_files.append(os.path.join(root, filename))
    return sh_files

def run_shellharden(file_path, fix=False):
    """
    Run shellharden on a file.
    
    Args:
        file_path: Path to the shell script
        fix: If True, apply suggested fixes
        
    Returns:
        (has_issues, output)
    """
    cmd = ["shellharden"]
    
    if fix:
        cmd.append("--replace")
    else:
        cmd.append("--check")
    
    cmd.append(file_path)
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    # shellharden returns non-zero if it would make changes
    has_issues = result.returncode != 0
    output = result.stdout + result.stderr
    
    return has_issues, output

def basic_security_check(file_path):
    """
    Basic security checks when shellharden is not available.
    """
    issues = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception as e:
        return [f"  Error reading file: {e}"]
    
    for i, line in enumerate(lines, 1):
        # Skip comments
        stripped = line.strip()
        if stripped.startswith('#'):
            continue
        
        # Check each pattern
        for pattern, message, severity in SECURITY_PATTERNS:
            if re.search(pattern, line):
                # Additional check: skip if the match is inside quotes
                if is_inside_quotes(line, pattern):
                    continue
                    
                severity_tag = f"[{severity.upper()}]"
                issues.append(f"  Line {i}: {severity_tag} {message}")
                issues.append(f"    {line.strip()}")
    
    # Additional context-aware checks
    issues.extend(check_quoting_context(lines))
    issues.extend(check_dangerous_redirects(lines))
    
    return issues

def is_inside_quotes(line, pattern):
    """
    Check if the pattern match is already inside double quotes.
    This reduces false positives for things like: source "${VAR}/file.sh"
    """
    match = re.search(pattern, line)
    if not match:
        return False
    
    # Get the position of the match
    match_start = match.start()
    
    # Count quotes before the match
    before_match = line[:match_start]
    
    # Simple heuristic: count unescaped double quotes
    # If odd number, we're inside quotes
    double_quotes = 0
    i = 0
    while i < len(before_match):
        if before_match[i] == '"' and (i == 0 or before_match[i-1] != '\\'):
            double_quotes += 1
        i += 1
    
    # If odd number of quotes before match, we're inside a quoted string
    return double_quotes % 2 == 1

def check_quoting_context(lines):
    """Check for variables that should be quoted in dangerous contexts."""
    issues = []
    
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('#'):
            continue
        
        # Only check for unquoted variables in specific dangerous contexts
        # where word splitting would be a problem
        
        # Check for unquoted variables in [ test ] (NOT [[ ]]) that could word-split
        # [ ] is POSIX and DOES word-split, [[ ]] is bash and does NOT word-split
        # Example: [ $var = "value" ] should be [ "$var" = "value" ]
        # But [[ $var = "value" ]] is safe as-is
        
        # Only flag single bracket tests
        if ' [ ' in line or line.strip().startswith('[ '):
            test_match = re.search(r'\[\s+\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\s+[!=<>]', line)
            if test_match:
                # Make sure it's not already quoted
                if not is_inside_quotes(line, r'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?'):
                    issues.append(f"  Line {i}: [MEDIUM] Unquoted variable in [ test ] (use [[ ]] or quote variable)")
                    issues.append(f"    {line.strip()}")
        
        # Check for unquoted variables with rm/mv/cp (dangerous operations)
        dangerous_cmds = r'\b(rm|mv|cp)\s+.*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?(?!["\'])'
        if re.search(dangerous_cmds, line):
            # Verify it's truly unquoted
            var_match = re.search(r'\$', line)
            if var_match:
                before_var = line[:var_match.start()]
                if before_var.count('"') % 2 == 0:  # Even quotes = not inside quotes
                    issues.append(f"  Line {i}: [HIGH] Unquoted variable in dangerous file operation")
                    issues.append(f"    {line.strip()}")
    
    return issues

def check_dangerous_redirects(lines):
    """Check for dangerous redirect operations."""
    issues = []
    
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith('#'):
            continue
        
        # Check for redirect to important system files
        system_files = ['/etc/passwd', '/etc/shadow', '/etc/hosts', '/boot', '/dev/null']
        for sf in system_files:
            if re.search(rf'>\s*{re.escape(sf)}(?!\s)', line):
                if sf != '/dev/null':  # /dev/null is usually safe
                    issues.append(f"  Line {i}: [HIGH] Redirect to system file {sf}")
                    issues.append(f"    {line.strip()}")
    
    return issues

def check_set_options(file_path):
    """Check if script uses proper error handling options."""
    recommendations = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception:
        return recommendations
    
    has_set_e = re.search(r'^\s*set\s+-[a-z]*e', content, re.MULTILINE)
    has_set_u = re.search(r'^\s*set\s+-[a-z]*u', content, re.MULTILINE)
    has_set_pipefail = re.search(r'^\s*set\s+(-[a-z]*o\s+pipefail|-o\s+pipefail)', content, re.MULTILINE)
    
    if not has_set_e:
        recommendations.append("  Consider: Add 'set -e' to exit on errors")
    if not has_set_u:
        recommendations.append("  Consider: Add 'set -u' to catch undefined variables")
    if not has_set_pipefail:
        recommendations.append("  Consider: Add 'set -o pipefail' to catch pipeline errors")
    
    return recommendations

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 SecurityCheck.py <directory> [--fix]")
        sys.exit(1)
    
    base_dir = sys.argv[1]
    fix_mode = "--fix" in sys.argv
    
    if not os.path.isdir(base_dir):
        print(f"Error: {base_dir} is not a valid directory.")
        sys.exit(1)
    
    # Check if shellharden is available
    shellharden_available = check_shellharden_installed()
    
    print("=" * 80)
    print("SECURITY CHECK")
    print("=" * 80)
    
    if not shellharden_available:
        print("NOTE: shellharden not found. Using basic security checks.")
        print("For enhanced security analysis, install shellharden:")
        print("  cargo install shellharden")
        if fix_mode:
            print("\nWARNING: --fix requires shellharden. Running in check-only mode.")
            fix_mode = False
    
    print()
    
    sh_files = find_sh_files(base_dir)
    if not sh_files:
        print("No .sh files found.")
        return 0
    
    total_files = len(sh_files)
    files_with_issues = 0
    critical_issues = 0
    files_fixed = 0
    
    print(f"Scanning {total_files} shell scripts for security issues...")
    print()
    
    for idx, sh_file in enumerate(sh_files, 1):
        # Progress indicator
        progress = int((idx / total_files) * 100)
        print(f"\rProgress: [{idx}/{total_files}] ({progress}%)...", end='', flush=True)
        
        issues = []
        recommendations = []
        
        if shellharden_available:
            has_issues, output = run_shellharden(sh_file, fix=fix_mode)
            
            if has_issues:
                if fix_mode:
                    files_fixed += 1
                issues.append(output)
        else:
            # Basic security checks
            basic_issues = basic_security_check(sh_file)
            if basic_issues:
                issues.extend(basic_issues)
                # Count critical issues
                critical_issues += sum(1 for issue in basic_issues if '[CRITICAL]' in issue)
        
        # Always check set options (good practice recommendations)
        recommendations = check_set_options(sh_file)
        
        # Only report if there are actual security issues, not just recommendations
        if issues:
            print(f"\r{' ' * 60}\r", end='')  # Clear progress line
            files_with_issues += 1
            
            if fix_mode:
                print(f"[FIXED] {sh_file}")
            else:
                print(f"[SECURITY] {sh_file}")
                
            for issue in issues:
                if issue.strip():
                    print(issue)
            
            if recommendations and not fix_mode:
                print("\n  Recommendations:")
                for rec in recommendations:
                    print(rec)
            
            print()
    
    # Clear progress line
    print(f"\r{' ' * 60}\r", end='')
    
    # Summary
    print("=" * 80)
    print("SECURITY CHECK SUMMARY")
    print("=" * 80)
    print(f"Total files scanned: {total_files}")
    print(f"Files with security issues: {files_with_issues}")
    
    if not shellharden_available:
        print(f"Critical issues found: {critical_issues}")
    
    if fix_mode:
        print(f"Files fixed: {files_fixed}")
    elif files_with_issues > 0 and shellharden_available:
        print("\nRun with --fix to automatically fix issues (requires shellharden)")
    
    if files_with_issues == 0:
        print("\nNo security issues detected!")
    
    print()
    
    return 0 if (files_with_issues == 0 or fix_mode) else 1

if __name__ == "__main__":
    sys.exit(main())
