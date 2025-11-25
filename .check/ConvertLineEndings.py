#!/usr/bin/env python3
"""
ConvertLineEndings.py

Recursively converts CRLF (Windows) line endings to LF (Unix) line endings.
Automatically skips directories and files that should not be modified.

Usage:
    python3 ConvertLineEndings.py <directory>

Skips:
    - Directories: .git, .github, .site, .check
    - Files: .gitattributes, .gitignore, ConvertLineEndings.py
    - Binary files: images, archives, executables, compiled files

Author: Coela
"""

import os
import sys

def convert_line_endings_to_unix(directory):
    """
    Recursively walk `directory`, converting Windows-style line endings (\r\n)
    to Unix-style (\n) in all files EXCEPT:
      - Git folders: .git, .github
      - Build/site folders: .site, .check, .docs
      - Special files: .gitattributes, .gitignore
      - This script itself
    """
    # Directories to skip
    skip_dirs = {".git", ".github", ".site", ".check"}
    
    # Files to skip
    skip_files = {".gitattributes", ".gitignore", "ConvertLineEndings.py"}
    
    for root, dirs, files in os.walk(directory):
        # Remove skip directories from dirs list (modifies in-place for os.walk)
        dirs[:] = [d for d in dirs if d not in skip_dirs]

        for filename in files:
            # Skip specific files
            if filename in skip_files:
                continue
            
            # Skip binary file types that should never be converted
            if filename.endswith(('.png', '.jpg', '.jpeg', '.gif', '.ico', 
                                  '.zip', '.tar', '.gz', '.bz2','.pyc', 
                                  '.pyo', '.so', '.dylib')):
                continue

            file_path = os.path.join(root, filename)

            # Read the file in binary mode
            try:
                with open(file_path, "rb") as f:
                    content = f.read()
            except OSError as e:
                print(f"[ERROR] Could not open {file_path}: {e}")
                continue

            # Replace CRLF with LF
            new_content = content.replace(b"\r\n", b"\n")

            # Only write back if there's a difference
            if new_content != content:
                try:
                    with open(file_path, "wb") as f:
                        f.write(new_content)
                    print(f"[INFO] Converted line endings in {file_path}")
                except OSError as e:
                    print(f"[ERROR] Could not write to {file_path}: {e}")


def main():
    if len(sys.argv) != 2:
        print("Usage: python convert_line_endings.py <directory>")
        sys.exit(1)

    directory = sys.argv[1]

    if not os.path.isdir(directory):
        print(f"Error: {directory} is not a valid directory.")
        sys.exit(1)

    convert_line_endings_to_unix(directory)

if __name__ == "__main__":
    main()
