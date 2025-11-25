#!/usr/bin/env python3
"""
ErrorHandlingCheck.py

Verifies proper error handling in shell scripts.

Checks:
    - Use of set -e, set -u, set -o pipefail
    - Proper exit code handling
    - Error traps (trap ERR)
    - Command substitution with error checking
    - Critical commands followed by error checks
    - Functions return appropriate exit codes

Usage:
    python3 ErrorHandlingCheck.py <directory> [--strict]

Options:
    --strict    Require all error handling best practices

Error handling best practices:
    - set -e: Exit immediately on command failure
    - set -u: Treat unset variables as errors
    - set -o pipefail: Catch failures in pipelines
    - trap ERR: Execute function on error
    - Check exit codes: Test $? after critical commands
    - Return codes: Functions should return proper exit codes

Author: Coela
"""

import os
import sys
import re
from pathlib import Path
from collections import defaultdict

SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

# Patterns for error handling constructs
SET_E_REGEX = re.compile(r'^\s*set\s+-[a-z]*e', re.MULTILINE)
SET_U_REGEX = re.compile(r'^\s*set\s+-[a-z]*u', re.MULTILINE)
SET_PIPEFAIL_REGEX = re.compile(r'^\s*set\s+(-[a-z]*o\s+pipefail|-o\s+pipefail)', re.MULTILINE)
TRAP_ERR_REGEX = re.compile(r'^\s*trap\s+["\']?.*["\']?\s+ERR', re.MULTILINE)

# Critical commands that should have error checking
CRITICAL_COMMANDS = [
    'rm', 'mv', 'cp', 'dd', 'mkfs', 'fdisk', 'parted',
    'apt-get', 'apt', 'yum', 'dnf', 'systemctl',
    'pvecm', 'pvesh', 'qm', 'pct',
    'curl', 'wget', 'git', 'rsync'
]

# Function patterns
FUNC_DEF_REGEX = re.compile(r'^(?:function\s+)?([a-zA-Z_][a-zA-Z0-9_]*|__[a-zA-Z0-9_]+__)\s*\(\)\s*\{')
RETURN_REGEX = re.compile(r'^\s*return\s+(\d+|[\$\w]+)')
EXIT_REGEX = re.compile(r'^\s*exit\s+(\d+|[\$\w]+)')

def find_sh_files(base_dir):
    """Find all .sh files recursively."""
    sh_files = []
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for filename in files:
            if filename.endswith(".sh"):
                sh_files.append(os.path.join(root, filename))
    return sh_files

def check_set_options(file_path):
    """Check if script uses set -e, set -u, and set -o pipefail."""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception:
        return {}
    
    return {
        'has_set_e': bool(SET_E_REGEX.search(content)),
        'has_set_u': bool(SET_U_REGEX.search(content)),
        'has_set_pipefail': bool(SET_PIPEFAIL_REGEX.search(content)),
        'has_trap_err': bool(TRAP_ERR_REGEX.search(content)),
    }

def check_critical_commands(file_path):
    """
    Check if critical commands are followed by error checking.
    Returns list of lines with unchecked critical commands.
    """
    issues = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return issues
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Skip comments
        if stripped.startswith('#'):
            continue
        
        # Check for critical commands
        for cmd in CRITICAL_COMMANDS:
            # Look for command at start of line or after common prefixes
            pattern = rf'\b{re.escape(cmd)}\b'
            if re.search(pattern, stripped):
                # Check if it's in a conditional or has explicit error handling
                # Allow: if cmd; cmd || exit; cmd && next; $(cmd) checks
                has_error_handling = any([
                    stripped.startswith('if '),
                    ' || ' in stripped,
                    ' && ' in stripped,
                    stripped.endswith(' || \\'),
                    stripped.endswith(' && \\'),
                ])
                
                # Check next few lines for error checking
                if not has_error_handling and i + 1 < len(lines):
                    next_lines = ''.join(lines[i+1:min(i+4, len(lines))])
                    has_error_handling = any([
                        '$?' in next_lines,
                        'if [' in next_lines and '$?' in next_lines,
                        'test $?' in next_lines,
                    ])
                
                if not has_error_handling:
                    # Check if we're inside a function with set -e
                    # (if set -e is present, we can be more lenient)
                    issues.append((i + 1, stripped, cmd))
    
    return issues

def analyze_function_returns(file_path):
    """
    Analyze functions to see if they properly return exit codes.
    """
    issues = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return issues
    
    current_function = None
    function_start = 0
    brace_depth = 0
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Check for function definition
        func_match = FUNC_DEF_REGEX.match(stripped)
        if func_match:
            current_function = func_match.group(1)
            function_start = i
            brace_depth = 1
            continue
        
        if current_function:
            # Track brace depth
            brace_depth += stripped.count('{') - stripped.count('}')
            
            # If we're back to depth 0, function ended
            if brace_depth == 0:
                # Check if function has explicit return statement
                func_lines = lines[function_start:i+1]
                has_return = any(RETURN_REGEX.search(l) for l in func_lines)
                has_exit = any(EXIT_REGEX.search(l) for l in func_lines)
                
                # Functions should have return statements or use exit
                if not has_return and not has_exit and len(func_lines) > 5:
                    # Only flag if function is non-trivial
                    issues.append((function_start + 1, current_function, 
                                 "Function may not return proper exit code"))
                
                current_function = None
    
    return issues

