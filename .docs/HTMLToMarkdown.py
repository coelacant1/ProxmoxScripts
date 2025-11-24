#!/usr/bin/env python3
"""
Convert Proxmox VE Administration Guide HTML to Markdown
"""

import sys
import re
from pathlib import Path
from html.parser import HTMLParser
import argparse


class HTMLToMarkdownConverter(HTMLParser):
    def __init__(self, base_url=""):
        super().__init__()
        self.markdown = []
        self.current_text = []
        self.list_stack = []
        self.in_pre = False
        self.in_code = False
        self.in_heading = False
        self.heading_level = 0
        self.heading_id = ""
        self.in_link = False
        self.link_href = ""
        self.in_table = False
        self.table_rows = []
        self.table_caption = ""
        self.current_row = []
        self.in_cell = False
        self.skip_content = False
        self.in_dl = False
        self.in_dt = False
        self.in_dd = False
        self.base_url = base_url
        self.chapters = []
        self.current_chapter = None
        self.id_to_heading = {}  # Map HTML IDs to markdown headings
        self.in_pre_code = False  # Track if we're in a code block
    
    @staticmethod
    def heading_to_anchor(heading_text):
        """Convert heading text to GitHub-style anchor"""
        # Remove markdown heading markers
        text = re.sub(r'^#+\s+', '', heading_text)
        # Lowercase
        text = text.lower()
        # Remove punctuation except spaces and hyphens
        text = re.sub(r'[^\w\s-]', '', text)
        # Replace spaces with hyphens
        text = re.sub(r'\s+', '-', text)
        # Remove leading/trailing hyphens
        text = text.strip('-')
        return text
        
    def handle_starttag(self, tag, attrs):
        attrs_dict = dict(attrs)
        
        if tag in ['script', 'style']:
            self.skip_content = True
            return
            
        if tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']:
            self.flush_text()
            self.in_heading = True
            self.heading_level = int(tag[1])
            self.heading_id = attrs_dict.get('id', '')
            
        elif tag == 'p':
            # Don't add extra spacing if we're in a list item or table cell
            if not self.list_stack and not self.in_cell:
                self.flush_text()
            
        elif tag == 'div':
            attrs_dict = dict(attrs)
            # Flush text for certain div classes that indicate new sections
            if attrs_dict.get('class') in ['paragraph', 'sectionbody', 'section']:
                self.flush_text()
            
        elif tag == 'br':
            self.current_text.append('\n')
            
        elif tag == 'strong' or tag == 'b':
            self.current_text.append('**')
            
        elif tag == 'em' or tag == 'i':
            self.current_text.append('*')
            
        elif tag == 'code':
            if not self.in_pre:
                self.current_text.append('`')
                self.in_code = True
                
        elif tag == 'pre':
            self.flush_text()
            self.in_pre = True
            self.in_pre_code = True
            self.markdown.append('\n```\n')
            
        elif tag == 'a':
            # Skip headerlink anchors inside headings
            if attrs_dict.get('class') == 'headerlink':
                self.skip_content = True
                return
            # Skip image links (no text, just href to image)
            href = attrs_dict.get('href', '')
            if href and any(ext in href.lower() for ext in ['.png', '.jpg', '.jpeg', '.gif', '.svg']):
                self.skip_content = True
                return
            self.in_link = True
            self.link_href = href
            self.current_text.append('[')
            
        elif tag == 'ul':
            self.flush_text()
            self.list_stack.append('ul')
            
        elif tag == 'ol':
            self.flush_text()
            self.list_stack.append('ol')
            
        elif tag == 'li':
            self.flush_text()
            indent = '  ' * (len(self.list_stack) - 1)
            if self.list_stack and self.list_stack[-1] == 'ul':
                self.markdown.append(f'\n{indent}* ')
            else:
                self.markdown.append(f'\n{indent}1. ')
                
        elif tag == 'table':
            self.flush_text()
            self.in_table = True
            self.table_rows = []
            self.table_caption = ""
            
        elif tag == 'caption':
            # Table caption
            pass
            
        elif tag == 'thead' or tag == 'tbody' or tag == 'colgroup' or tag == 'col':
            # Skip these structural tags
            pass
            
        elif tag == 'tr':
            self.current_row = []
            
        elif tag in ['td', 'th']:
            self.in_cell = True
            
        elif tag == 'hr':
            self.flush_text()
            self.markdown.append('\n---\n')
            
        elif tag == 'blockquote':
            self.flush_text()
            self.current_text.append('> ')
            
        elif tag == 'dl':
            self.flush_text()
            self.in_dl = True
            
        elif tag == 'dt':
            self.flush_text()
            self.in_dt = True
            
        elif tag == 'dd':
            self.flush_text()
            self.in_dd = True
            
    def handle_endtag(self, tag):
        if tag in ['script', 'style']:
            self.skip_content = False
            return
            
        if tag in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']:
            text = ''.join(self.current_text).strip()
            heading_text = f'\n{"#" * self.heading_level} {text}\n'
            self.markdown.append(heading_text)
            
            # Map HTML ID to GitHub-style anchor
            if self.heading_id and text:
                github_anchor = self.heading_to_anchor(text)
                self.id_to_heading[self.heading_id] = github_anchor
            
            # Track chapters (h2 level)
            if self.heading_level == 2 and text:
                if self.current_chapter:
                    self.chapters.append(self.current_chapter)
                self.current_chapter = {
                    'title': text,
                    'id': self.heading_id,
                    'content_start': len(self.markdown)
                }
            
            self.current_text = []
            self.in_heading = False
            self.heading_id = ""
            
        elif tag == 'p':
            # Don't output newline at end if we're in a list or table cell
            if not self.list_stack and not self.in_cell:
                self.flush_text()
                self.markdown.append('\n')
            
        elif tag == 'strong' or tag == 'b':
            self.current_text.append('**')
            
        elif tag == 'em' or tag == 'i':
            self.current_text.append('*')
            
        elif tag == 'code':
            if not self.in_pre:
                self.current_text.append('`')
                self.in_code = False
                
        elif tag == 'pre':
            # Detect common code types and add language hint
            content = ''.join(self.markdown[-10:]) if len(self.markdown) > 10 else ''.join(self.markdown)
            
            # Check for common patterns
            lang = ""
            if 'auto eth' in content or 'iface' in content or 'address' in content:
                lang = "bash"
            elif any(cmd in content for cmd in ['apt', 'systemctl', 'cd ', 'ls ', 'mkdir', 'chmod', 'chown']):
                lang = "bash"
            elif 'pvesm' in content or 'pct' in content or 'qm ' in content:
                lang = "bash"
                
            # Update the opening fence if we detected a language
            if lang and self.in_pre_code:
                # Find the last ``` and add language
                for i in range(len(self.markdown) - 1, -1, -1):
                    if self.markdown[i] == '\n```\n':
                        self.markdown[i] = f'\n```{lang}\n'
                        break
            
            self.markdown.append('\n```\n')
            self.in_pre = False
            self.in_pre_code = False
            
        elif tag == 'a':
            # Re-enable content after headerlink
            if self.skip_content:
                self.skip_content = False
                return
                
            text = ''.join(self.current_text).strip()
            if self.link_href:
                # Convert internal anchor links to GitHub-style markdown anchors
                link = self.link_href
                if self.base_url and link.startswith(self.base_url):
                    # Extract HTML anchor from URL
                    if '#' in link:
                        html_id = link.split('#')[1]
                        # Use GitHub anchor if we've seen this heading, otherwise keep HTML ID
                        link = f'#{html_id}'
                elif link.startswith('#'):
                    # Already an anchor link - keep as is for now
                    pass
                self.markdown.append(f'{text}]({link}) ')
            else:
                self.markdown.append(f'{text}] ')
            self.current_text = []
            self.in_link = False
            
        elif tag == 'caption':
            # Save caption text
            caption_text = ''.join(self.current_text).strip()
            if caption_text:
                self.table_caption = caption_text
            self.current_text = []
            
        elif tag == 'thead' or tag == 'tbody' or tag == 'colgroup' or tag == 'col':
            # Skip these
            pass
            
        elif tag == 'ul' or tag == 'ol':
            self.flush_text()
            if self.list_stack:
                self.list_stack.pop()
            self.markdown.append('\n')
            
        elif tag == 'li':
            self.flush_text()
            
        elif tag == 'tr':
            if self.current_row:
                self.table_rows.append(self.current_row)
            self.current_row = []
            
        elif tag in ['td', 'th']:
            cell_text = ''.join(self.current_text).strip()
            self.current_row.append(cell_text)
            self.current_text = []
            self.in_cell = False
            
        elif tag == 'table':
            self.flush_table()
            self.in_table = False
            self.table_caption = ""
            
        elif tag == 'dl':
            self.flush_text()
            self.in_dl = False
            self.markdown.append('\n')
            
        elif tag == 'dt':
            text = ''.join(self.current_text).strip()
            if text:
                self.markdown.append(f'\n**{text}**\n')
            self.current_text = []
            self.in_dt = False
            
        elif tag == 'dd':
            self.flush_text()
            self.markdown.append('\n')
            self.in_dd = False
            
    def handle_data(self, data):
        if self.skip_content:
            return
            
        if self.in_pre:
            self.markdown.append(data)
        else:
            # Normalize whitespace but preserve intentional line breaks
            cleaned = re.sub(r'\s+', ' ', data)
            if cleaned:
                self.current_text.append(cleaned)
                
    def flush_text(self):
        if self.current_text:
            text = ''.join(self.current_text).strip()
            if text:
                self.markdown.append(text)
            self.current_text = []
            
    def flush_table(self):
        if not self.table_rows:
            return
            
        self.markdown.append('\n')
        
        # Add caption if present
        if self.table_caption:
            self.markdown.append(f'**{self.table_caption}**\n\n')
        
        # Determine column count
        max_cols = max(len(row) for row in self.table_rows) if self.table_rows else 0
        
        # Write header
        if self.table_rows:
            header = self.table_rows[0]
            # Pad rows to have same number of columns
            while len(header) < max_cols:
                header.append('')
            self.markdown.append('| ' + ' | '.join(header) + ' |')
            self.markdown.append('\n|' + '|'.join(['---'] * len(header)) + '|')
            
            # Write data rows
            for row in self.table_rows[1:]:
                # Pad rows to have same number of columns
                while len(row) < max_cols:
                    row.append('')
                self.markdown.append('\n| ' + ' | '.join(row) + ' |')
                
        self.markdown.append('\n\n')
        self.table_rows = []
        
    def get_markdown(self):
        self.flush_text()
        # Finalize last chapter
        if self.current_chapter:
            self.chapters.append(self.current_chapter)
        
        result = ''.join(self.markdown)
        
        # Convert HTML ID references to GitHub-style anchors
        result = self._convert_links_to_github_anchors(result)
        
        # Clean up excessive newlines
        result = re.sub(r'\n{3,}', '\n\n', result)
        # Remove empty headings (headings with no text)
        result = re.sub(r'\n#{1,6}\s*\n', '\n', result)
        return result.strip() + '\n'
    
    def _convert_links_to_github_anchors(self, text):
        """Convert HTML ID references in links to GitHub-style anchors"""
        def replace_link(match):
            link_text = match.group(1)
            link_url = match.group(2)
            
            # Only process anchor links
            if link_url.startswith('#'):
                html_id = link_url[1:]  # Remove the #
                # Convert to GitHub anchor if we have a mapping
                if html_id in self.id_to_heading:
                    github_anchor = self.id_to_heading[html_id]
                    return f'[{link_text}](#{github_anchor})'
            
            return match.group(0)  # Return unchanged
        
        # Match markdown links [text](url)
        return re.sub(r'\[([^\]]+)\]\(([^)]+)\)', replace_link, text)
    
    def get_chapters(self):
        """Split markdown into chapters based on h2 headings"""
        if not self.chapters:
            return []
        
        full_text = ''.join(self.markdown)
        chapter_docs = []
        
        for i, chapter in enumerate(self.chapters):
            # Find content between this chapter and the next
            start_idx = chapter['content_start']
            end_idx = self.chapters[i + 1]['content_start'] if i + 1 < len(self.chapters) else len(self.markdown)
            
            chapter_content = ''.join(self.markdown[start_idx:end_idx])
            
            # Convert links in chapter content
            chapter_content = self._convert_links_to_github_anchors(chapter_content)
            
            # Clean up
            chapter_content = re.sub(r'\n{3,}', '\n\n', chapter_content)
            chapter_content = re.sub(r'\n#{1,6}\s*\n', '\n', chapter_content)
            chapter_content = chapter_content.strip()
            
            if chapter_content:
                chapter_docs.append({
                    'title': chapter['title'],
                    'id': chapter['id'],
                    'content': chapter_content
                })
        
        return chapter_docs


