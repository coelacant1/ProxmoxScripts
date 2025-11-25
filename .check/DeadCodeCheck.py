#!/usr/bin/env python3
"""
DeadCodeCheck.py

Detects unused (dead) code in shell scripts:
- Functions defined but never called
- Sourced utilities that are never used
- Variables declared but never referenced

Usage:
    python3 DeadCodeCheck.py <directory> [--verbose]

Options:
    --verbose   Show detailed information about each finding

Analysis:
    - Identifies functions defined locally but never called
    - Cross-references with utility functions to avoid false positives
    - Tracks variable declarations and usage
    - Considers entry point scripts (scripts that call functions from utilities)

Author: Coela
"""

import os
import sys
import re
from pathlib import Path
from collections import defaultdict

SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

# Regex patterns
FUNC_DEF_REGEX = re.compile(r'^(?:function\s+)?([a-zA-Z_][a-zA-Z0-9_]*|__[a-zA-Z0-9_]+__)\s*\(\)\s*\{')
FUNC_CALL_REGEX = re.compile(r'\b([a-zA-Z_][a-zA-Z0-9_]*|__[a-zA-Z0-9_]+__)\s*(?:\(|$)')
VAR_DECLARATION_REGEX = re.compile(r'^\s*(?:local\s+|declare\s+|export\s+)?([A-Z_][A-Z0-9_]*)\s*=')
VAR_USAGE_REGEX = re.compile(r'\$\{?([A-Z_][A-Z0-9_]*)\}?')

# Entry point patterns (main-like functions or direct script execution)
ENTRY_PATTERNS = [
    'main',
    '__main__',
]

def find_sh_files(base_dir, utilities_only=False):
    """Find all .sh files recursively, optionally filtering for utilities."""
    sh_files = []
    utilities_path = Path(base_dir).resolve() / "Utilities"
    
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        
        for filename in files:
            if filename.endswith(".sh"):
                file_path = os.path.join(root, filename)
                
                if utilities_only:
                    if str(Path(file_path).resolve()).startswith(str(utilities_path)):
                        sh_files.append(file_path)
                else:
                    if not str(Path(file_path).resolve()).startswith(str(utilities_path)):
                        sh_files.append(file_path)
    
    return sh_files

def parse_functions(file_path):
    """Parse function definitions from a file."""
    functions = {}
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return functions
    
    for i, line in enumerate(lines, 1):
        match = FUNC_DEF_REGEX.match(line.strip())
        if match:
            func_name = match.group(1)
            functions[func_name] = i
    
    return functions

def find_function_calls(file_path, exclude_definitions=True):
    """Find all function calls in a file."""
    calls = set()
    defined_functions = set()
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return calls
    
    for line in lines:
        # Skip comments
        stripped = line.strip()
        if stripped.startswith('#'):
            continue
        
        # Track function definitions
        def_match = FUNC_DEF_REGEX.match(stripped)
        if def_match:
            defined_functions.add(def_match.group(1))
            continue
        
        # Find function calls (simple heuristic: word followed by space or opening paren)
        tokens = stripped.split()
        for token in tokens:
            # Remove command substitution, redirects, etc.
            clean_token = re.sub(r'[\$\(\)\[\]\{\}<>|&;"\']', ' ', token)
            words = clean_token.split()
            
            for word in words:
                if re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', word) or \
                   re.match(r'^__[a-zA-Z0-9_]+__$', word):
                    calls.add(word)
    
    # Remove defined functions if requested
    if exclude_definitions:
        calls -= defined_functions
    
    return calls

def find_variable_declarations_and_usage(file_path):
    """Find variable declarations and their usage."""
    declarations = {}
    usage = set()
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return declarations, usage
    
    for i, line in enumerate(lines, 1):
        # Skip comments
        stripped = line.strip()
        if stripped.startswith('#'):
            continue
        
        # Find declarations
        decl_match = VAR_DECLARATION_REGEX.search(line)
        if decl_match:
            var_name = decl_match.group(1)
            declarations[var_name] = i
        
        # Find usage
        for match in VAR_USAGE_REGEX.finditer(line):
            usage.add(match.group(1))
    
    return declarations, usage

