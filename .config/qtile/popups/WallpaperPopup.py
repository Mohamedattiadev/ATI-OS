import os
import random
import threading
import subprocess
from qtile_extras.popup import PopupRelativeLayout, PopupText, PopupImage
from libqtile.log_utils import logger

# =============================================================================
# PIL IMPORT SAFETY
# =============================================================================
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    Image = None
    HAS_PIL = False
    logger.warning("PIL not found. Install python-pillow for fast wallpaper previews.")

# =============================================================================
# GLOBAL STATE
# =============================================================================
_WALLPAPER_LAYOUT = None
_IMAGES = []
_INDEX = 0
_COL_OFFSET = 0
_CURRENT_WALL = None

# =============================================================================
# CONFIG & STYLING
# =============================================================================
WALLPAPER_DIR = os.path.expanduser("~/Pictures/Wallpapers")
CACHE_WALL = os.path.expanduser("~/.cache/wall")
CACHE_THUMBS = os.path.expanduser("~/.cache/qtile_thumbs")

ROWS_PER_COL = 21  # Adjusted for better vertical spacing
COL_COUNT = 3
MAX_NAME_LEN = 26

# DOOM ONE PALETTE (Enhanced)
COLORS = {
    "bg": "#1c1f24",
    "fg": "#bbc2cf",
    "muted": "#5b6268",
    "blue": "#51afef",
    "cyan": "#46d9ff",
    "green": "#98be65",
    "purple": "#c678dd",
    "red": "#ff6c6b",
    "line": "#2a2e36",
    "dark": "#1b1b1b",
    "highlight_bg": "#51afef", # The background of selected item
    "highlight_fg": "#1c1f24"  # The text color of selected item
}

# =============================================================================
# HELPERS
# =============================================================================
def load_images():
    if not os.path.isdir(WALLPAPER_DIR):
        return []
    os.makedirs(CACHE_THUMBS, exist_ok=True)
    return sorted(
        os.path.join(WALLPAPER_DIR, f)
        for f in os.listdir(WALLPAPER_DIR)
        if f.lower().endswith((".png", ".jpg", ".jpeg", ".webp"))
    )

def load_current_wallpaper():
    if os.path.exists(CACHE_WALL):
        try:
            with open(CACHE_WALL) as f:
                return f.read().strip()
        except Exception:
            pass
    return None

def get_thumbnail_path(original_path):
    if not HAS_PIL:
        return original_path
    
    filename = os.path.basename(original_path)
    thumb_path = os.path.join(CACHE_THUMBS, filename)

    if os.path.exists(thumb_path):
        return thumb_path
    return original_path

def generate_thumbnails_background():
    if not HAS_PIL or Image is None:
        return
    for img_path in _IMAGES:
        filename = os.path.basename(img_path)
        thumb_path = os.path.join(CACHE_THUMBS, filename)
        if not os.path.exists(thumb_path):
            try:
                with Image.open(img_path) as img:
                    img.thumbnail((600, 600))
                    img.save(thumb_path)
            except Exception:
                pass

def truncate(name: str) -> str:
    # Ensure name fills the space for the background color to look like a bar
    if len(name) > MAX_NAME_LEN:
        name = name[:MAX_NAME_LEN - 1] + "…"
    return f"{name:<{MAX_NAME_LEN}}"

def index_to_pos(i):
    return i % ROWS_PER_COL, i // ROWS_PER_COL

def pos_to_index(row, col):
    idx = col * ROWS_PER_COL + row
    return idx if 0 <= idx < len(_IMAGES) else None

def render_column(visible_col):
    lines = []
    actual_col = visible_col + _COL_OFFSET

    for row in range(ROWS_PER_COL):
        idx = pos_to_index(row, actual_col)
        
        if idx is None:
            break

        path = _IMAGES[idx]
        filename = os.path.basename(path)
        display_name = truncate(filename)
        
        is_selected = idx == _INDEX
        is_current = path == _CURRENT_WALL

        # --- ENHANCED STYLING LOGIC ---
        if is_selected:
            # "Card" style: Solid background block
            icon = "  " # Circle icon
            text = (
                f'<span background="{COLORS["highlight_bg"]}" foreground="{COLORS["highlight_fg"]}" weight="bold">'
                f'{icon} {display_name}</span>'
            )
        elif is_current:
            # Green checkmark for active
            icon = "  " # Checkmark
            text = (
                f'<span foreground="{COLORS["green"]}" weight="bold">'
                f'{icon} {display_name}</span>'
            )
        else:
            # Standard item
            icon = "  " # Empty circle
            text = (
                f'<span foreground="{COLORS["fg"]}">'
                f'{icon} {display_name}</span>'
            )
            
        lines.append(text)

    return "\n".join(lines)

