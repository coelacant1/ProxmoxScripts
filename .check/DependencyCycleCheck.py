#!/usr/bin/env python3
"""
DependencyCycleCheck.py

Detects circular dependencies in shell script source statements.

A circular dependency occurs when:
  Script A sources Script B
  Script B sources Script C
  Script C sources Script A

This can cause issues with initialization order and infinite loops.

Usage:
    python3 DependencyCycleCheck.py <directory> [--verbose]

Options:
    --verbose   Show detailed dependency tree

Analysis:
    - Builds a dependency graph from source statements
    - Detects cycles using depth-first search
    - Reports all cycles found with full paths
    - Visualizes dependency tree structure

Author: Coela
"""

import os
import sys
import re
from pathlib import Path
from collections import defaultdict, deque

SKIP_DIRS = {".git", ".github", ".site", ".check", ".docs"}

# Regex for source statements
SOURCE_REGEX = re.compile(
    r'^\s*(?:source|\.)\s+"?\$\{?UTILITYPATH\}?/([a-zA-Z0-9_.-]+)"?'
)

def find_sh_files(base_dir):
    """Find all .sh files recursively."""
    sh_files = []
    for root, dirs, files in os.walk(base_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for filename in files:
            if filename.endswith(".sh"):
                sh_files.append(os.path.join(root, filename))
    return sh_files

def parse_dependencies(file_path):
    """
    Parse source statements to find direct dependencies.
    Returns a set of sourced script names.
    """
    dependencies = set()
    
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                match = SOURCE_REGEX.search(line.strip())
                if match:
                    dependencies.add(match.group(1))
    except Exception:
        pass
    
    return dependencies

def build_dependency_graph(base_dir):
    """
    Build a dependency graph for all scripts.
    Returns:
        - graph: dict mapping filename -> set of dependencies
        - file_paths: dict mapping filename -> full path
    """
    graph = defaultdict(set)
    file_paths = {}
    
    sh_files = find_sh_files(base_dir)
    
    for file_path in sh_files:
        filename = Path(file_path).name
        file_paths[filename] = file_path
        
        dependencies = parse_dependencies(file_path)
        graph[filename] = dependencies
    
    return graph, file_paths

def find_cycles_dfs(graph):
    """
    Find all cycles in the dependency graph using DFS.
    Returns a list of cycles, where each cycle is a list of filenames.
    """
    cycles = []
    visited = set()
    rec_stack = []
    
    def dfs(node, path):
        if node in rec_stack:
            # Found a cycle
            cycle_start = rec_stack.index(node)
            cycle = rec_stack[cycle_start:] + [node]
            cycles.append(cycle)
            return
        
        if node in visited:
            return
        
        visited.add(node)
        rec_stack.append(node)
        
        # Visit all dependencies
        for dep in graph.get(node, set()):
            if dep in graph:  # Only follow if the dependency exists
                dfs(dep, path + [dep])
        
        rec_stack.pop()
    
    # Start DFS from each node
    for node in graph:
        if node not in visited:
            dfs(node, [node])
    
    return cycles

def find_strongly_connected_components(graph):
    """
    Find strongly connected components using Tarjan's algorithm.
    Components with more than one node are cycles.
    """
    index_counter = [0]
    stack = []
    lowlinks = {}
    index = {}
    on_stack = defaultdict(bool)
    components = []
    
    def strongconnect(node):
        index[node] = index_counter[0]
        lowlinks[node] = index_counter[0]
        index_counter[0] += 1
        stack.append(node)
        on_stack[node] = True
        
        # Visit successors
        for dep in graph.get(node, set()):
            if dep not in graph:
                continue
            
            if dep not in index:
                strongconnect(dep)
                lowlinks[node] = min(lowlinks[node], lowlinks[dep])
            elif on_stack[dep]:
                lowlinks[node] = min(lowlinks[node], index[dep])
        
        # Root node of SCC
        if lowlinks[node] == index[node]:
            component = []
            while True:
                w = stack.pop()
                on_stack[w] = False
                component.append(w)
                if w == node:
                    break
            components.append(component)
    
    for node in graph:
        if node not in index:
            strongconnect(node)
    
    return components

def format_cycle(cycle):
    """Format a cycle for display."""
    return " -> ".join(cycle)

def visualize_dependencies(graph, file_paths, show_all=False):
    """
    Create a text-based visualization of the dependency tree.
    """
    lines = []
    visited = set()
    
    def add_deps(node, prefix="", is_last=True):
        if node in visited and not show_all:
            lines.append(f"{prefix}{'└── ' if is_last else '├── '}{node} (already shown)")
            return
        
        visited.add(node)
        lines.append(f"{prefix}{'└── ' if is_last else '├── '}{node}")
        
        deps = sorted(graph.get(node, set()))
        for i, dep in enumerate(deps):
            if dep in graph:
                is_last_dep = (i == len(deps) - 1)
                new_prefix = prefix + ("    " if is_last else "│   ")
                add_deps(dep, new_prefix, is_last_dep)
    
    # Find root nodes (nodes with no incoming edges)
    all_deps = set()
    for deps in graph.values():
        all_deps.update(deps)
    
    roots = sorted(set(graph.keys()) - all_deps)
    
    if roots:
        lines.append("Root scripts (not sourced by others):")
        for i, root in enumerate(roots):
            add_deps(root, "", i == len(roots) - 1)
    
    return "\n".join(lines)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 DependencyCycleCheck.py <directory> [--verbose]")
        sys.exit(1)
    
    base_dir = sys.argv[1]
    verbose = "--verbose" in sys.argv
    
    if not os.path.isdir(base_dir):
        print(f"Error: {base_dir} is not a valid directory.")
        sys.exit(1)
    
    print("=" * 80)
    print("DEPENDENCY CYCLE ANALYSIS")
    print("=" * 80)
    print()
    
    # Build dependency graph
    print("Building dependency graph...")
    graph, file_paths = build_dependency_graph(base_dir)
    
    total_scripts = len(graph)
    total_dependencies = sum(len(deps) for deps in graph.values())
    
    print(f"Analyzed {total_scripts} scripts")
    print(f"Found {total_dependencies} source statements")
    print()
    
    # Find cycles using SCC algorithm
    print("Detecting circular dependencies...")
    components = find_strongly_connected_components(graph)
    
    # Filter to only cycles (components with more than one node)
    cycles = [comp for comp in components if len(comp) > 1]
    
    if cycles:
        print(f"\n[WARNING] Found {len(cycles)} circular dependency cycle(s)!\n")
        
        for i, cycle in enumerate(cycles, 1):
            print(f"Cycle {i}:")
            # Show the cycle
            cycle_display = cycle + [cycle[0]]  # Complete the circle
            print(f"  {format_cycle(cycle_display)}")
            
            if verbose:
                print("  Files involved:")
                for node in cycle:
                    if node in file_paths:
                        print(f"    {file_paths[node]}")
            print()
        
        print("Circular dependencies can cause:")
        print("  - Infinite loops during script initialization")
        print("  - Unpredictable behavior")
        print("  - Difficult-to-debug issues")
        print()
        print("Recommendation: Refactor to remove cycles by:")
        print("  - Creating a common base utility sourced by both")
        print("  - Moving shared functions to a third file")
        print("  - Restructuring the dependency hierarchy")
    else:
        print("[OK] No circular dependencies detected!")
    
    print()
    
    # Dependency tree visualization
    if verbose:
        print("=" * 80)
        print("DEPENDENCY TREE")
        print("=" * 80)
        print()
        
        tree = visualize_dependencies(graph, file_paths)
        if tree:
            print(tree)
        else:
            print("No dependencies to visualize.")
        print()
    
    # Statistics
    if verbose:
        print("=" * 80)
        print("DEPENDENCY STATISTICS")
        print("=" * 80)
        print()
        
        # Most dependencies
        most_deps = sorted(graph.items(), key=lambda x: len(x[1]), reverse=True)[:5]
        if most_deps:
            print("Scripts with most dependencies:")
            for script, deps in most_deps:
                if len(deps) > 0:
                    print(f"  {script}: {len(deps)} dependencies")
        
        print()
        
        # Most depended upon
        dep_count = defaultdict(int)
        for deps in graph.values():
            for dep in deps:
                dep_count[dep] += 1
        
        most_used = sorted(dep_count.items(), key=lambda x: x[1], reverse=True)[:5]
        if most_used:
            print("Most commonly sourced utilities:")
            for script, count in most_used:
                print(f"  {script}: sourced by {count} script(s)")
        
        print()
    
    # Summary
    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Total scripts: {total_scripts}")
    print(f"Total dependencies: {total_dependencies}")
    print(f"Circular dependencies: {len(cycles)}")
    print()
    
    return 0 if len(cycles) == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
