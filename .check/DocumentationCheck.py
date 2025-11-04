#!/usr/bin/env python3
"""
DocumentationCheck.py

Verifies documentation completeness in shell scripts.

Checks:
    - All scripts have file header with description
    - All scripts have usage information
    - All functions have description comments
    - Function Index matches actual functions
    - Scripts have proper examples

Usage:
    python3 DocumentationCheck.py <directory> [--strict]

Options:
    --strict    Enable stricter checks (examples required, parameter docs, etc.)

Documentation standards:
    - File header: First comment block should describe the script
    - Usage section: Must include usage syntax
    - Function comments: Each function should have a brief description
    - Function Index: Auto-generated list of functions (verified)
    - Examples: At least one example of script usage (strict mode)

Author: Coela
"""

import os
import sys
import re
from pathlib import Path

SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

# Regex patterns
FUNC_DEF_REGEX = re.compile(r'^(?:function\s+)?([a-zA-Z_][a-zA-Z0-9_]*|__[a-zA-Z0-9_]+__)\s*\(\)\s*\{')
FUNCTION_INDEX_REGEX = re.compile(r'^#\s*Function Index:', re.IGNORECASE)
USAGE_REGEX = re.compile(r'^#\s*Usage:', re.IGNORECASE)
EXAMPLE_REGEX = re.compile(r'^#\s*Example:', re.IGNORECASE)

def find_sh_files(base_dir):
    """Find all .sh files recursively."""
    sh_files = []
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for filename in files:
            if filename.endswith(".sh"):
                sh_files.append(os.path.join(root, filename))
    return sh_files

def parse_header_comments(file_path):
    """
    Extract the top comment block from a script.
    Returns the comment lines and metadata.
    """
    default_metadata = {
        'has_description': False,
        'has_usage': False,
        'has_example': False,
        'has_function_index': False,
        'description_lines': [],
    }
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return [], default_metadata
    
    if not lines:
        return [], default_metadata
    
    header_lines = []
    metadata = {
        'has_description': False,
        'has_usage': False,
        'has_example': False,
        'has_function_index': False,
        'description_lines': [],
    }
    
    # Skip shebang
    start_idx = 0
    if lines and lines[0].startswith('#!'):
        start_idx = 1
    
    # Collect header comment block
    in_header = False
    for i in range(start_idx, len(lines)):
        line = lines[i]
        stripped = line.strip()
        
        if stripped.startswith('#'):
            in_header = True
            header_lines.append(line)
            
            # Check for specific sections
            if USAGE_REGEX.search(stripped):
                metadata['has_usage'] = True
            elif EXAMPLE_REGEX.search(stripped):
                metadata['has_example'] = True
            elif FUNCTION_INDEX_REGEX.search(stripped):
                metadata['has_function_index'] = True
            elif stripped.startswith('#') and len(stripped) > 2:
                # Non-empty comment line could be description
                if not any([USAGE_REGEX.search(stripped), 
                           EXAMPLE_REGEX.search(stripped),
                           FUNCTION_INDEX_REGEX.search(stripped)]):
                    metadata['description_lines'].append(stripped)
        elif in_header and stripped == '':
            # Empty line within comment block
            header_lines.append(line)
        elif in_header:
            # End of comment block
            break
    
    # Check if we have a meaningful description
    meaningful_desc = [line for line in metadata['description_lines'] 
                      if not line.startswith('#' + '-' * 10) and 
                      not line.startswith('# =' * 10) and
                      len(line.strip()) > 3]
    
    metadata['has_description'] = len(meaningful_desc) > 2
    
    return header_lines, metadata

def parse_functions_with_context(file_path):
    """
    Parse functions and check if they have documentation comments.
    Returns dict: {function_name: {'line': num, 'has_doc': bool, 'doc': str}}
    """
    functions = {}
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return functions
    
    for i, line in enumerate(lines):
        match = FUNC_DEF_REGEX.match(line.strip())
        if match:
            func_name = match.group(1)
            
            # Look for comment above function (up to 5 lines back)
            has_doc = False
            doc_lines = []
            
            for j in range(max(0, i - 5), i):
                prev_line = lines[j].strip()
                if prev_line.startswith('#'):
                    # Check if it's a meaningful comment (not just separators)
                    if not re.match(r'^#+\s*$', prev_line) and \
                       not re.match(r'^#\s*[-=*#+]{3,}', prev_line):
                        has_doc = True
                        doc_lines.append(prev_line)
            
            functions[func_name] = {
                'line': i + 1,
                'has_doc': has_doc,
                'doc': '\n'.join(doc_lines) if doc_lines else ''
            }
    
    return functions

