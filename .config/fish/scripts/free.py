#!/usr/bin/env python3

import subprocess
from rich.console import Console
from rich.table import Table
from rich.style import Style
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

def get_memory_info():
    try:
        result = subprocess.run(['free', '-m'], capture_output=True, text=True, check=True)
        return result.stdout.splitlines()
    except subprocess.CalledProcessError as e:
        print(f"Error running free command: {e}")
        return []

def parse_memory_info(lines):
    if len(lines) < 2:
        return {}
    
    headers = lines[0].split()
    mem_info = lines[1].split()
    swap_info = lines[2].split() if len(lines) > 2 else []
    
    return {
        'headers': headers,
        'memory': mem_info[1:],  # Skip "Mem:"
        'swap': swap_info[1:] if swap_info else None
    }

def create_memory_table(info):
    table = Table(
        title="Memory Usage (MB)",
        show_header=True,
        header_style=f"bold {DRACULA_THEME['blue']}",
        box=box.ROUNDED,
        border_style=DRACULA_THEME['blue'],
        style=DRACULA_THEME['foreground']
    )
    
    # Add columns
    table.add_column("Type", style=DRACULA_THEME['purple'], min_width=5)
    for header in info['headers']:
        if header in ['total', 'available']:
            style = DRACULA_THEME['cyan']
        elif header == 'used':
            style = DRACULA_THEME['red']
        elif header == 'free':
            style = DRACULA_THEME['green']
        else:
            style = DRACULA_THEME['comment']
        table.add_column(header, justify="right", style=style, min_width=7)
    
    # Add memory row
    mem = info['memory']
    total_mem = int(mem[0]) if len(mem) > 0 else 0
    used_mem = int(mem[1]) if len(mem) > 1 else 0
    used_percent = (used_mem / total_mem) * 100 if total_mem > 0 else 0
    
    mem_style = (
        Style(color=DRACULA_THEME['red'], bold=True) if used_percent > 90 else
        Style(color=DRACULA_THEME['orange']) if used_percent > 70 else
        Style(color=DRACULA_THEME['green'])
    )
    table.add_row("Mem", *mem, style=mem_style)
    
    # Add swap row if available
    if info['swap']:
        swap = info['swap']
        total_swap = int(swap[0]) if len(swap) > 0 else 0
        used_swap = int(swap[1]) if len(swap) > 1 else 0
        swap_percent = (used_swap / total_swap) * 100 if total_swap > 0 else 0
        
        swap_style = (
            Style(color=DRACULA_THEME['red'], bold=True) if swap_percent > 90 else
            Style(color=DRACULA_THEME['orange']) if swap_percent > 70 else
            Style(color=DRACULA_THEME['yellow'])
        )
        table.add_row("Swap", *swap, style=swap_style)
    
    # Add usage summary
    table.add_section()
    usage_values = [f"{used_percent:.1f}%"]
    if info['swap']:
        usage_values.append(f"{swap_percent:.1f}%")
    usage_row = ["Usage"] + usage_values + [""] * (len(info['headers']) - len(usage_values) - 1)
    table.add_row(*usage_row, style=Style(color=DRACULA_THEME['pink'], bold=True))
    
    return table

def main():
    console = Console()
    lines = get_memory_info()
    if not lines:
        console.print(f"[{DRACULA_THEME['red']}]Error getting memory info[/]")
        return
    
    info = parse_memory_info(lines)
    if not info:
        console.print(f"[{DRACULA_THEME['red']}]No memory information available[/]")
        return
    
    table = create_memory_table(info)
    console.print(table)

if __name__ == "__main__":
    main()
