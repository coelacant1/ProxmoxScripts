#!/usr/bin/env python3
"""
This script scans the ../Utilities directory for .sh files (ignoring those that start with an underscore),
parses function header blocks (formatted with "# ---" and "# @tag ..." comments, including multi-line tags),
and generates a markdown file (../Utilities/Utilities.md) that lists each function with its quick description,
usage, example output, and output information.
"""

import os
import glob
import re

# Directory paths
UTILS_DIR = os.path.join(os.path.dirname(__file__), "../Utilities")
OUTPUT_MD = os.path.join(UTILS_DIR, "Utilities.md")

# Regex patterns for header parsing
header_start_re = re.compile(r'^# ---\s*(\S+)\s*-+')
tag_line_re = re.compile(r'^#\s*@(\w+)\s*(.*)')
comment_line_re = re.compile(r'^#\s?(.*)')  # any comment line

def parse_function_block(lines, start_index):
    """
    Parse a function header block starting at start_index in lines.
    Handles multi-line tags: if a subsequent comment line does not start with "# @" then
    it is appended to the last tag's value.
    
    Returns a tuple (func_info, new_index) where func_info is a dictionary with keys:
      function, description, usage, example_output, return
    and new_index is the index of the first line after the block.
    """
    # Initialize expected keys; note that "example_output" is now added.
    info = {
        "function": "",
        "description": "",
        "usage": "",
        "example_output": "",
        "return": ""
    }
    current_tag = None
    i = start_index + 1  # skip the "# ---" header line
    while i < len(lines):
        line = lines[i].rstrip("\n")
        if not line.startswith("#"):
            break
        tag_match = tag_line_re.match(line)
        if tag_match:
            tag, content = tag_match.groups()
            tag = tag.lower()
            if tag in info:
                info[tag] = content.strip()
                current_tag = tag
            else:
                current_tag = None
        else:
            # Continuation line: append to current tag if exists.
            cont_match = comment_line_re.match(line)
            if cont_match and current_tag:
                cont_text = cont_match.group(1).strip()
                if cont_text:
                    info[current_tag] += " " + cont_text
        i += 1
    return info, i

def parse_file(file_path):
    """
    Parse a shell script file for function header blocks.
    Returns a list of function info dictionaries.
    """
    functions = []
    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if header_start_re.match(line):
            func_info, i = parse_function_block(lines, i)
            if func_info.get("function"):
                functions.append(func_info)
        else:
            i += 1
    return functions

def generate_markdown():
    # Get list of .sh files (ignoring files starting with an underscore)
    sh_files = sorted([os.path.basename(f) for f in glob.glob(os.path.join(UTILS_DIR, "*.sh"))
                       if not os.path.basename(f).startswith("_")])
    
    md_lines = []
    md_lines.append("# Utility Functions Quick Description and Usage\n")
    md_lines.append("Concise documentation for the helper utilties\n")
    md_lines.append("## File Tree")
    md_lines.append("utilities/")
    for fname in sh_files:
        md_lines.append(f"└── {fname}")
    md_lines.append("\n")
    
    # For each file, parse functions and add summary entries.
    for fname in sh_files:
        md_lines.append(f"## {fname}\n")

        file_path = os.path.join(UTILS_DIR, fname)
        functions = parse_file(file_path)
        for func in functions:
            # Use the first sentence of description as a short description.
            desc = func.get("description", "").strip()
            short_desc = desc.split(".")[0] if desc else "No description available"
            usage = func.get("usage", "No usage info provided.").strip()
            example_output = func.get("example_output", "No example output provided.").strip()
            ret = func.get("return", "No output info provided.").strip()
            
            md_lines.append(f"{fname}/{func['function']}: {short_desc}.  ")
            md_lines.append(f"Usage: {usage}  ")
            md_lines.append(f"Example Output: {example_output}  ")
            md_lines.append(f"Output: {ret}\n")
    
    with open(OUTPUT_MD, "w", encoding="utf-8") as out_file:
        out_file.write("\n".join(md_lines))
    print(f"Markdown file generated at: {OUTPUT_MD}")

if __name__ == "__main__":
    generate_markdown()