def check_function_index_accuracy(file_path):
    """
    Check if the Function Index in the header matches actual functions.
    Returns (is_accurate, expected_funcs, indexed_funcs)
    """
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return True, set(), set()
    
    # Find actual functions
    actual_funcs = set()
    for line in lines:
        match = FUNC_DEF_REGEX.match(line.strip())
        if match:
            actual_funcs.add(match.group(1))
    
    # Find indexed functions
    indexed_funcs = set()
    in_index = False
    
    for line in lines:
        stripped = line.strip()
        
        if FUNCTION_INDEX_REGEX.search(stripped):
            in_index = True
            continue
        
        if in_index:
            # Stop at non-comment or different section
            if not stripped.startswith('#'):
                break
            
            if any(keyword in stripped.lower() for keyword in ['usage:', 'example:', 'author:', 'note:']):
                break
            
            # Extract function name from index line (formats: "# - funcname" or "# funcname")
            func_match = re.search(r'#\s*[-*]?\s*([a-zA-Z_][a-zA-Z0-9_]*|__[a-zA-Z0-9_]+__)', stripped)
            if func_match:
                indexed_funcs.add(func_match.group(1))
    
    is_accurate = actual_funcs == indexed_funcs
    
    return is_accurate, actual_funcs, indexed_funcs

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 DocumentationCheck.py <directory> [--strict]")
        sys.exit(1)
    
    base_dir = sys.argv[1]
    strict_mode = "--strict" in sys.argv
    
    if not os.path.isdir(base_dir):
        print(f"Error: {base_dir} is not a valid directory.")
        sys.exit(1)
    
    print("=" * 80)
    print("DOCUMENTATION CHECK")
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
    
    issues_summary = {
        'no_description': 0,
        'no_usage': 0,
        'no_example': 0,
        'functions_without_docs': 0,
        'inaccurate_index': 0,
    }
    
    print(f"Checking documentation for {total_files} scripts...")
    print()
    
    for idx, file_path in enumerate(sh_files, 1):
        # Progress
        progress = int((idx / total_files) * 100)
        print(f"\rProgress: [{idx}/{total_files}] ({progress}%)...", end='', flush=True)
        
        issues = []
        
        # Check header documentation
        header_lines, metadata = parse_header_comments(file_path)
        
        if not metadata['has_description']:
            issues.append("Missing description in header")
            issues_summary['no_description'] += 1
        
        if not metadata['has_usage']:
            issues.append("Missing usage section")
            issues_summary['no_usage'] += 1
        
        if strict_mode and not metadata['has_example']:
            issues.append("Missing example section (strict mode)")
            issues_summary['no_example'] += 1
        
        # Check functions
        functions = parse_functions_with_context(file_path)
        undocumented_funcs = [name for name, info in functions.items() 
                             if not info['has_doc']]
        
        if undocumented_funcs:
            issues.append(f"{len(undocumented_funcs)} function(s) without documentation")
            issues_summary['functions_without_docs'] += len(undocumented_funcs)
        
        # Check function index accuracy
        if functions:  # Only if there are functions
            is_accurate, actual_funcs, indexed_funcs = check_function_index_accuracy(file_path)
            
            if not is_accurate:
                missing_from_index = actual_funcs - indexed_funcs
                extra_in_index = indexed_funcs - actual_funcs
                
                if missing_from_index or extra_in_index:
                    issues.append("Function Index is inaccurate")
                    issues_summary['inaccurate_index'] += 1
                    
                    if missing_from_index:
                        issues.append(f"  Missing from index: {', '.join(sorted(missing_from_index))}")
                    if extra_in_index:
                        issues.append(f"  Extra in index: {', '.join(sorted(extra_in_index))}")
        
        # Report issues
        if issues:
            print(f"\r{' ' * 60}\r", end='')  # Clear progress
            files_with_issues += 1
            
            print(f"[DOC] {file_path}")
            for issue in issues:
                print(f"  {issue}")
            
            if undocumented_funcs and len(undocumented_funcs) <= 5:
                print(f"  Undocumented functions:")
                for func_name in sorted(undocumented_funcs):
                    line_num = functions[func_name]['line']
                    print(f"    Line {line_num}: {func_name}()")
            
            print()
    
    # Clear progress
    print(f"\r{' ' * 60}\r", end='')
    
    # Summary
    print("=" * 80)
    print("DOCUMENTATION SUMMARY")
    print("=" * 80)
    print(f"Total files checked: {total_files}")
    print(f"Files with documentation issues: {files_with_issues}")
    print()
    print("Issue breakdown:")
    print(f"  Missing descriptions: {issues_summary['no_description']}")
    print(f"  Missing usage sections: {issues_summary['no_usage']}")
    if strict_mode:
        print(f"  Missing examples: {issues_summary['no_example']}")
    print(f"  Functions without docs: {issues_summary['functions_without_docs']}")
    print(f"  Inaccurate function indices: {issues_summary['inaccurate_index']}")
    print()
    
    if files_with_issues > 0:
        print("Recommendations:")
        print("  - Add description comments at the top of each script")
        print("  - Include usage examples in the header")
        print("  - Document each function with a comment above its definition")
        print("  - Run UpdateFunctionIndex.py to fix function indices")
        if not strict_mode:
            print("  - Use --strict mode for more thorough checking")
    else:
        print("All documentation checks passed!")
    
    print()
    
    return 0 if files_with_issues == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
