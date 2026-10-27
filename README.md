# Bookmark Recipy

Merge, deduplicate and tidy up browser bookmark exports (`.html`) into a single clean file, ready to import back into any browser.

Point it at a few exported bookmark files (or whole folders of them) and it produces one consolidated file with every unique link, organized in a real nested folder structure.

## Features

- **Merges many files at once**: pass individual files, directories (searched recursively for `.html` / `.htm`), or a mix of both.
- **Removes duplicates**: each URL appears only once in the final file; the first folder it was found in wins.
- **Keeps your folder hierarchy**: nested folders are rebuilt as real nested folders, not flattened names like `Dev / Python`.
- **Drops the browser's root toolbar folder**: "Bookmarks Toolbar" / "Bookmarks bar" no longer prefix every category. Detected through the `PERSONAL_TOOLBAR_FOLDER` attribute, with a name-based fallback.
- **Collects loose bookmarks**: links that were not inside any folder go into an `Others` folder.
- **Shows counters**: unique bookmarks found in each input file, plus the consolidated total.
- **Safe to re-run**: skips the output file if it is inside an input directory, and ignores repeated paths.
- **Browser-compatible output**: standard Netscape bookmark format with proper HTML escaping.

## Requirements

- Bash
- Python 3 (standard library only, no extra packages)

## Usage

```bash
chmod +x bookmark-recipy-ver1.sh
./bookmark-recipy-ver1.sh <output.html> <directory_or_file_1> [file_2 ...]
```

### Example

```bash
./bookmark-recipy-ver1.sh my_bookmarks.html ~/Downloads/bookmarks/ loose_file.html
```

Sample output:

```
Processing 3 file(s) found...

[Input] /home/user/Downloads/bookmarks/firefox.html: 412 unique bookmarks found.
[Input] /home/user/Downloads/bookmarks/chrome.html: 530 unique bookmarks found.
[Input] loose_file.html: 58 unique bookmarks found.

[Output] Consolidated total of unique bookmarks in the final file: 871

Success! Merged file saved to: my_bookmarks.html
```

Then import `my_bookmarks.html` in your browser (Firefox: *Bookmarks → Manage Bookmarks → Import and Backup → Import Bookmarks from HTML*; Chrome/Edge: *Bookmarks → Import bookmarks and settings → Bookmarks HTML file*).

## Customization

Open the script and edit the constants at the top of the embedded Python block:

- `ROOT_FOLDER_NAMES`: add the name of any top-level folder your browser uses that you do not want in the result (for example "Other Bookmarks").
- `LOOSE_FOLDER_NAME`: the folder name used for bookmarks that were not inside any folder (default `Others`).

## Notes and limitations

- Duplicates are detected by exact URL string, so `http://example.com` and `http://example.com/` count as different links.
- Extra attributes such as `ADD_DATE` and icons are not preserved; only folder names, URLs and titles are kept.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 [Tálison](https://github.com/talisondec).
