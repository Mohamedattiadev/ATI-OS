
import time

from libqtile.lazy import lazy
from libqtile import hook
from libqtile.backend.base.window import Window

obsidian_group = "S"
obsidian_class = "obsidian"
anki_group = "S"
qute_group = "2"
anki_class = "Anki"
# Substring-matched by _matches_class(), so this also catches the plain
# GTK "pcmanfm" if one is somehow open -- but the spawn below is the Qt one.
file_manager_class = "pcmanfm"
qute_class = "qutebrowser"
brave_group = "5"
brave_class = "brave-browser"
google_chrome_class = "google-chrome"
terminal_class = "kitty"
terminal_group = "4"
file_manager_group = "3"
google_chrome_group = "6"
telegram_group = "9"
telegram_name_prefix = "Telegram"

# "Where did I come from", per screen. One slot shared by every toggle on
# purpose -- these keys are one alt-tab between two groups, not seven
# independent histories -- but NOT shared across monitors: screen 0 and
# screen 1 show different groups, so a single slot meant a toggle on the
# external screen overwrote the way back on the laptop screen and vice
# versa. What a slot must never hold is the group that screen is showing;
# see _remember() and _go_back(), which is where the old code went wrong.
last_group: dict[int, str] = {}

# app class -> monotonic timestamp of the last spawn we issued for it.
_last_spawn: dict[str, float] = {}


def _matches_class(wm_class, cls: str) -> bool:
    """Case-insensitive substring test against every WM_CLASS field.

    The old test was `cls in wm_class` -- exact membership of the pair --
    which is far too strict for how apps actually set WM_CLASS. Telegram
    reports ("telegram-desktop", "TelegramDesktop"), so the configured
    "Telegram" never matched, toggle_telegram() never found the running
    window, and Mod+Shift+T fell through to the spawn branch and launched
    another copy every single time.

    toggle_terminal() already did it this way; the rest did not. Doing it
    here fixes Telegram and hardens brave/anki/obsidian/qutebrowser/
    pcmanfm against the same class of mismatch (e.g. "brave-browser" vs
    "Brave-browser").
    """
    if not wm_class:
        return False
    needle = cls.lower()
    return any(needle in (c or "").lower() for c in wm_class)


def _matches_instance(wm_class, cls: str) -> bool:
    """Exact, case-insensitive test against the INSTANCE field only.

    WM_CLASS is a pair, (instance, class). _matches_class() tests a substring
    against BOTH halves, which is right for apps that spell their class
    inconsistently -- and catastrophic for Brave, because the scratchpad
    dropdowns are Brave too:

        main browser   ("brave-browser",   "Brave-browser")
        WhatsApp       ("web.whatsapp.com","Brave-browser")
        DeepSeek       ("chat.deepseek.com","Brave-browser")
        ChatGPT        ("chat.openai.com", "Brave-browser")

    "brave-browser" is a case-insensitive substring of "Brave-browser", so
    the loose test matched all four. Only the instance half distinguishes
    them, and it is exactly what the ScratchPad's own Match(wm_instance_class=)
    rules key on -- so this is the same identity the rest of the config uses.
    """
    if not wm_class:
        return False
    return (wm_class[0] or "").lower() == cls.lower()


def _matcher(exact_instance: bool):
    return _matches_instance if exact_instance else _matches_class


def _is_scratchpad(win) -> bool:
    """True for a window owned by the ScratchPad group.

    A dropdown never belongs to a numbered workspace, so focusing one via
    _focus_window_and_group() -- which switches to a group the window is not
    in and then asks that group to focus it -- silently does nothing. That
    is the "Mod+B sometimes just doesn't open Brave" report: whichever Brave
    window happened to come first in windows_map won, and if that was the
    WhatsApp or DeepSeek dropdown the keypress went nowhere at all.

    Note this matters for Mod+N too: term1/term2 are kitty dropdowns.
    """
    group = getattr(win, "group", None)
    return getattr(group, "name", None) == "scratchpad"


def _is_secondary(win) -> bool:
    """True for a dialog / transient / utility window, not the app proper.

    Same two X11 questions config.py's _is_secondary_window() asks, applied
    to a managed window instead of a freshly-managed client.

    Two separate bugs needed this. Picking a target: Anki's Add/Browse/
    Preview windows and Obsidian's modals all carry the app's own WM_CLASS,
    and _find_window_by_class() returned whichever came first in the
    insertion-ordered windows_map -- so the key could land you on a dialog,
    or on nothing at all if that dialog had already been closed. Returning
    home: closing such a dialog fired client_killed with the app's class on
    it, which is precisely the "I close the Obsidian/Anki popup and it
    throws me back to the previous workspace" report.

    Wrapped in try/except and defaulting to False: on a backend without
    these X11 calls the toggles simply behave as they did before.
    """
    try:
        if (win.window.get_wm_type() or "normal") != "normal":
            return True
    except Exception:
        pass
    try:
        return bool(win.window.get_wm_transient_for())
    except Exception:
        return False


