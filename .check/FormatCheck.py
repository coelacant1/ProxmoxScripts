#!/usr/bin/env python3
"""
FormatCheck.py

Checks and optionally fixes bash script formatting using shfmt.
Falls back to basic formatting checks if shfmt is not installed.

Usage:
    python3 FormatCheck.py <directory> [--fix] [--diff]

Options:
    --fix       Automatically fix formatting issues
    --diff      Show formatting differences

Installation (for full functionality):
    # Using Go
    go install mvdan.cc/sh/v3/cmd/shfmt@latest
    
    # Or download binary from:
    # https://github.com/mvdan/sh/releases

Formatting rules:
    - Indent with 4 spaces
    - Binary operators at start of line
    - Switch cases indented
    - Redirect operators preceded by space

Author: Coela
"""

import os
import sys
import subprocess
import shutil
from pathlib import Path

SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

def check_shfmt_installed():
    """Check if shfmt is available in PATH."""
    return shutil.which("shfmt") is not None

def find_sh_files(base_dir):
    """Find all .sh files recursively, skipping certain directories."""
    sh_files = []
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for filename in files:
            if filename.endswith(".sh"):
                sh_files.append(os.path.join(root, filename))
    return sh_files

def run_shfmt_check(file_path, fix=False, show_diff=False):
    """
    Run shfmt on a file.
    
    Args:
        file_path: Path to the shell script
        fix: If True, write corrected formatting back to file
        show_diff: If True, show the diff
        
    Returns:
        (has_issues, diff_output)
    """
    # shfmt flags: -i 4 (4 spaces), -bn (binary ops at start), -ci (switch case indent)
    cmd = ["shfmt", "-i", "4", "-bn", "-ci"]
    
    if show_diff:
        cmd.append("-d")
    
    if fix:
        cmd.extend(["-w", file_path])
    else:
        cmd.append(file_path)
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if fix:
        return result.returncode != 0, ""
    else:
        # In check mode, if output differs from input, file has issues
        if show_diff:
            return len(result.stdout) > 0, result.stdout
        else:
            with open(file_path, 'r') as f:
                original = f.read()
            return result.stdout != original, result.stdout

def basic_format_check(file_path):
    """
    Basic formatting checks when shfmt is not available.
    
    Checks:
        - Mixed tabs and spaces for indentation
        - Trailing whitespace
        - Multiple consecutive blank lines
        - Missing final newline
    """
    issues = []
    
    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    if not lines:
        return issues
    
    has_tabs = False
    has_spaces = False
    consecutive_blanks = 0
    
    for i, line in enumerate(lines, 1):
        # Check for mixed indentation
        if line.startswith('\t'):
            has_tabs = True
        elif line.startswith(' '):
            has_spaces = True
        
        # Check for trailing whitespace
        if line.rstrip('\n') != line.rstrip('\n').rstrip():
            issues.append(f"  Line {i}: Trailing whitespace")
        
        # Check for multiple consecutive blank lines
        if line.strip() == '':
            consecutive_blanks += 1
            if consecutive_blanks > 2:
                issues.append(f"  Line {i}: More than 2 consecutive blank lines")
        else:
            consecutive_blanks = 0
    
    # Check for mixed indentation
    if has_tabs and has_spaces:
        issues.append("  Mixed tabs and spaces for indentation")
    
    # Check for final newline
    if lines and not lines[-1].endswith('\n'):
        issues.append("  Missing final newline")
    
    return issues

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 FormatCheck.py <directory> [--fix] [--diff]")
        sys.exit(1)
    
    base_dir = sys.argv[1]
    fix_mode = "--fix" in sys.argv
    show_diff = "--diff" in sys.argv
    
    if not os.path.isdir(base_dir):
        print(f"Error: {base_dir} is not a valid directory.")
        sys.exit(1)
    
    # Check if shfmt is available
    shfmt_available = check_shfmt_installed()
    
    if not shfmt_available:
        print("=" * 80)
        print("WARNING: shfmt not found. Using basic formatting checks.")
        print("For full formatting support, install shfmt:")
        print("  go install mvdan.cc/sh/v3/cmd/shfmt@latest")
        print("=" * 80)
        print()
    
    sh_files = find_sh_files(base_dir)
    if not sh_files:
        print("No .sh files found.")
        return
    
    total_files = len(sh_files)
    files_with_issues = 0
    files_fixed = 0
    
    print(f"Checking {total_files} shell scripts...")
    print()
    
    for idx, sh_file in enumerate(sh_files, 1):
        # Progress indicator
        progress = int((idx / total_files) * 100)
        print(f"\rProgress: [{idx}/{total_files}] ({progress}%)...", end='', flush=True)
        
        if shfmt_available:
            has_issues, output = run_shfmt_check(sh_file, fix=fix_mode, show_diff=show_diff)
            
            if has_issues:
                print(f"\r{' ' * 60}\r", end='')  # Clear progress line
                files_with_issues += 1
                
                if fix_mode:
                    print(f"[FIXED] {sh_file}")
                    files_fixed += 1
                elif show_diff and output:
                    print(f"[FORMAT] {sh_file}")
                    print(output)
                else:
                    print(f"[FORMAT] {sh_file}")
        else:
            # Basic checks
            issues = basic_format_check(sh_file)
            
            if issues:
                print(f"\r{' ' * 60}\r", end='')  # Clear progress line
                files_with_issues += 1
                print(f"[FORMAT] {sh_file}")
                for issue in issues:
                    print(issue)
                print()
    
    # Clear progress line
    print(f"\r{' ' * 60}\r", end='')
    
    # Summary
    print("=" * 80)
    print("FORMATTING CHECK SUMMARY")
    print("=" * 80)
    print(f"Total files checked: {total_files}")
    print(f"Files with formatting issues: {files_with_issues}")
    
    if fix_mode:
        print(f"Files fixed: {files_fixed}")
    elif files_with_issues > 0:
        print("\nRun with --fix to automatically fix formatting issues")
        print("Run with --diff to see detailed differences")
    
    if files_with_issues == 0:
        print("\nAll files are properly formatted!")
    
    print()
    
    return 0 if files_with_issues == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