def is_entry_point_script(file_path):
    """
    Check if a script is an entry point (executed directly, not just sourced).
    Entry point scripts may call functions without defining them.
    """
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception:
        return False
    
    # Check for entry point patterns
    for pattern in ENTRY_PATTERNS:
        if re.search(rf'\b{pattern}\b', content):
            return True
    
    # Check if script has executable logic outside functions
    lines = content.split('\n')
    in_function = False
    has_top_level_code = False
    
    for line in lines:
        stripped = line.strip()
        
        # Skip empty lines and comments
        if not stripped or stripped.startswith('#'):
            continue
        
        # Check for function start
        if FUNC_DEF_REGEX.match(stripped):
            in_function = True
        
        # Check for function end (simple heuristic: closing brace at start of line)
        if stripped == '}':
            in_function = False
            continue
        
        # If we have code outside functions (not just variable declarations or source)
        if not in_function:
            if not stripped.startswith(('source ', '. ', 'export ', 'declare ', 'readonly ')):
                if not re.match(r'^[A-Z_][A-Z0-9_]*=', stripped):
                    has_top_level_code = True
                    break
    
    return has_top_level_code

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 DeadCodeCheck.py <directory> [--verbose]")
        sys.exit(1)
    
    base_dir = sys.argv[1]
    verbose = "--verbose" in sys.argv
    
    if not os.path.isdir(base_dir):
        print(f"Error: {base_dir} is not a valid directory.")
        sys.exit(1)
    
    print("=" * 80)
    print("DEAD CODE ANALYSIS")
    print("=" * 80)
    print()
    
    # First, build a map of all utility functions
    print("Building function database from utilities...")
    utility_files = find_sh_files(base_dir, utilities_only=True)
    utility_functions = set()
    
    for util_file in utility_files:
        funcs = parse_functions(util_file)
        utility_functions.update(funcs.keys())
    
    print(f"Found {len(utility_functions)} utility functions")
    print()
    
    # Now analyze regular scripts
    script_files = find_sh_files(base_dir, utilities_only=False)
    
    total_dead_functions = 0
    total_dead_variables = 0
    files_with_dead_code = 0
    
    print(f"Analyzing {len(script_files)} scripts...")
    print()
    
    for script_file in script_files:
        dead_functions = []
        dead_variables = []
        
        # Check if this is an entry point script
        is_entry_point = is_entry_point_script(script_file)
        
        # Analyze functions
        defined_funcs = parse_functions(script_file)
        called_funcs = find_function_calls(script_file)
        
        for func_name, line_num in defined_funcs.items():
            # Skip if it's called in this file
            if func_name in called_funcs:
                continue
            
            # Skip if it's an entry point function
            if func_name in ENTRY_PATTERNS:
                continue
            
            # Skip if it's a utility function (could be called from elsewhere)
            if func_name in utility_functions:
                continue
            
            # If this is not an entry point, the function is likely dead
            if not is_entry_point:
                dead_functions.append((func_name, line_num))
        
        # Analyze variables (only in non-entry-point scripts)
        if not is_entry_point:
            declarations, usage = find_variable_declarations_and_usage(script_file)
            
            for var_name, line_num in declarations.items():
                if var_name not in usage:
                    # Skip some common variables that might be used by sourced scripts
                    if var_name not in ['UTILITYPATH', 'SCRIPTPATH', 'PATH', 'HOME']:
                        dead_variables.append((var_name, line_num))
        
        # Report findings
        if dead_functions or dead_variables:
            files_with_dead_code += 1
            print(f"[DEAD CODE] {script_file}")
            
            if is_entry_point and verbose:
                print("  (Note: Entry point script - some unused functions may be intentional)")
            
            if dead_functions:
                total_dead_functions += len(dead_functions)
                print(f"  Unused functions ({len(dead_functions)}):")
                for func_name, line_num in sorted(dead_functions, key=lambda x: x[1]):
                    print(f"    Line {line_num}: {func_name}()")
            
            if dead_variables:
                total_dead_variables += len(dead_variables)
                print(f"  Unused variables ({len(dead_variables)}):")
                for var_name, line_num in sorted(dead_variables, key=lambda x: x[1]):
                    print(f"    Line {line_num}: {var_name}")
            
            print()
    
    # Summary
    print("=" * 80)
    print("DEAD CODE SUMMARY")
    print("=" * 80)
    print(f"Files analyzed: {len(script_files)}")
    print(f"Files with potential dead code: {files_with_dead_code}")
    print(f"Total unused functions: {total_dead_functions}")
    print(f"Total unused variables: {total_dead_variables}")
    print()
    
    if files_with_dead_code > 0:
        print("Note: Some findings may be false positives:")
        print("  - Functions/variables used dynamically")
        print("  - Functions defined for future use")
        print("  - Entry point scripts that define helper functions")
    else:
        print("No dead code detected!")
    
    print()
    
    return 0 if files_with_dead_code == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