def _candidates(qtile, cls: str, exact_instance: bool):
    match = _matcher(exact_instance)
    for w in qtile.windows_map.values():
        if not isinstance(w, Window) or _is_scratchpad(w):
            continue
        if match(w.get_wm_class(), cls):
            yield w


def _find_target(qtile, group_name: str, cls: str, exact_instance: bool = False):
    """The best window to land on, or None.

    Ranked rather than first-match, because windows_map is ordered by when
    each window was created -- with an ambiguous test the winner used to
    depend on the order you happened to open things in that session:

      1. a real app window sitting on the app's own group   (the normal case)
      2. a real app window that you moved somewhere else    (follow it there)
      3. a dialog, if that is genuinely all there is        (better than
         doing nothing, which is what the old code did)
    """
    fallback_elsewhere = None
    fallback_secondary = None

    for w in _candidates(qtile, cls, exact_instance):
        on_group = getattr(getattr(w, "group", None), "name", None) == group_name
        if _is_secondary(w):
            if fallback_secondary is None:
                fallback_secondary = w
            continue
        if on_group:
            return w
        if fallback_elsewhere is None:
            fallback_elsewhere = w

    return fallback_elsewhere or fallback_secondary


def _screen_index(qtile) -> int:
    try:
        return qtile.screens.index(qtile.current_screen)
    except (ValueError, AttributeError):
        return 0


def _remember(qtile, current_group: str, dest_group: str) -> None:
    """Record where to come back to -- never the group we are landing on.

    The old code did a bare `last_group[0] = current_group` on every path,
    including the ones where current_group WAS the target group (you were
    already on S and pressed Mod+Shift+O with Obsidian not yet running).
    That parked the slot on the app's own group, and every later "go back"
    -- from any of the seven toggles, they all share this one slot --
    became a toscreen() onto the group you were already standing on, i.e. a
    silent no-op. That is the "the key just does nothing sometimes" report.
    """
    if dest_group != current_group:
        last_group[_screen_index(qtile)] = current_group


def _go_back(qtile, current_group: str) -> None:
    """Return to the remembered group, and leave this one remembered.

    Swapping rather than just reading is what makes the pair behave like a
    real alt-tab: press the key a third time and you come back here. Without
    the swap, a chain (Mod+B from 1, then Mod+M from 5) left the slot
    pointing at 5 while you stood on 5, and Mod+B became a dead key.
    """
    idx = _screen_index(qtile)
    dest = last_group.get(idx)
    if not dest or dest == current_group:
        return
    group = qtile.groups_map.get(dest)
    if group is None:
        # A group can disappear across a config reload; groups_map[dest]
        # would raise straight out of the keybinding and only show up in
        # the log.
        last_group.pop(idx, None)
        return
    last_group[idx] = current_group
    _show_group(qtile, group)


def _show_group(qtile, group) -> None:
    """Make `group` the one you are looking at, without stealing it.

    Group.toscreen() with no argument means "pull this group onto the
    CURRENT screen" (libqtile/group.py), so on a two-monitor setup pressing
    Mod+B while Brave's group is already up on the external screen used to
    yank that group over to the laptop and push the laptop's group out to
    the external -- both monitors change contents, and the window you asked
    for arrives on the wrong one.

    If some screen is already showing the group, move focus to that screen
    instead. Nothing is rearranged and the app is where it already was.
    warp=False for the same reason as everywhere else here: cursor_warp is
    False in config.py.
    """
    for i, screen in enumerate(qtile.screens):
        if screen.group is group:
            if screen is not qtile.current_screen:
                qtile.focus_screen(i, warp=False)
            return
    group.toscreen()


def _focus_window_and_group(qtile, group, window) -> None:
    """Go to the group and make that window the one actually shown.

    Takes the group OBJECT, not a name, and focuses via the window's own
    group. The old version switched to a group by name and then called
    qtile.current_group.focus() -- two assumptions that do not always hold:
    with more than one screen toscreen() can put the group on the other
    screen (so current_group is not the one you asked for), and if the
    window had been dragged to a different group the focus() call quietly
    did nothing at all.
    """
    _show_group(qtile, group)
    if window is None:
        return
    home = getattr(window, "group", None)
    if home is None:
        return
    try:
        home.focus(window, warp=False)
        window.bring_to_front()
    except Exception:
        pass


def _spawn_once(qtile, key: str, cmd: str, cooldown: float = 3.0) -> None:
    """Spawn, unless we already asked for this app a moment ago.

    Between the spawn and the window being mapped there is a window of a
    second or more in which _find_target() still returns None, so a second
    keypress -- or the double-press you make when the first one seems not to
    have done anything -- launched a second copy of Anki/Obsidian/Brave.
    """
    now = time.monotonic()
    if now - _last_spawn.get(key, 0.0) < cooldown:
        return
    _last_spawn[key] = now
    qtile.spawn(cmd)


