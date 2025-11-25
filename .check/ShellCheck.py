#!/usr/bin/env python3
"""
ShellCheck.py

Runs ShellCheck on all .sh files in a directory tree, or falls back to
basic validation checks if ShellCheck is not installed.

Usage:
    python3 ShellCheck.py <directory>

Checks performed:
    - ShellCheck analysis (if available)
    - Shebang validation
    - Execute permission check

Skips:
    - .git, .github, .site, .check directories
    - This script itself

Author: Coela
"""

# Requires Shellcheck: https://github.com/koalaman/shellcheck#user-content-installing

import os
import sys
import subprocess
import shutil

# Directories to skip during traversal
SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

def find_sh_files(base_dir):
    """
    Recursively find all .sh files under base_dir, skipping certain directories.
    Returns a list of file paths.
    """
    sh_files = []
    for root, dirs, files in os.walk(base_dir):
        # Skip specified directories
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        
        for filename in files:
            # Skip this script itself
            if filename == "ShellCheck.py":
                continue
                
            if filename.endswith(".sh"):
                sh_files.append(os.path.join(root, filename))
    return sh_files

def run_shellcheck(file_path):
    """
    Runs ShellCheck on a given file path.
    Returns stdout, stderr, and the process return code.
    """
    result = subprocess.run(
        ["shellcheck", "-e", "SC1090", file_path],
        capture_output=True,
        text=True
    )
    return result.stdout, result.stderr, result.returncode

def naive_sh_check(file_path):
    """
    A very basic check that looks for a few common issues:
      - Missing or non-bash shebang.
      - File not marked as executable.
    Feel free to add more checks here as needed.
    """
    errors = []

    # 1. Check shebang in the first line
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        first_line = f.readline().strip()
        if not first_line.startswith("#!"):
            errors.append("Missing shebang (#!/bin/bash or similar) in first line.")
        elif "bash" not in first_line and "sh" not in first_line:
            errors.append(f"Shebang does not specify bash/sh: {first_line}")

    # 2. Check if file has execute permission
    if not os.access(file_path, os.X_OK):
        errors.append("File is not set as executable (chmod +x).")

    return errors

def main():
    if len(sys.argv) != 2:
        print("Usage: python ShellCheck.py <folder>")
        sys.exit(1)

    base_dir = sys.argv[1]
    if not os.path.isdir(base_dir):
        print(f"Error: {base_dir} is not a valid directory.")
        sys.exit(1)

    # Find all .sh files in the specified directory
    sh_files = find_sh_files(base_dir)
    if not sh_files:
        print("No .sh files found.")
        return

    # Check if ShellCheck is installed
    shellcheck_path = shutil.which("shellcheck")
    shellcheck_installed = shellcheck_path is not None

    # For each .sh file, either use ShellCheck or fallback checks
    for sh_file in sh_files:
        print(f"=== Checking file: {sh_file} ===")

        if shellcheck_installed:
            # Run ShellCheck
            stdout, stderr, returncode = run_shellcheck(sh_file)
            if returncode == 0:
                print("No issues found by ShellCheck.")
            else:
                # ShellCheck warnings/errors
                print("ShellCheck issues:")
                if stdout.strip():
                    print(stdout.strip())
                if stderr.strip():
                    print(stderr.strip())
        else:
            # Fallback: run naive checks
            errors = naive_sh_check(sh_file)
            if errors:
                print("Naive check found potential issues:")
                for err in errors:
                    print(f"  - {err}")

if __name__ == "__main__":
    main()
