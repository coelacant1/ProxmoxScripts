#!/usr/bin/env python3
"""
LoggingCoverageCheck.py

Checks that all functions in Utilities/ scripts have logging statements.
Ensures every function can be debugged when errors occur.

Usage:
    python3 LoggingCoverageCheck.py
    
Exit codes:
    0 - All functions have logging
    1 - Some functions are missing logging
"""

import os
import re
import sys
from pathlib import Path

# Define which files should be checked and their logging function
UTILITY_FILES = {
    'ArgumentParser.sh': '__argparser_log__',
    'BulkOperations.sh': '__bulk_log__',
    'Colors.sh': '__color_log__',
    'Communication.sh': '__comm_log__',
    'Conversion.sh': '__convert_log__',
    'Network.sh': '__net_log__',
    'Prompts.sh': '__prompt_log__',
    'Operations.sh': '__api_log__',
    'Cluster.sh': '__query_log__',
    'RemoteExecution.sh': '__remoteexec_log__',
    'SSH.sh': '__ssh_log__',
    'StateManager.sh': '__state_log__',
}

# Functions that don't need logging (wrappers, simple helpers)
EXCLUDE_FUNCTIONS = {
    # Logging wrapper functions themselves
    '__argparser_log__',
    '__bulk_log__',
    '__color_log__',
    '__comm_log__',
    '__convert_log__',
    '__net_log__',
    '__prompt_log__',
    '__api_log__',
    '__query_log__',
    '__remoteexec_log__',
    '__ssh_log__',
    '__state_log__',
    # Simple inline wrappers that are logged by parent
    'vm_wrapper',
    'ct_wrapper',
}


def find_functions(content):
    """Find all function definitions in bash script."""
    # Match function definitions: function_name() {
    pattern = r'^([a-zA-Z_][a-zA-Z0-9_]*)\(\)\s*\{'
    functions = []
    
    lines = content.split('\n')
    for i, line in enumerate(lines):
        match = re.match(pattern, line)
        if match:
            func_name = match.group(1)
            functions.append((func_name, i))
    
    return functions


def get_function_body(lines, start_line, end_line):
    """Extract function body between start and end lines."""
    return '\n'.join(lines[start_line:end_line])


def has_logging(body, log_function):
    """Check if function body contains logging statements."""
    # Look for the logging function call
    return re.search(rf'{log_function}\s+', body) is not None


def check_file(filepath, log_function):
    """Check a single utility file for logging coverage."""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    lines = content.split('\n')
    functions = find_functions(content)
    
    # Find functions without logging
    unlogged = []
    
    for i, (func_name, start_line) in enumerate(functions):
        # Skip excluded functions
        if func_name in EXCLUDE_FUNCTIONS:
            continue
        
        # Find end of function (next function or EOF)
        if i + 1 < len(functions):
            end_line = functions[i + 1][1]
        else:
            end_line = len(lines)
        
        # Get function body
        body = get_function_body(lines, start_line, end_line)
        
        # Check for logging
        if not has_logging(body, log_function):
            unlogged.append((func_name, start_line + 1))  # +1 for human-readable line numbers
    
    return unlogged, len([f for f in functions if f[0] not in EXCLUDE_FUNCTIONS])


def main():
    """Main checking logic."""
    # Get the repository root
    script_dir = Path(__file__).parent
    repo_root = script_dir.parent
    utilities_dir = repo_root / 'Utilities'
    
    if not utilities_dir.exists():
        print(f"Error: Utilities directory not found at {utilities_dir}")
        return 1
    
    print("=" * 70)
    print("LOGGING COVERAGE CHECK - Utilities/")
    print("=" * 70)
    print()
    print("Checking that all functions have logging statements...")
    print()
    
    total_files_checked = 0
    total_functions = 0
    total_unlogged = 0
    files_with_issues = []
    
    # Check each utility file
    for filename, log_function in sorted(UTILITY_FILES.items()):
        filepath = utilities_dir / filename
        
        if not filepath.exists():
            print(f"{filename} - FILE NOT FOUND")
            continue
        
        total_files_checked += 1
        unlogged, func_count = check_file(filepath, log_function)
        total_functions += func_count
        
        if unlogged:
            total_unlogged += len(unlogged)
            files_with_issues.append(filename)
            print(f"{filename}")
            print(f"   Functions without logging: {len(unlogged)}/{func_count}")
            for func_name, line_num in unlogged:
                print(f"      Line {line_num:4d}: {func_name}()")
            print()
        else:
            print(f"{filename}")
            print(f"   All {func_count} functions have logging")
            print()
    
    # Summary
    print("=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"Files checked:              {total_files_checked}")
    print(f"Total functions:            {total_functions}")
    print(f"Functions with logging:     {total_functions - total_unlogged}")
    print(f"Functions without logging:  {total_unlogged}")
    print()
    
    if total_unlogged > 0:
        coverage = ((total_functions - total_unlogged) / total_functions) * 100
        print(f"Logging coverage: {coverage:.1f}%")
        print()
        print(f"FAILED: {total_unlogged} functions are missing logging")
        print()
        print("Files needing attention:")
        for filename in files_with_issues:
            print(f"  - {filename}")
        print()
        print("Add logging to these functions using the pattern:")
        print('  __<module>_log__ "DEBUG" "Function entry message"')
        print('  __<module>_log__ "ERROR" "Error description"')
        return 1
    else:
        print("SUCCESS: All utility functions have logging coverage!")
        print()
        print("This ensures:")
        print("  • Functions can be debugged when errors occur")
        print("  • Parameter values are visible in logs")
        print("  • Execution flow can be traced")
        print("  • Error conditions have context")
        return 0


if __name__ == '__main__':
    sys.exit(main())
