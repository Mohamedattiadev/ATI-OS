# ~/.config/qtile/homerow.py
import pyatspi
from libqtile.popup import Popup
from libqtile.lazy import lazy
from libqtile.log_utils import logger

# Constants
HINT_CHARS = "ASDFGHJKLQWERTYUIOP"
SCROLL_ROLES = {
    "scroll pane",
    "viewport",
    "panel",
    "terminal",
    "text",
    "list",
    "table",
    "document web",
}

# Global State (Active Hints)
# Structure: { "A": { "node": atspi_node, "popup": popup_obj }, ... }
active_hints = {}


def get_focused_subtree():
    """
    Finds the accessible node corresponding to the currently focused window.
    This is critical to avoid scanning the entire desktop.
    """
    registry = pyatspi.Registry
    desktop = registry.getDesktop(0)

    # Heuristic: Find the application with the focused state
    # Note: iterating registry can be slow; we do a shallow search first.
    for app in desktop:
        try:
            # Check children (windows) of the app
            for window in app:
                state = window.getState()
                if state.contains(pyatspi.STATE_ACTIVE) or state.contains(
                    pyatspi.STATE_FOCUSED
                ):
                    return window
        except:
            continue
    return None


def collect_scrollable_nodes(node, targets, depth=0, max_depth=15):
    """
    Recursively finds scrollable or interactable elements.
    """
    if depth > max_depth:
        return

    try:
        role = node.getRoleName().lower()
        state = node.getState()
    except:
        return

    # Filter: Must be showing and visible
    if not (
        state.contains(pyatspi.STATE_SHOWING) and state.contains(pyatspi.STATE_VISIBLE)
    ):
        return

    # Check if this node is interesting (Scrollable or specific roles)
    is_scrollable = role in SCROLL_ROLES

    if is_scrollable:
        try:
            comp = node.queryComponent()
            # GET_SCREEN_COORDS is usually more reliable for overlays
            x, y, w, h = comp.getExtents(pyatspi.DESKTOP_COORDS)

            # Filter tiny elements (likely invisible layout containers)
            if w > 40 and h > 40:
                targets.append((node, x, y, w, h))
        except:
            pass

    # Recurse children
    # We limit child count to avoid hanging on massive lists (like complex web pages)
    try:
        child_count = node.childCount
        # Limit checking to first 50 children for performance
        count = min(child_count, 50)
        for i in range(count):
            collect_scrollable_nodes(
                node.getChildAtIndex(i), targets, depth + 1, max_depth
            )
    except:
        pass


@lazy.function
def start_homerow(qtile):
    """
    Entry point: Scans UI, draws hints, and prepares the state.
    """
    global active_hints

    # 1. Cleanup old state if exists
    if active_hints:
        cleanup_homerow(qtile)

    # 2. Get Targets
    root = get_focused_subtree()
    if not root:
        logger.warning("Homerow: No active AT-SPI window found.")
        return

    targets = []
    collect_scrollable_nodes(root, targets)

    # 3. Draw Hints
    logger.warning(f"Homerow: Found {len(targets)} targets.")

    for i, (node, x, y, w, h) in enumerate(targets):
        if i >= len(HINT_CHARS):
            break

        char = HINT_CHARS[i]

        # Create Qtile Popup
        popup = Popup(
            qtile,
            x=x + 10,  # Offset slightly inside the region
            y=y + 10,
            width=24,
            height=24,
            background="#d75f5f",  # Red-ish for high visibility
            foreground="#ffffff",
            opacity=0.9,
            border="#ffffff",
            border_width=1,
        )

        # Center text roughly
        popup.text = char
        popup.draw_text(text=char, x=6, y=2)
        popup.show()

        active_hints[char] = {"node": node, "popup": popup}


@lazy.function
def resolve_hint(qtile, char):
    """
    Called when a user presses a hint key (A, S, D...).
    Executes the action and cleans up.
    """
    global active_hints
    char = char.upper()

    if char in active_hints:
        target = active_hints[char]
        node = target["node"]

        logger.warning(f"Homerow: Scrolling node {char}")

        # Try to Scroll
        try:
            # Try specific Scroll interface first
            # 6 = ScrollType.BOTTOM_RIGHT / DOWN (varies by implementation)
            # usually we want to focus it or scroll.
            # Let's try to grab focus first, then scroll.
            comp = node.queryComponent()
            comp.grabFocus()

            # If it implements scrolling directly:
            # node.queryComponent().scrollTo(pyatspi.ScrollType.TOP_LEFT)

            # Simple fallback: If we focused it, we can use xdotool or qtile to send keys
            # But let's try the AT-SPI scroll action if available
            # Many widgets don't support scrollTo well.
            pass
        except Exception as e:
            logger.error(f"Homerow Action Failed: {e}")

    # Always cleanup after selection
    cleanup_homerow(qtile)


def cleanup_homerow(qtile):
    global active_hints
    for char, data in active_hints.items():
        data["popup"].hide()
        data["popup"].kill()
    active_hints = {}
