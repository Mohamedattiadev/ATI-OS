# SPDX-FileCopyrightText: 2025 Rehpotsirhc
#
# SPDX-License-Identifier: MIT

def setup(c, options={}):
    palette = {
        "background": "#282c34",  # gray
        "foreground": "#dfdfdf",  # white
        "black": "#181920",
        "dark-gray": "#21242b",
        "gray": "#282c34",
        "cool-gray": "#3b404d",
        "medium-gray": "#3f444a",
        "light-gray": "#5b6268",
        "lighter-gray": "#73797e",
        "pale-gray": "#9ca0a4",
        "white": "#dfdfdf",
        "bright-white": "#fefefe",
        "pure-white": "#ffffff",
        "darker-purple": "#5b3766",
        "dark-purple": "#615c80",
        "purple": "#a9a1e1",
        "dark-pink": "#945aa6",
        "pink": "#c678dd",
        "dark-blue": "#2257a0",
        "blue": "#51afef",
        "light-blue": "#7bb6e2",
        "cyan": "#46d9ff",
        "dark-green": "#668044",
        "green": "#98be65",
        "teal": "#4db5bd",
        "red": "#ff6c6b",
        "orange": "#da8548",
        "yellow": "#ecbe7b",
    }

    spacing = options.get("spacing", {"vertical": 5, "horizontal": 5})

    padding = options.get(
        "padding",
        {
            "top": spacing["vertical"],
            "right": spacing["horizontal"],
            "bottom": spacing["vertical"],
            "left": spacing["horizontal"],
        },
    )

    # Background color of the completion widget category headers.
    c.colors.completion.category.bg = palette["cool-gray"]

    # Bottom border color of the completion widget category headers.
    c.colors.completion.category.border.bottom = palette["dark-gray"]

    # Top border color of the completion widget category headers.
    c.colors.completion.category.border.top = palette["dark-gray"]

    # Foreground color of completion widget category headers.
    c.colors.completion.category.fg = palette["blue"]

    # Background color of the completion widget for even rows.
    c.colors.completion.even.bg = palette["background"]

    # Background color of the completion widget for odd rows.
    c.colors.completion.odd.bg = palette["dark-gray"]

    # Text color of the completion widget.
    c.colors.completion.fg = palette["foreground"]

    # Background color of the selected completion item.
    c.colors.completion.item.selected.bg = palette["medium-gray"]

    # Bottom border color of the selected completion item.
    c.colors.completion.item.selected.border.bottom = palette["medium-gray"]

    # Top border color of the completion widget category headers.
    c.colors.completion.item.selected.border.top = palette["medium-gray"]

    # Foreground color of the selected completion item.
    c.colors.completion.item.selected.fg = palette["foreground"]

    # Foreground color of the matched text in the completion.
    c.colors.completion.match.fg = palette["pink"]

    # Foreground color of the selected matched text in the completion.
    c.colors.completion.item.selected.match.fg = palette["light-blue"]

    # Color of the scrollbar in completion view
    c.colors.completion.scrollbar.bg = palette["medium-gray"]

    # Color of the scrollbar handle in completion view.
    c.colors.completion.scrollbar.fg = palette["light-gray"]

    # Background color for the download bar.
    c.colors.downloads.bar.bg = palette["dark-gray"]

    # Background color for downloads with errors.
    c.colors.downloads.error.bg = palette["red"]

    # Foreground color for downloads with errors.
    c.colors.downloads.error.fg = palette["pure-white"]

    # Color gradient start for download grays.
    c.colors.downloads.start.bg = palette["blue"]

    # Color gradient stop for download grays.
    c.colors.downloads.stop.bg = palette["dark-green"]

    # Color gradient start for download foregrounds.
    c.colors.downloads.start.fg = palette["pure-white"]

    # Color gradient stop for download foregrounds.
    c.colors.downloads.stop.fg = palette["pure-white"]

    # Color gradient interpolation system for download backgrounds.
    # Valid values:
    #   - rgb: Interpolate in the RGB color system.
    #   - hsv: Interpolate in the HSV color system.
    #   - hsl: Interpolate in the HSL color system.
    #   - none: Don't show a gradient.
    c.colors.downloads.system.bg = "rgb"

    # Color gradient interpolation system for download foregrounds.
    c.colors.downloads.system.fg = "rgb"

    # Background color for hints. Note that you can use a `rgba(...)` value
    # for transparency.
    # c.colors.hints.bg = palette["yellow"]
    #
    # # Font color for hints.
    # c.colors.hints.fg = palette["gray"]
    #
    # c.hints.border = "1px solid " + palette["dark-gray"]
    #
    # # Font color for the matched part of hints.
    # c.colors.hints.match.fg = palette["dark-green"]