def split_cli_appendix(content, output_dir, base_filename, chapter_title):
    """Split Command-line Interface appendix into subsections"""
    # Extract chapter number from title (e.g., "22. Appendix A" -> "22")
    chapter_num_match = re.match(r'^(\d+)\.', chapter_title)
    if not chapter_num_match:
        return
    
    chapter_num = chapter_num_match.group(1)
    
    # Find all ### {chapter_num}.X subsections
    sections = []
    lines = content.split('\n')
    current_section = None
    current_content = []
    
    # Pattern to match subsections like "### 22.1." or "### 22.10."
    subsection_pattern = f'### {chapter_num}.'
    
    for line in lines:
        # Match ### {chapter_num}.X headings
        if line.startswith(subsection_pattern):
            # Save previous section
            if current_section:
                sections.append({
                    'title': current_section,
                    'content': '\n'.join(current_content)
                })
            # Start new section
            current_section = line.replace('### ', '').strip()
            current_content = [line]
        elif current_section:
            current_content.append(line)
    
    # Save last section
    if current_section:
        sections.append({
            'title': current_section,
            'content': '\n'.join(current_content)
        })
    
    # Write subsection files
    if sections:
        print(f"    Splitting {base_filename} into {len(sections)} subsections...")
        for section in sections:
            # Extract subsection number (e.g., "22.3. pvesm..." -> "03")
            subsection_match = re.match(rf'^{chapter_num}\.(\d+)\.?\s*(.*)', section['title'])
            if subsection_match:
                subsection_num = subsection_match.group(1).zfill(2)  # Pad to 2 digits
                subsection_name = subsection_match.group(2).strip()
                
                # Create safe filename from name
                safe_name = re.sub(r'[^\w\s-]', '', subsection_name)
                safe_name = re.sub(r'[-\s]+', '-', safe_name)
                safe_name = safe_name.strip('-')[:60]  # Limit length
                
                section_file = output_dir / f"{chapter_num}-{subsection_num}-{safe_name}.md"
            else:
                # Fallback to original logic
                safe_title = re.sub(r'[^\w\s-]', '', section['title'])
                safe_title = re.sub(r'[-\s]+', '-', safe_title)
                safe_title = safe_title.strip('-')[:80]
                section_file = output_dir / f"{safe_title}.md"
            
            with open(section_file, 'w', encoding='utf-8') as f:
                f.write(section['content'])
            
            print(f"      • {section_file.name}")


