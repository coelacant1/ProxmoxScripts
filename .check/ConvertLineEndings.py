#!/usr/bin/env python3

import os
import sys

def convert_line_endings_to_unix(directory):
    """
    Walk through the given directory (recursively), converting
    Windows-style line endings (\r\n) to Unix-style (\n), except
    in any directory named '.github'.
    """
    for root, dirs, files in os.walk(directory):
        # Skip the .github directory (and its subfolders if any)
        if ".github" in dirs:
            dirs.remove(".github")

        for filename in files:
            file_path = os.path.join(root, filename)
            try:
                # Read file in binary mode to see raw bytes
                with open(file_path, "rb") as f:
                    content = f.read()
            except OSError as e:
                print(f"[ERROR] Could not open {file_path}: {e}")
                continue

            # Replace CRLF with LF
            new_content = content.replace(b"\r\n", b"\n")

            # Only write if there's a difference
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
