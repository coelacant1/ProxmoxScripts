#!/usr/bin/env python3
"""
UpdateFunctionIndex.py

This script scans a specified directory (recursively) for all *.sh files and
modifies the top block of contiguous comment lines in each file by inserting
or updating a "Function Index:" section with the names of functions found in
that script.

Behavior:
- Takes a single argument (path to a folder).
- Recursively walks that folder, processing every file that ends with ".sh".
- Skips .git, .github, .site, .check, .docs directories.
- Identifies the top contiguous comment block (lines starting with '#').
- Removes any existing lines from "Function Index:" to the end of that block.
- Parses the entire file for function definitions (using a regex for patterns like
  `funcName() {` or `function funcName() {`).
- **Only** if one or more functions are found, a new "Function Index:" section
  is appended to the top comment block listing them.

Usage:
    python UpdateFunctionIndex.py /path/to/directory

Example:
    python UpdateFunctionIndex.py /home/user/scripts

Author: Coela
"""

import sys
import os
import re

FUNCTION_INDEX_HEADER = "# Function Index:"

# Directories to skip during traversal
SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

def parse_functions(lines):
    """
    Scan all lines for function definitions.
    Returns a list of function names in the order they appear.
    Looks for:
      ^function <name> {   or
      ^function <name>() { or
      ^<name>() {
    Ignores lines that begin with '#'.
    """
    func_pattern = re.compile(r"""
        ^\s*                      # Start of line, optional whitespace
        (?:function\s+)?          # Optional 'function ' keyword
        ([a-zA-Z_][a-zA-Z0-9_]*)  # Capture group for function name
        \s*\(\s*\)\s*\{          # Required parentheses, then '{'
    """, re.VERBOSE)

    functions_found = []
    for line in lines:
        # Skip commented lines
        if line.strip().startswith("#"):
            continue
        match = func_pattern.match(line)
        if match:
            func_name = match.group(1)
            functions_found.append(func_name)
    return functions_found

def remove_old_function_index(comment_block):
    """
    Removes any lines from 'Function Index:' through the end of the block.
    Returns the cleaned list of comment lines.
    """
    cleaned_block = []
    inside_old_index = False

    for line in comment_block:
        if inside_old_index:
            # Once we find the start of an old Function Index,
            # we skip all subsequent lines in this block
            continue

        if FUNCTION_INDEX_HEADER in line:
            inside_old_index = True
            continue

        cleaned_block.append(line)
    return cleaned_block

def insert_new_function_index(comment_block, func_names):
    """
    Insert the new function index lines at the end of the comment block.
    Only called if func_names is non-empty.
    Returns the updated list of comment lines.
    """
    comment_block.append(FUNCTION_INDEX_HEADER + "\n")
    for name in func_names:
        comment_block.append(f"#   - {name}\n")
    comment_block.append("#\n")  # Final separator line

    return comment_block

def process_file(filepath):
    """
    1. Identify top contiguous comment block.
    2. Remove old function index (if present).
    3. Parse entire file for function definitions.
    4. If functions are found, insert new function index lines.
    5. Reconstruct and rewrite the file.
    
    Returns True if file was updated, False otherwise.
    """
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"\nCould not read file '{filepath}': {e}")
        return False

    # Identify top contiguous comment block
    top_comment_end = 0
    for i, line in enumerate(lines):
        if not line.lstrip().startswith("#"):
            top_comment_end = i
            break
    else:
        # If we never break, the entire file may be comments
        top_comment_end = len(lines)

    top_comment_block = lines[:top_comment_end]
    remainder = lines[top_comment_end:]

    # Remove existing "Function Index:" portion
    cleaned_block = remove_old_function_index(top_comment_block)

    # Parse for function definitions in the entire file
    all_functions = parse_functions(lines)

    # Only add "Function Index:" if we found at least one function
    if all_functions:
        updated_block = insert_new_function_index(cleaned_block, all_functions)

        # Combine the updated comment block with the rest of the file
        new_contents = updated_block + remainder

        # Write back to the file
        try:
            with open(filepath, "w", encoding="utf-8") as f:
                f.writelines(new_contents)
            return True
        except Exception as e:
            print(f"\nCould not write to file '{filepath}': {e}")
            return False
    
    return False

def main():
    # Expect exactly one argument: the path to the directory
    if len(sys.argv) < 2:
        print("Usage: python UpdateFunctionIndex.py /path/to/directory")
        sys.exit(1)

    folder_to_scan = sys.argv[1]
    if not os.path.isdir(folder_to_scan):
        print(f"Error: '{folder_to_scan}' is not a directory.")
        sys.exit(1)

    # Collect all .sh files first for progress tracking
    all_files = []
    for root, dirs, files in os.walk(folder_to_scan):
        # Skip specified directories
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        
        for filename in files:
            if filename.lower().endswith(".sh"):
                all_files.append(os.path.join(root, filename))
    
    total_files = len(all_files)
    updated_count = 0
    
    print(f"Found {total_files} .sh files to process")
    print("")
    
    # Process each file with progress indicator
    for i, filepath in enumerate(all_files, 1):
        # Show progress
        progress = int((i / total_files) * 100)
        print(f"Processing [{i}/{total_files}] ({progress}%): {os.path.basename(filepath)}", end='\r')
        
        if process_file(filepath):
            updated_count += 1
    
    # Clear progress line and show summary
    print(" " * 100, end='\r')
    print(f"\nProcessed {total_files} files")
    print(f"Updated {updated_count} files with function indices")
    print(f"Skipped {total_files - updated_count} files (no functions or no changes needed)")

if __name__ == "__main__":
    main()