def check_error_propagation(file_path):
    """
    Check if errors are properly propagated in command substitutions.
    """
    issues = []
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return issues
    
    for i, line in enumerate(lines):
        stripped = line.strip()
        
        # Skip comments
        if stripped.startswith('#'):
            continue
        
        # Look for command substitutions
        if '$(' in stripped or '`' in stripped:
            # Check if result is checked or if it's in a conditional
            has_check = any([
                stripped.startswith('if '),
                ' || ' in stripped,
                ' && ' in stripped,
                '|| exit' in stripped,
                '|| return' in stripped,
            ])
            
            # Check next line for error check
            if not has_check and i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                has_check = '$?' in next_line or 'if [' in next_line
            
            # Check if variable assignment is checked later
            var_match = re.match(r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$\(', stripped)
            if var_match and not has_check:
                var_name = var_match.group(1)
                # Look ahead a few lines for usage check
                check_range = lines[i+1:min(i+10, len(lines))]
                checks_var = any(
                    f'${var_name}' in l and ('||' in l or '&&' in l or 'if' in l)
                    for l in check_range
                )
                
                if not checks_var:
                    issues.append((i + 1, stripped, 
                                 "Command substitution result not checked"))
    
    return issues

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 ErrorHandlingCheck.py <directory> [--strict]")
        sys.exit(1)
    
    base_dir = sys.argv[1]
    strict_mode = "--strict" in sys.argv
    
    if not os.path.isdir(base_dir):
        print(f"Error: {base_dir} is not a valid directory.")
        sys.exit(1)
    
    print("=" * 80)
    print("ERROR HANDLING CHECK")
    if strict_mode:
        print("(Strict Mode)")
    print("=" * 80)
    print()
    
    sh_files = find_sh_files(base_dir)
    
    if not sh_files:
        print("No .sh files found.")
        return 0
    
    total_files = len(sh_files)
    files_with_issues = 0
    
    stats = {
        'no_set_e': 0,
        'no_set_u': 0,
        'no_pipefail': 0,
        'no_trap': 0,
        'unchecked_commands': 0,
        'function_returns': 0,
        'error_propagation': 0,
    }
    
    print(f"Analyzing error handling in {total_files} scripts...")
    print()
    
    for idx, file_path in enumerate(sh_files, 1):
        # Progress
        progress = int((idx / total_files) * 100)
        print(f"\rProgress: [{idx}/{total_files}] ({progress}%)...", end='', flush=True)
        
        issues = []
        
        # Check set options
        set_opts = check_set_options(file_path)
        
        if not set_opts['has_set_e']:
            issues.append("Missing 'set -e' (exit on error)")
            stats['no_set_e'] += 1
        
        if strict_mode and not set_opts['has_set_u']:
            issues.append("Missing 'set -u' (treat unset vars as error)")
            stats['no_set_u'] += 1
        
        if strict_mode and not set_opts['has_set_pipefail']:
            issues.append("Missing 'set -o pipefail' (catch pipeline failures)")
            stats['no_pipefail'] += 1
        
        if strict_mode and not set_opts['has_trap_err']:
            issues.append("No error trap defined (trap ERR)")
            stats['no_trap'] += 1
        
        # Check critical commands (only if set -e is not present)
        if not set_opts['has_set_e'] or strict_mode:
            critical_issues = check_critical_commands(file_path)
            if critical_issues:
                stats['unchecked_commands'] += len(critical_issues)
                issues.append(f"{len(critical_issues)} critical command(s) without error checking")
        
        # Check function returns
        if strict_mode:
            func_issues = analyze_function_returns(file_path)
            if func_issues:
                stats['function_returns'] += len(func_issues)
                issues.append(f"{len(func_issues)} function(s) may not return proper exit codes")
        
        # Check error propagation
        if strict_mode:
            prop_issues = check_error_propagation(file_path)
            if prop_issues:
                stats['error_propagation'] += len(prop_issues)
                issues.append(f"{len(prop_issues)} command substitution(s) not checked")
        
        # Report issues
        if issues:
            print(f"\r{' ' * 60}\r", end='')  # Clear progress
            files_with_issues += 1
            
            print(f"[ERROR HANDLING] {file_path}")
            for issue in issues:
                print(f"  {issue}")
            
            # Show some examples of unchecked commands
            if not set_opts['has_set_e'] or strict_mode:
                critical_issues = check_critical_commands(file_path)
                if critical_issues and len(critical_issues) <= 3:
                    print("  Examples:")
                    for line_num, line_text, cmd in critical_issues[:3]:
                        print(f"    Line {line_num}: {line_text[:60]}...")
            
            print()
    
    # Clear progress
    print(f"\r{' ' * 60}\r", end='')
    
    # Summary
    print("=" * 80)
    print("ERROR HANDLING SUMMARY")
    print("=" * 80)
    print(f"Total files checked: {total_files}")
    print(f"Files with error handling issues: {files_with_issues}")
    print()
    print("Issue breakdown:")
    print(f"  Missing 'set -e': {stats['no_set_e']}")
    if strict_mode:
        print(f"  Missing 'set -u': {stats['no_set_u']}")
        print(f"  Missing 'set -o pipefail': {stats['no_pipefail']}")
        print(f"  No error trap: {stats['no_trap']}")
        print(f"  Functions without proper returns: {stats['function_returns']}")
        print(f"  Unchecked command substitutions: {stats['error_propagation']}")
    print(f"  Critical commands without checks: {stats['unchecked_commands']}")
    print()
    
    if files_with_issues > 0:
        print("Recommendations:")
        print("  - Add 'set -e' at the start of scripts to exit on errors")
        print("  - Add 'set -u' to catch undefined variable usage")
        print("  - Add 'set -o pipefail' to catch pipeline failures")
        print("  - Use '|| exit 1' or '|| return 1' after critical commands")
        print("  - Check exit codes: 'if [ $? -ne 0 ]; then ...'")
        print("  - Define error traps: 'trap error_handler ERR'")
        if not strict_mode:
            print("  - Use --strict for comprehensive error handling checks")
    else:
        print("All error handling checks passed!")
    
    print()
    
    return 0 if files_with_issues == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