def _toggle(qtile, group_name: str, cls: str, spawn_cmd: str, exact_instance: bool = False):
    """The one body all seven toggles share.

    They were seven near-identical copies that had drifted apart (terminal
    searched only inside its own group, brave grew the instance-exact test,
    the rest kept the loose one, and half the comments still said "Anki").
    Every bug fixed in one copy had to be fixed in six others, and never was.
    """
    group = qtile.groups_map.get(group_name)
    if group is None:
        return

    current_group = qtile.current_group.name
    current_win = qtile.current_window
    match = _matcher(exact_instance)

    # Standing on the app itself -> go back where you came from.
    #
    # No longer conditional on also being in the app's configured group:
    # if you had moved the window to another group, the old code missed
    # this branch, then tried to focus that window from the configured
    # group, and did nothing.
    if (
        current_win is not None
        and not _is_scratchpad(current_win)
        and match(current_win.get_wm_class(), cls)
    ):
        _go_back(qtile, current_group)
        return

    target = _find_target(qtile, group_name, cls, exact_instance)

    # Open somewhere -> go to where it really is, not where it is filed.
    if target is not None:
        dest = getattr(target, "group", None) or group
        _remember(qtile, current_group, dest.name)
        _focus_window_and_group(qtile, dest, target)
        return

    # Not open -> land on its group and start it.
    _remember(qtile, current_group, group_name)
    _show_group(qtile, group)
    _spawn_once(qtile, cls, spawn_cmd)


# --- toggle apps ---


@lazy.function
def toggle_telegram(qtile):
    _toggle(qtile, telegram_group, telegram_name_prefix, "Telegram")


@lazy.function
def toggle_file_manager(qtile):
    _toggle(qtile, file_manager_group, file_manager_class, "pcmanfm-qt")


@lazy.function
def toggle_terminal(qtile):
    _toggle(qtile, terminal_group, terminal_class, "kitty")


@lazy.function
def toggle_qutebrowser(qtile):
    _toggle(qtile, qute_group, qute_class, "qutebrowser")


@lazy.function
def toggle_google_chrome(qtile):
    _toggle(qtile, google_chrome_group, google_chrome_class, "google-chrome-stable")


@lazy.function
def toggle_brave(qtile):
    # exact_instance: the ChatGPT/DeepSeek/WhatsApp dropdowns are Brave
    # windows whose CLASS half is also "Brave-browser". See
    # _matches_instance() -- matching loosely here is what made this
    # binding intermittent.
    _toggle(qtile, brave_group, brave_class, "brave", exact_instance=True)


@lazy.function
def toggle_anki(qtile):
    # Anki and Obsidian share group S, which is why the target has to be
    # picked by window and not just by group: being on S with Anki focused
    # and pressing Mod+Shift+O must move focus to Obsidian, not bounce you
    # off the group.
    _toggle(qtile, anki_group, anki_class, "anki")


@lazy.function
def toggle_obsidian(qtile):
    _toggle(qtile, obsidian_group, obsidian_class, "obsidian")


# --- Hooks to return to previous group ---


def _return_after_closed(window, group_name: str, cls: str, exact_instance: bool = False):
    """Go back when the LAST window of an app closes, and only then.

    The old hooks fired on any dying window whose WM_CLASS matched, from
    anywhere, with no other condition than last_group being set. Three ways
    that misfired, all of them things you would notice as the keys
    "behaving weirdly":

      * Anki's Add/Browse/Preview windows and Obsidian's modals carry the
        app's WM_CLASS. Closing one teleported you off the app you were
        still using. This is the reported symptom.
      * It fired while you were on a completely different group -- quit
        Obsidian from a menu on group 7, get yanked to wherever the slot
        happened to point.
      * The slot is shared with six other toggles, so "back" was often a
        group that had nothing to do with Obsidian, or the group you were
        already on.

    So: only a real window (not a dialog), only when it was on the app's
    group, only while you are standing on that group, and only once nothing
    of that app is left there. client_killed fires before qtile detaches the
    window (core/manager.py unmanage()), hence the explicit `w is not
    window` -- the dying window is still in group.windows at this point.
    """
    if not isinstance(window, Window) or _is_secondary(window):
        return
    match = _matcher(exact_instance)
    if not match(window.get_wm_class(), cls):
        return

    home = getattr(window, "group", None)
    if getattr(home, "name", None) != group_name:
        return

    qtile = window.qtile
    if qtile.current_group.name != group_name:
        return

    for w in home.windows:
        if w is not window and not _is_secondary(w) and match(w.get_wm_class(), cls):
            return

    _go_back(qtile, group_name)


@hook.subscribe.client_killed
def auto_return_after_anki_killed(window):
    _return_after_closed(window, anki_group, anki_class)


@hook.subscribe.client_killed
def auto_return_after_obsidian_killed(window):
    _return_after_closed(window, obsidian_group, obsidian_class)


@hook.subscribe.client_killed
def _forget_spawn_on_close(window):
    """Let a re-open right after a close through the _spawn_once() cooldown."""
    if not isinstance(window, Window):
        return
    wm_class = window.get_wm_class() or []
    for cls in list(_last_spawn):
        if _matches_class(wm_class, cls):
            _last_spawn.pop(cls, None)
