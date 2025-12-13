#!/usr/bin/env python3

import subprocess
import os
import sys
from rich.console import Console
from rich.table import Table
from rich.style import Style
from rich.text import Text
from rich import box

# Dracula Theme Colors
DRACULA_THEME = {
    "pink": "#ff79c6",
    "orange": "#ffb86c",
    "red": "#ff5555",
    "foreground": "#f8f8f2",
    "green": "#50fa7b",
    "purple": "#bd93f9",
    "yellow": "#f1fa8c",
    "comment": "#6272a4",
    "cyan": "#8be9fd",
    "blue": "#51afef"
}

def get_size(path):
    """Get human-readable size of a file/directory"""
    try:
        result = subprocess.run(['du', '-sh', path], capture_output=True, text=True, check=True)
        return result.stdout.split()[0]
    except subprocess.CalledProcessError:
        return "N/A"

def get_directory_contents(path):
    """Get contents of directory with sizes"""
    if not os.path.isdir(path):
        return None
    
    contents = []
    try:
        with os.scandir(path) as entries:
            for entry in entries:
                if entry.name.startswith('.'):
                    continue
                contents.append({
                    'name': entry.name,
                    'size': get_size(entry.path),
                    'is_dir': entry.is_dir()
                })
        return sorted(contents, key=lambda x: (not x['is_dir'], x['name'].lower()))
    except PermissionError:
        return None

def show_directory_contents(path):
    """Display directory contents in a table"""
    console = Console()
    contents = get_directory_contents(path)
    if not contents:
        console.print(f"[{DRACULA_THEME['orange']}]Could not read directory contents[/]")
        return

    # Use just the directory name in title to avoid wrapping
    table = Table(
        title=f"Contents of [bold]{os.path.basename(path)}[/]",
        show_header=True,
        header_style=f"bold {DRACULA_THEME['blue']}",
        box=box.ROUNDED,  # <- Change this line
        style=DRACULA_THEME['foreground'],
        border_style=DRACULA_THEME['blue'],  # Optional: match disk info style
        show_edge=True     # <- Ensure border is shown
    )

    table.add_column("Name", style=DRACULA_THEME['cyan'])
    table.add_column("Size", justify="right", style=DRACULA_THEME['yellow'])
    table.add_column("Type", style=DRACULA_THEME['green'])

    for item in contents:
        item_type = "📁 Dir" if item['is_dir'] else "📄 File"
        table.add_row(
            item['name'],
            item['size'],
            item_type
        )

    console.print(table)

def show_full_disk_info(path=None):
    """Display full disk usage information"""
    console = Console()
    cmd = ['df', '-h']
    if path:
        cmd.append(path)

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        lines = result.stdout.splitlines()
        
        # Fix "Mounted on" header splitting
        header_line = lines[0].replace("Mounted on", "Mounted_on")
        headers = header_line.split()
        headers = [h.replace("Mounted_on", "Mounted on") for h in headers]

        table = Table(
            title="Disk Usage" + (f" for {path}" if path else ""),
            show_header=True,
            header_style=f"bold {DRACULA_THEME['blue']}",
            box=box.ROUNDED,
            border_style=DRACULA_THEME['blue'],
            style=DRACULA_THEME['foreground']
        )

        for header in headers:
            if header in ['Size', 'Avail']:
                style = DRACULA_THEME['cyan']
            elif header == 'Used':
                style = DRACULA_THEME['orange']
            elif header == 'Use%':
                style = DRACULA_THEME['foreground']
            else:
                style = DRACULA_THEME['purple']
            table.add_column(header, justify="right" if header != 'Filesystem' else "left", style=style)

        for line in lines[1:]:
            parts = line.split()
            if len(parts) >= 6:
                use_percent = int(parts[4].replace('%', ''))
                use_style = (Style(color=DRACULA_THEME['red'], bold=True) if use_percent > 90 
                             else Style(color=DRACULA_THEME['orange']) if use_percent > 70 
                             else Style(color=DRACULA_THEME['green']))

                row = [
                    parts[0],
                    Text(parts[1], style=DRACULA_THEME['cyan']),
                    Text(parts[2], style=DRACULA_THEME['orange']),
                    Text(parts[3], style=DRACULA_THEME['cyan']),
                    Text(parts[4], style=use_style),
                    ' '.join(parts[5:])
                ]
                table.add_row(*row)

        console.print(table)
    except subprocess.CalledProcessError:
        console.print(f"[{DRACULA_THEME['red']}]Error getting disk information[/]")

def main():
    # Determine if we're showing just contents (dfh) or full info
    is_dfh = os.path.basename(sys.argv[0]) == 'dfh'

    if is_dfh:
        # dfh - show contents of current directory
        target = os.getcwd()
        show_directory_contents(target)
    elif len(sys.argv) > 1:
        # df <path> - show contents of specified directory
        target = os.path.abspath(sys.argv[1])
        if os.path.isdir(target):
            show_directory_contents(target)
        else:
            # Show disk info for specific path
            show_full_disk_info(target)
    else:
        # df - show full disk info
        show_full_disk_info()

if __name__ == "__main__":
    main()