def convert_html_to_markdown(html_file, output_file=None, split_chapters=False):
    """Convert HTML file to Markdown"""
    html_path = Path(html_file)
    
    if not html_path.exists():
        print(f"Error: File '{html_file}' not found.")
        return False
        
    # Read HTML content
    with open(html_path, 'r', encoding='utf-8') as f:
        html_content = f.read()
    
    # Extract version number
    version = "unknown"
    version_match = re.search(r'<span id="revnumber">version\s+([\d.]+)', html_content)
    if version_match:
        version = version_match.group(1)
    
    # Detect base URL from HTML
    base_url = ""
    base_match = re.search(r'href="([^"]+pve-admin-guide\.html)', html_content)
    if base_match:
        base_url = base_match.group(1).split('#')[0]
        
    # Convert to Markdown
    converter = HTMLToMarkdownConverter(base_url=base_url)
    converter.feed(html_content)
    markdown_content = converter.get_markdown()
    
    # Don't write the full combined file
    print(f"Conversion complete. Version: {version}")
    print(f"Content size: {len(markdown_content)} characters")
    
    # Split into chapters if requested
    if split_chapters:
        chapters = converter.get_chapters()
        if chapters:
            # Use provided output directory or create version-specific one
            if output_file:
                chapters_dir = Path(output_file)
            else:
                script_dir = Path(__file__).parent
                version_formatted = f"V{version.replace('.', '-')}_PVEGuide"
                chapters_dir = script_dir / version_formatted
            
            # Create directory if it doesn't exist
            chapters_dir.mkdir(parents=True, exist_ok=True)
            
            print(f"\nCreating {len(chapters)} chapter files in {chapters_dir.name}/...")
            for chapter in chapters:
                # Create safe filename from title
                safe_title = re.sub(r'[^\w\s-]', '', chapter['title'])
                safe_title = re.sub(r'[-\s]+', '-', safe_title)
                safe_title = safe_title.strip('-')[:80]  # Limit length
                
                chapter_file = chapters_dir / f"{safe_title}.md"
                
                # Add chapter title as h1
                chapter_content = f"# {chapter['title']}\n\n{chapter['content']}"
                
                with open(chapter_file, 'w', encoding='utf-8') as f:
                    f.write(chapter_content)
                
                print(f"  Created: {chapter_file.name}")
                
                # Special handling for Command-line Interface appendix - split into subsections
                if 'command-line interface' in chapter['title'].lower() or 'command line interface' in chapter['title'].lower():
                    split_cli_appendix(chapter_content, chapters_dir, safe_title, chapter['title'])
                    
                    # Replace the main chapter file with just a summary/index
                    # Extract chapter number from the title to find subsection files
                    chapter_num_match = re.match(r'^(\d+)\.', chapter['title'])
                    if chapter_num_match:
                        chapter_num = chapter_num_match.group(1)
                        subsection_files = sorted(chapters_dir.glob(f"{chapter_num}-*-*.md"))
                        if subsection_files:
                            summary_content = f"# {chapter['title']}\n\n"
                            summary_content += "This chapter has been split into the following subsections:\n\n"
                            for sf in subsection_files:
                                # Extract subsection title from filename
                                subsection_name = sf.stem.replace('-', ' ', 2)  # Replace first 2 hyphens with spaces
                                subsection_name = subsection_name.replace(' ', '.', 1)  # First space becomes dot
                                summary_content += f"- [{subsection_name}](./{sf.name})\n"
                            
                            with open(chapter_file, 'w', encoding='utf-8') as f:
                                f.write(summary_content)
            
            # Create README
            readme_content = f"""# Proxmox VE Administration Guide - Version {version}

This directory contains the Proxmox VE Administration Guide (v{version}) split into individual chapters.

## Features

- **Pure GitHub Markdown**: No HTML - uses native GitHub heading anchors
- **Automatic Links**: GitHub creates anchors from headings
- **Clean Format**: All code blocks, tables, and lists properly formatted

## Usage

Individual chapter files are ideal for:
- Quick reference
- Documentation integration

Generated from official Proxmox VE documentation.
"""
            with open(chapters_dir / 'README.md', 'w', encoding='utf-8') as f:
                f.write(readme_content)
            
            print(f"\nAll chapters saved to: {chapters_dir}/")
    
    return True


def main():
    parser = argparse.ArgumentParser(
        description='Convert Proxmox VE Administration Guide HTML to Markdown'
    )
    parser.add_argument(
        'input_file',
        help='Path to the HTML file to convert'
    )
    parser.add_argument(
        '-o', '--output',
        help='Output markdown file path (default: .d directory with .md extension)',
        default=None
    )
    parser.add_argument(
        '-s', '--split-chapters',
        help='Split output into separate files per chapter',
        action='store_true'
    )
    
    args = parser.parse_args()
    
    success = convert_html_to_markdown(args.input_file, args.output, args.split_chapters)
    sys.exit(0 if success else 1)



if __name__ == "__main__":
    main()
