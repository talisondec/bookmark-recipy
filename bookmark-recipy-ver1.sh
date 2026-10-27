#!/bin/bash

# ==============================================================================
# Script to merge and clean bookmark files (.html) with counter
# Usage: ./merge_bookmarks.sh <output_file.html> <directory_or_file_1> [file_2...]
#
# MIT License
# Copyright (c) 2026 Tálison (https://github.com/talisondec)
# ==============================================================================

# 1. Dependency check: Verify if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required to securely process HTML." >&2
    exit 1
fi

# 2. Minimum argument validation
if [ "$#" -lt 2 ]; then
    echo "Incorrect usage."
    echo "Usage: $0 <output_file.html> <directory_or_file_1> [file_2 ...]"
    echo "Example: $0 my_bookmarks.html ~/Downloads/bookmarks_folder/ loose_file.html"
    exit 1
fi

OUTPUT_FILE="$1"
shift

# 3. Collection and validation of input files (supports individual files and directories)
INPUT_FILES=()
for arg in "$@"; do
    if [ -d "$arg" ]; then
        while IFS=read -r -d '' file; do
            INPUT_FILES+=("$file")
        done < <(find "$arg" -type f \( -iname "*.html" -o -iname "*.htm" \) -print0)
    elif [ -f "$arg" ]; then
        INPUT_FILES+=("$arg")
    else
        echo "Warning: Path ignored (not a valid file or directory): $arg" >&2
    fi
done

if [ "${#INPUT_FILES[@]}" -eq 0 ]; then
    echo "Error: No valid .html files found in the provided paths." >&2
    exit 1
fi

echo "Processing ${#INPUT_FILES[@]} file(s) found..."
echo ""

# 4. Embedded Python block for parsing, individual/global counting, and HTML generation
python3 - "$OUTPUT_FILE" "${INPUT_FILES[@]}" << 'EOF'
import sys
import os
import html
from html.parser import HTMLParser

# Avoid UnicodeEncodeError when printing filenames in non-UTF-8 locales
try:
    sys.stdout.reconfigure(errors='replace')
    sys.stderr.reconfigure(errors='replace')
except AttributeError:
    pass

output_file = sys.argv[1]
input_files = sys.argv[2:]
output_real = os.path.realpath(output_file)

# Folder name for bookmarks that are not inside any folder
LOOSE_FOLDER_NAME = "Others"

# Browser root folders that should NOT appear in the hierarchy.
# (Additionally, any <H3> with PERSONAL_TOOLBAR_FOLDER="true" is ignored.)
ROOT_FOLDER_NAMES = {
    "bookmarks toolbar",
    "bookmarks bar",
    "barra de favoritos",
    "barra de marcadores",
    "barra de ferramentas de favoritos",
}

# Global folder tree: each node = {"links": {url: title}, "children": {name: node}}
def new_node():
    return {"links": {}, "children": {}}

root = new_node()
seen_urls = set()


def get_node(path):
    """Returns (creating if necessary) the tree node for the given path."""
    node = root
    for name in path:
        node = node["children"].setdefault(name, new_node())
    return node


class BookmarkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        # Each <DL> pushes exactly one entry (folder name or None),
        # and each </DL> pops exactly one, keeping the stack balanced.
        self.dl_stack = []
        self.pending_folder = None   # <H3> name waiting for the next <DL>
        self.in_h3 = False
        self.h3_text = ""
        self.h3_is_root = False      # Is <H3> the bookmarks bar folder?
        self.in_a = False
        self.a_href = None
        self.a_title = ""
        self.entries = {}            # {path (tuple): {url: title}}
        self.file_seen_urls = set()

    def handle_starttag(self, tag, attrs):
        # HTMLParser already converts tag and attribute names to lowercase
        attrs_dict = dict(attrs)
        if tag == 'dt':
            # New item: discard pending folder name that did not receive <DL>
            self.pending_folder = None
        elif tag == 'h3':
            self.in_h3 = True
            self.h3_text = ""
            self.pending_folder = None
            self.h3_is_root = (
                (attrs_dict.get('personal_toolbar_folder') or "").lower() == "true"
            )
        elif tag == 'a':
            href = attrs_dict.get('href')
            if href and href.strip():
                self.in_a = True
                self.a_href = href.strip()
                self.a_title = ""
        elif tag == 'dl':
            self.dl_stack.append(self.pending_folder)
            self.pending_folder = None

    def handle_endtag(self, tag):
        if tag == 'h3':
            self.in_h3 = False
            name = self.h3_text.strip()
            # Bookmarks bar root folder: excluded from hierarchy
            if self.h3_is_root or name.casefold() in ROOT_FOLDER_NAMES:
                name = ""
            self.pending_folder = name or None
            self.h3_is_root = False
        elif tag == 'a':
            if self.in_a and self.a_href:
                # Internal per-file deduplication for individual counter
                if self.a_href not in self.file_seen_urls:
                    self.file_seen_urls.add(self.a_href)
                    path = tuple(name for name in self.dl_stack if name)
                    title = self.a_title.strip() or self.a_href
                    self.entries.setdefault(path, {})[self.a_href] = title
            self.in_a = False
            self.a_href = None
            self.a_title = ""
        elif tag == 'dl':
            if self.dl_stack:
                self.dl_stack.pop()

    def handle_data(self, data):
        if self.in_h3:
            self.h3_text += data
        elif self.in_a:
            self.a_title += data


# Reading, individual counting, and parsing of each input file
processed = set()
for filepath in input_files:
    real = os.path.realpath(filepath)

    if real == output_real:
        print(f"  [Ignored] {filepath}: is the output file itself.")
        continue
    if real in processed:
        print(f"  [Ignored] {filepath}: already processed (repeated path).")
        continue
    processed.add(real)

    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        parser = BookmarkParser()
        parser.feed(content)
        parser.close()

        # Display unique bookmark count for the input file
        file_unique_count = len(parser.file_seen_urls)
        print(f"  [Input] {filepath}: {file_unique_count} unique bookmarks found.")

        # Global merging and cross-file deduplication
        for path, links in parser.entries.items():
            target_path = path if path else (LOOSE_FOLDER_NAME,)
            for url, title in links.items():
                if url not in seen_urls:
                    seen_urls.add(url)
                    get_node(target_path)["links"][url] = title

    except Exception as e:
        print(f"Warning: Error reading file {filepath}: {e}", file=sys.stderr)

total_unique_final = len(seen_urls)
print(f"\n  [Output] Consolidated total of unique bookmarks in the final file: {total_unique_final}\n")


def write_links(f, node, pad):
    for url, title in node["links"].items():
        escaped_url = html.escape(url, quote=True)
        escaped_title = html.escape(title)
        f.write(f"{pad}<DT><A HREF=\"{escaped_url}\">{escaped_title}</A>\n")


def write_folder(f, name, node, depth):
    """Writes a folder and its subfolders recursively."""
    pad = "    " * depth
    f.write(f"{pad}<DT><H3>{html.escape(name)}</H3>\n")
    f.write(f"{pad}<DL><p>\n")
    write_links(f, node, pad + "    ")
    for child_name, child in node["children"].items():
        write_folder(f, child_name, child, depth + 1)
    f.write(f"{pad}</DL><p>\n")


# Writing the final browser-compatible HTML file (with character escaping)
try:
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n")
        f.write("<!-- This is an automatically generated file. It will be read and overwritten. -->\n")
        f.write("<!-- MIT License - Copyright (c) 2026 Tálison (https://github.com/talisondec) -->\n")
        f.write("<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n")
        f.write("<TITLE>Bookmarks</TITLE>\n")
        f.write("<H1>Bookmarks</H1>\n")
        f.write(f"<!-- Total Unique Bookmarks Count: {total_unique_final} -->\n")
        f.write("<DL><p>\n")

        write_links(f, root, "    ")
        for name, child in root["children"].items():
            write_folder(f, name, child, 1)

        f.write("</DL><p>\n")
    print(f"Success! Merged file saved to: {output_file}")
except Exception as e:
    print(f"Error writing output file: {e}", file=sys.stderr)
    sys.exit(1)
EOF