# Hint background – strong violet-blue, balanced saturation
#     c.colors.hints.bg = "#4c4f9d"
#
# # Hint text – clean white, great contrast
#     c.colors.hints.fg = "#ffffff"
#
# # Matched characters – soft amber/gold for a friendly contrast
#     c.colors.hints.match.fg = "#ffcc66"
#
# # Hint border – vivid turquoise for distinct edge visibility
#     c.hints.border = "2px solid #40c4ff"
#
    # c.fonts.hints = "bold 10pt FiraCode Nerd Font"
# Use a rounded, mono font and increase padding
    c.fonts.hints = "bold 11pt 'Fira Mono'"


    # Optional: Transparent-ish background if supported
    # c.colors.hints.bg = "rgba(198,120,221,0.9)"
    # Background color of the keyhint widget.
    c.colors.keyhint.bg = palette["dark-gray"]

    # Text color for the keyhint widget.
    c.colors.keyhint.fg = palette["blue"]

    # Highlight color for keys to complete the current keychain.
    c.colors.keyhint.suffix.fg = palette["green"]

    # Background color of an error message.
    c.colors.messages.error.bg = palette["dark-gray"]

    # Border color of an error message.
    c.colors.messages.error.border = palette["light-gray"]

    # Foreground color of an error message.
    c.colors.messages.error.fg = palette["red"]

    # Background color of an info message.
    c.colors.messages.info.bg = palette["background"]

    # Border color of an info message.
    c.colors.messages.info.border = palette["light-gray"]

    # Foreground color an info message.
    c.colors.messages.info.fg = palette["foreground"]

    # Background color of a warning message.
    c.colors.messages.warning.bg = palette["background"]

    # Border color of a warning message.
    c.colors.messages.warning.border = palette["light-gray"]

    # Foreground color a warning message.
    c.colors.messages.warning.fg = palette["red"]

    # Background color for prompts.
    c.colors.prompts.bg = palette["background"]

    # Border used around UI elements in prompts.
    c.colors.prompts.border = "1px solid " + palette["light-gray"]

    # Foreground color for prompts.
    c.colors.prompts.fg = palette["foreground"]

    # Background color for the selected item in filename prompts.
    c.colors.prompts.selected.bg = palette["light-gray"]

    # Background color of the statusbar in caret mode.
    c.colors.statusbar.caret.bg = palette["dark-purple"]

    # Foreground color of the statusbar in caret mode.
    c.colors.statusbar.caret.fg = palette["foreground"]

    # Background color of the statusbar in caret mode with a selection.
    c.colors.statusbar.caret.selection.bg = palette["dark-pink"]

    # Foreground color of the statusbar in caret mode with a selection.
    c.colors.statusbar.caret.selection.fg = palette["foreground"]

    # Background color of the statusbar in command mode.
    c.colors.statusbar.command.bg = palette["background"]

    # Foreground color of the statusbar in command mode.
    c.colors.statusbar.command.fg = palette["foreground"]

    # Background color of the statusbar in private browsing + command mode.
    c.colors.statusbar.command.private.bg = palette["background"]

    # Foreground color of the statusbar in private browsing + command mode.
    c.colors.statusbar.command.private.fg = palette["foreground"]

    # Background color of the statusbar in insert mode.
    c.colors.statusbar.insert.bg = palette["dark-blue"]

    # Foreground color of the statusbar in insert mode.
    c.colors.statusbar.insert.fg = palette["foreground"]

    # Background color of the statusbar.
    c.colors.statusbar.normal.bg = palette["background"]

    # Foreground color of the statusbar.
    c.colors.statusbar.normal.fg = palette["foreground"]

    # Background color of the statusbar in passthrough mode.
    c.colors.statusbar.passthrough.bg = palette["darker-purple"]

    # Foreground color of the statusbar in passthrough mode.
    c.colors.statusbar.passthrough.fg = palette["foreground"]

    # Background color of the statusbar in private browsing mode.
    c.colors.statusbar.private.bg = palette["light-gray"]

    # Foreground color of the statusbar in private browsing mode.
    c.colors.statusbar.private.fg = palette["foreground"]

    # Background color of the progress bar.
    c.colors.statusbar.progress.bg = palette["background"]

    # Foreground color of the URL in the statusbar on error.
    c.colors.statusbar.url.error.fg = palette["red"]

    # Default foreground color of the URL in the statusbar.
    c.colors.statusbar.url.fg = palette["foreground"]

    # Foreground color of the URL in the statusbar for hovered links.
    c.colors.statusbar.url.hover.fg = palette["cyan"]

    # Foreground color of the URL in the statusbar on successful load
    c.colors.statusbar.url.success.http.fg = palette["green"]
    c.colors.statusbar.url.success.https.fg = palette["green"]

    # Foreground color of the URL in the statusbar when there's a warning.
    c.colors.statusbar.url.warn.fg = palette["yellow"]

    # Status bar padding
    c.statusbar.padding = padding

    # Background color of the tab bar.
    c.colors.tabs.bar.bg = palette["light-gray"]

    # Background color of unselected even tabs.
    c.colors.tabs.even.bg = palette["pale-gray"]

    # Foreground color of unselected even tabs.
    c.colors.tabs.even.fg = palette["bright-white"]

    # Color for the tab indicator on errors.
    c.colors.tabs.indicator.error = palette["red"]

    # Color gradient start for the tab indicator.
    c.colors.tabs.indicator.start = palette["blue"]

    # Color gradient end for the tab indicator.
    c.colors.tabs.indicator.stop = palette["green"]

    # Color gradient interpolation system for the tab indicator.
    # Valid values:
    #   - rgb: Interpolate in the RGB color system.
    #   - hsv: Interpolate in the HSV color system.
    #   - hsl: Interpolate in the HSL color system.
    #   - none: Don't show a gradient.
    c.colors.tabs.indicator.system = "rgb"

    # Background color of unselected odd tabs.
    c.colors.tabs.odd.bg = palette["lighter-gray"]

    # Foreground color of unselected odd tabs.
    c.colors.tabs.odd.fg = palette["bright-white"]

    # Background color of pinned unselected even tabs.
    c.colors.tabs.pinned.even.bg = palette["pale-gray"]

    # Foreground color of pinned unselected even tabs.
    c.colors.tabs.pinned.even.fg = palette["bright-white"]

    # Background color of pinned unselected odd tabs.
    c.colors.tabs.pinned.odd.bg = palette["lighter-gray"]

    # Foreground color of pinned unselected odd tabs.
    c.colors.tabs.pinned.odd.fg = palette["bright-white"]

    # Background color of pinned selected even tabs.
    c.colors.tabs.pinned.selected.even.bg = palette["background"]

    # Foreground color of pinned selected even tabs.
    c.colors.tabs.pinned.selected.even.fg = palette["bright-white"]

    # Background color of pinned selected odd tabs.
    c.colors.tabs.pinned.selected.odd.bg = palette["background"]

    # Foreground color of pinned selected odd tabs.
    c.colors.tabs.pinned.selected.odd.fg = palette["bright-white"]

    # Background color of selected even tabs.
    c.colors.tabs.selected.even.bg = palette["background"]

    # Foreground color of selected even tabs.
    c.colors.tabs.selected.even.fg = palette["bright-white"]

    # Background color of selected odd tabs.
    c.colors.tabs.selected.odd.bg = palette["background"]

    # Foreground color of selected odd tabs.
    c.colors.tabs.selected.odd.fg = palette["bright-white"]

    # Tab padding
    c.tabs.padding = padding
    c.tabs.indicator.width = 3
    c.tabs.favicons.scale = 1