def render_footer():
    """Returns the markup for the footer status bar."""
    if not _IMAGES:
        return ""
    
    current_img = _IMAGES[_INDEX]
    filename = os.path.basename(current_img)
    
    # Calculate scroll percentage
    percent = int(((_INDEX + 1) / len(_IMAGES)) * 100)
    
    count_str = f" {percent}% "
    
    return (
        f'<span foreground="{COLORS["highlight_bg"]}" weight="bold">   IMAGE: </span>'
        f'<span foreground="{COLORS["fg"]}">{filename}</span>   '
        f'<span foreground="{COLORS["muted"]}">│</span>   '
        f'<span foreground="{COLORS["purple"]}" weight="bold">{count_str}</span>'
        f'<span foreground="{COLORS["muted"]}">of {len(_IMAGES)}</span>'
    )

# =============================================================================
# WALLPAPER ACTION
# =============================================================================
def apply_wallpaper():
    global _CURRENT_WALL
    path = _IMAGES[_INDEX]

    subprocess.run(["xwallpaper", "--stretch", path], check=False)

    os.makedirs(os.path.dirname(CACHE_WALL), exist_ok=True)
    with open(CACHE_WALL, "w") as f:
        f.write(path)

    _CURRENT_WALL = path

# =============================================================================
# SEARCH & RANDOM FUNCTIONS
# =============================================================================
def jump_to_random():
    global _INDEX
    if not _IMAGES:
        return
    
    # Pick random index
    new_idx = random.randint(0, len(_IMAGES) - 1)
    
    # Update state and ensure visibility
    _INDEX = new_idx
    ensure_visible()
    update_ui()

def fuzzy_search_rofi():
    global _INDEX
    if not _IMAGES:
        return

    # Create a list of names for Rofi
    names = "\n".join([os.path.basename(p) for p in _IMAGES])
    
    try:
        # Run rofi to get selection
        result = subprocess.run(
            ["rofi", "-dmenu", "-p", "Search Wallpaper", "-i", "-theme-str", 'window {width: 50%;}'],
            input=names.encode(),
            stdout=subprocess.PIPE,
            check=False
        )
        
        selected_name = result.stdout.decode().strip()
        
        if selected_name:
            # Find the index of the selected name
            for idx, path in enumerate(_IMAGES):
                if os.path.basename(path) == selected_name:
                    _INDEX = idx
                    ensure_visible()
                    update_ui()
                    return
    except Exception as e:
        logger.error(f"Wallpaper Search Error: {e}")

