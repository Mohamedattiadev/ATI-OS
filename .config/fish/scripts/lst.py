#!/usr/bin/env python3

import os
import argparse
from datetime import datetime
from stat import filemode
import time

# Import the necessary components from the rich library
from rich.console import Console
from rich.table import Table
from rich.text import Text
from rich import box
from rich.style import Style

# --- New "Dracula" Color and Icon Theme ---
# Using specific hex codes for a cohesive theme.
DRACULA_THEME = {
    # Type: (Icon, Style)
    "image":   ("🖼️", Style(color="#ff79c6")), # Pink
    "audio":   ("🎵", Style(color="#ffb86c")), # Orange
    "video":   ("🎬", Style(color="#ffb86c")), # Orange
    "archive": ("📦", Style(color="#ff5555")), # Red
    "doc":     ("📄", Style(color="#f8f8f2")), # Foreground
    "exec":    ("⚙️", Style(color="#50fa7b", bold=True)), # Green
    "dir":     ("📁", Style(color="#bd93f9", bold=True)), # Purple
    "link":    ("🔗", Style(color="#f1fa8c", bold=True)), # Yellow
    "file":    ("📝", Style(color="#6272a4")), # Comment/Dim
}

# Mapping extensions to file types
EXTENSIONS_TO_TYPE = {
    ".jpg": "image", ".jpeg": "image", ".png": "image", ".gif": "image",
    ".bmp": "image", ".svg": "image", ".webp": "image",
    ".mp3": "audio", ".wav": "audio", ".ogg": "audio", ".flac": "audio",
    ".aac": "audio", ".m4a": "audio",
    ".mp4": "video", ".mkv": "video", ".mov": "video", ".avi": "video",
    ".zip": "archive", ".tar": "archive", ".gz": "archive", ".rar": "archive",
    ".7z": "archive", ".bz2": "archive", ".xz": "archive",
    ".doc": "doc", ".docx": "doc", ".pdf": "doc", ".txt": "doc", ".md": "doc",
}

def format_size(size_bytes: int) -> Text:
    """Converts a size in bytes to a human-readable and styled Text object."""
    if size_bytes < 1024:
        return Text(f"{size_bytes} B", style="#6272a4") # Comment/Dim
    for unit in ["", "K", "M", "G", "T", "P"]:
        if abs(size_bytes) < 1024.0:
            # Use bold for Gigabytes and up
            style = "bold" if unit in ["G", "T", "P"] else "normal"
            return Text(f"{size_bytes:3.1f}{unit}B", style=style)
        size_bytes /= 1024.0
    return Text(f"{size_bytes:.1f}EB", style="bold")

def format_permissions(mode: int) -> Text:
    """Creates a styled Text object for file permissions using the Dracula theme."""
    perms = filemode(mode)
    text = Text()
    # Type character ('d' for directory, 'l' for link, etc.)
    text.append(perms[0], style="#bd93f9" if perms[0] == 'd' else "#f1fa8c" if perms[0] == 'l' else "#f8f8f2")
    # User, Group, Other permissions
    for i in range(1, 10, 3):
        text.append(perms[i],   style="#8be9fd" if perms[i]   != '-' else "#6272a4") # Read (Cyan)
        text.append(perms[i+1], style="#ffb86c" if perms[i+1] != '-' else "#6272a4") # Write (Orange)
        text.append(perms[i+2], style="#50fa7b" if perms[i+2] != '-' else "#6272a4") # Execute (Green)
    return text

def format_date(mod_timestamp: float) -> Text:
    """Creates a styled Text object for the modified date based on its age."""
    age_seconds = time.time() - mod_timestamp
    if age_seconds < 60 * 60 * 24 * 7: # Less than a week
        style = "#f1fa8c" # Yellow
    elif age_seconds < 60 * 60 * 24 * 365: # Less than a year
        style = "#6272a4" # Comment/Dim
    else: # Older
        style = "dim #6272a4"
    
    date_str = datetime.fromtimestamp(mod_timestamp).strftime('%d %b %Y %H:%M')
    return Text(date_str, style=style)

def get_file_type(entry: os.DirEntry) -> str:
    """Determines the file type string for a given directory entry."""
    if entry.is_dir():
        return "dir"
    if entry.is_symlink():
        return "link"
    
    file_ext = os.path.splitext(entry.name)[1].lower()
    if file_ext in EXTENSIONS_TO_TYPE:
        return EXTENSIONS_TO_TYPE[file_ext]

    if os.access(entry.path, os.X_OK):
        return "exec"
        
    return "file"

def list_directory(directory_path: str, show_all: bool):
    """Lists the contents of a directory in a rich, formatted table."""
    console = Console(force_terminal=True, theme=None)
    
    table = Table(show_header=True, header_style="bold #51afef", box=box.ROUNDED, border_style="#51afef")
    
    # Add index column first
    table.add_column("#", justify="right", style="#51afef", no_wrap=True)  # Dim/comment color
    table.add_column("Name", min_width=20)
    table.add_column("Size", justify="right", style="#8be9fd") # Cyan
    table.add_column("Permissions", no_wrap=True)
    table.add_column("Modified", no_wrap=True)

    try:
        entries = list(os.scandir(directory_path))
        # if not show_all:
        #     entries = [e for e in entries if not e.name.startswith('.')]
        # Sort directories first, then files, all alphabetically
        entries.sort(key=lambda e: (e.is_dir(), e.name.lower()), reverse=True)
    except FileNotFoundError:
        console.print(f"[bold #ff5555]Error: Directory not found: {directory_path}[/bold #ff5555]")
        return
    except PermissionError:
        console.print(f"[bold #ff5555]Error: Permission denied for directory: {directory_path}[/bold #ff5555]")
        return

    for index, entry in enumerate(entries, start=1):
        try:
            stat_info = entry.stat(follow_symlinks=False)
            file_type = get_file_type(entry)
            
            icon, style = DRACULA_THEME.get(file_type, DRACULA_THEME["file"])
            
            display_name = f"{icon} {entry.name}"
            name_text = Text(display_name, style=style)
            
            size_text = format_size(stat_info.st_size) if not entry.is_dir() else Text("-", style="#6272a4")
            permissions_text = format_permissions(stat_info.st_mode)
            mod_time_text = format_date(stat_info.st_mtime)

            # Add row with index first
            table.add_row(
                Text(str(index), style="#51afef"),  # Index number
                name_text, 
                size_text, 
                permissions_text, 
                mod_time_text
            )
        except OSError as e:
            table.add_row(
                Text(str(index), style="#6272a4"),
                Text(f"❌ Error reading {entry.name}: {e}", style="#ff5555")
            )

    console.print(table)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="A modern, Python-based file lister with a Dracula color theme.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "directory", nargs="?", default=".",
        help="The directory to list (defaults to current directory)."
    )
    parser.add_argument(
        "-a", "--all", action="store_true",
        help="Show all files, including hidden ones."
    )
    args = parser.parse_args()
    
    list_directory(args.directory, args.all)