# =============================================================================
# POPUP CONTROL
# =============================================================================
def show_wallpaper_picker(qtile):
    global _WALLPAPER_LAYOUT, _IMAGES, _INDEX, _COL_OFFSET, _CURRENT_WALL

    if _WALLPAPER_LAYOUT:
        return

    _IMAGES = load_images()
    if not _IMAGES:
        return

    _INDEX = 0
    _COL_OFFSET = 0
    _CURRENT_WALL = load_current_wallpaper()

    threading.Thread(target=generate_thumbnails_background, daemon=True).start()

    controls = []

    # ---------------- HEADER ----------------
    controls.append(
        PopupText(


text=(
        f'<span size="xx-large" weight="bold" foreground="{COLORS["blue"]}">'
        f'󰸉  WALLPAPER SELECTOR</span>\n'
        f'<span foreground="{COLORS["muted"]}">'
        f'Navigate : <b><span foreground="{COLORS["green"]}">hjkl</span></b>'
        f'<span foreground="{COLORS["blue"]}"><b>  |  </b></span>'
        f'Search : <b><span foreground="{COLORS["purple"]}">/</span></b>'
        f'<span foreground="{COLORS["blue"]}"><b>  |  </b></span>'
        f'Random : <b><span foreground="{COLORS["green"]}">R</span></b>'
        f'<span foreground="{COLORS["blue"]}"><b>  |  </b></span>'
        f'Apply : <b><span foreground="{COLORS["purple"]}">Enter</span></b>'
        f'</span>'
    ),
            markup=True,
            pos_x=0.05,
            pos_y=0.05,
            width=0.9,
            height=0.1,
            h_align="center",
        )
    )

    # ---------------- LINE DIVIDER ----------------
    controls.append(
         PopupText(
             text=f'<span foreground="{COLORS["line"]}">{"━" * 80}</span>',
             markup=True,
             pos_x=0.05, pos_y=0.13, width=0.9, height=0.05, h_align="center"
         )
    )

    # ---------------- COLUMNS ----------------
    start_x = 0.05
    col_width = 0.16 # Adjusted for layout
    gap = 0.01

    for c in range(COL_COUNT):
        controls.append(
            PopupText(
                text=render_column(c),
                markup=True,
                pos_x=start_x + c * (col_width + gap),
                pos_y=0.18,
                width=col_width,
                height=0.68,
                h_align="left",
                v_align="top",
                name=f"col{c}",
            )
        )

    # ---------------- PREVIEW IMAGE ----------------
    preview_img = get_thumbnail_path(_IMAGES[_INDEX])
    controls.append(
        PopupImage(
            filename=preview_img,
            pos_x=0.58,
            pos_y=0.18,
            width=0.37,
            height=0.68,
            preserve_aspect=True,
            name="preview",
        )
    )
    
    # ---------------- FOOTER ----------------
    controls.append(
        PopupText(
            text=render_footer(),
            markup=True,
            pos_x=0.05,
            pos_y=0.90,
            width=0.9,
            height=0.08,
            h_align="center",
            v_align="center",
            name="footer"
        )
    )

    _WALLPAPER_LAYOUT = PopupRelativeLayout(
        qtile,
        width=1050,
        height=680,
        background=COLORS["bg"] + "F2", # F2 = High opacity but not 100%
        close_on_click=False,
        controls=controls,
    )

    _WALLPAPER_LAYOUT.show(centered=True)


def close_wallpaper_picker():
    global _WALLPAPER_LAYOUT
    if _WALLPAPER_LAYOUT:
        _WALLPAPER_LAYOUT.hide()
        _WALLPAPER_LAYOUT = None

def toggle_wallpaper_picker(qtile):
    if _WALLPAPER_LAYOUT:
        close_wallpaper_picker()
    else:
        show_wallpaper_picker(qtile)

# =============================================================================
# NAVIGATION LOGIC
# =============================================================================
def ensure_visible():
    """Calculates _COL_OFFSET to make sure _INDEX is visible."""
    global _COL_OFFSET
    
    # Calculate which column the current index is in (globally)
    row, col = index_to_pos(_INDEX)
    
    # If the column is to the left of our view
    if col < _COL_OFFSET:
        _COL_OFFSET = col
    # If the column is to the right of our view
    elif col >= _COL_OFFSET + COL_COUNT:
        _COL_OFFSET = col - COL_COUNT + 1

def update_ui():
    """Redraws the UI components efficiently."""
    if _WALLPAPER_LAYOUT is None:
        return

    updates = {}
    updates["preview"] = get_thumbnail_path(_IMAGES[_INDEX])
    updates["footer"] = render_footer()
    
    for c in range(COL_COUNT):
        updates[f"col{c}"] = render_column(c)

    _WALLPAPER_LAYOUT.update_controls(**updates)

def move(drow=0, dcol=0):
    global _INDEX

    if _WALLPAPER_LAYOUT is None:
        return

    row, col = index_to_pos(_INDEX)
    new_row = row + drow
    new_col = col + dcol
    idx = pos_to_index(new_row, new_col)

    # Wrap logic for right movement at end of list
    if idx is None and dcol != 0:
        max_cols = (len(_IMAGES) // ROWS_PER_COL) + 1
        if 0 <= new_col < max_cols:
             idx = len(_IMAGES) - 1
        else:
             return 
    
    if idx is None:
        return

    _INDEX = idx
    ensure_visible()
    update_ui()

def apply(qtile):
    apply_wallpaper()
    close_wallpaper_picker()
    qtile.ungrab_chord()
