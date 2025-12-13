# CRITICAL: Load the autoconfig first.
config.load_autoconfig()



# Import the theme module (doom_one.py should be in ~/.config/qutebrowser/)
import doom_one

# -----------------------------------------------------------------------------
# Theme & UI
# -----------------------------------------------------------------------------
config.set("colors.webpage.darkmode.enabled", True)
doom_one.setup(c, {
    "spacing": {
        "vertical": 5,
        "horizontal": 5
    }
})

dark_mode = True  # Manually switch this or automate later




if dark_mode:
    # DARK MODE — dark background, bright text, stylish accent
    c.colors.hints.bg = "#1e1e2e"                    # Deep indigo-gray
    c.colors.hints.fg = "#ffffff"                 # Pure white hint text
    c.colors.hints.match.fg = "#f38ba8"             # Soft red-pink for matched chars
    c.hints.border = "2.5px solid #89b4fa"          # Soft blue border for visibility

else:
    # LIGHT MODE — bright background, dark text, elegant accents
    c.colors.hints.bg = "#f4f4f5"                    # Gentle off-white background
    c.colors.hints.fg = "#000000"                 # Pure black text for clarity
    c.colors.hints.match.fg = "#b91c1c"             # Deep crimson for match
    c.hints.border = "2.5px solid #6366f1"          # Indigo border for structure



c.hints.chars="asdghjkl"

c.fonts.default_family = "JetBrains Mono"
c.fonts.default_size = "9pt"
c.fonts.prompts = 'default_size sans-serif'
c.fonts.statusbar = '11pt "Source Code Pro"'

c.content.blocking.method = 'auto'
c.keyhint.blacklist = ['*']
c.messages.timeout = 0
c.scrolling.smooth = True


# -----------------------------------------------------------------------------
# Startup Pages
# -----------------------------------------------------------------------------
c.url.default_page = 'file:///home/ati/.config/qutebrowser/html/homepage.html'
c.url.start_pages = ['file:///home/ati/.config/qutebrowser/html/homepage.html']

# -----------------------------------------------------------------------------
# Editor & Clipboard
# -----------------------------------------------------------------------------
# c.editor.command = ["alacritty", "-e", "nvim", "{}"]
#
# c.editor.command = [
#     "alacritty", "-e", "nvim",
#     "+call cursor({line}, {column})", "{file}"
# ]

c.editor.command = [
    "alacritty", "--title", "edit-field",
    "-e", "nvim",
    "+call cursor({line}, {column})", "{file}"
]

c.content.javascript.clipboard = 'access'

# -----------------------------------------------------------------------------
# Tabs & Statusbar
# -----------------------------------------------------------------------------
c.tabs.show = 'always'

# -----------------------------------------------------------------------------
# Downloads
# -----------------------------------------------------------------------------
c.downloads.location.directory = '~/Downloads'


# -----------------------------------------------------------------------------
# Keybindings - Vim Style
# -----------------------------------------------------------------------------
# unbind
config.unbind('d', mode='normal')
config.unbind('D', mode='normal')
config.unbind('U', mode='normal')
config.unbind('u', mode='normal')
config.unbind('<Ctrl-a>', mode='normal')
config.unbind('<Ctrl-t>', mode='normal')
config.unbind('<Ctrl-q>', mode='normal')
# -----
config.unbind('m', mode='normal')
config.unbind('H', mode='normal')
config.unbind('L', mode='normal')
config.unbind('J', mode='normal')
config.unbind('K', mode='normal')
config.unbind('<Space>', mode='caret')
config.unbind('<Ctrl-v>',mode='normal')
config.unbind('Sq')
config.unbind('B', mode='normal')
config.unbind('b', mode='normal')
config.unbind('Sb')
config.unbind('gD')
config.unbind('Ss')
config.unbind('<Alt+m>')
config.unbind('q')# macro-record
config.unbind('@')# macro-run
config.unbind('<Shift+Tab>',mode='command')
config.unbind('<Ctrl+Tab>',mode='command')
config.unbind('<Ctrl+Shift+Tab>',mode='command')
config.unbind('<Ctrl+d>',mode='command')
config.unbind('<Shift+Del>',mode='command')
config.unbind('<Ctrl+c>',mode='command')
config.unbind('<Ctrl+Shift+c>',mode='command')
config.unbind('<Ctrl+Return>',mode='command')
config.unbind('<Ctrl+Return>',mode='command')
config.unbind('<Ctrl+b>')
config.unbind('<Ctrl+a>',mode='command')
config.unbind('<Ctrl+e>',mode='command')
config.unbind('<Alt+d>',mode='command')


# Navigation
config.bind('H', 'tab-prev')
config.bind('L', 'tab-next')
config.bind('<Ctrl-h>', 'back')
config.bind('<Ctrl-l>', 'forward')

# Prompt navigation
config.bind('<Ctrl-j>', 'completion-item-focus --next', mode='prompt')
config.bind('<Ctrl-k>', 'completion-item-focus --prev', mode='prompt')

# Hints
config.bind('T', 'cmd-set-text -s :tab-select')
config.bind('Y', 'hint links yank')
config.bind('M', 'hint links spawn mpv {hint-url}')

config.bind('V', 'hint links spawn --userscript ~/.config/qutebrowser/scripts/download_video {hint-url}', mode='normal')
config.bind('I', 'hint images spawn --userscript ~/.config/qutebrowser/scripts/download-indexed-image {hint-url}')
config.bind('yI', 'hint images yank')  # lowercase y, uppercase I
# Passthrough
config.bind('<Ctrl-p>', 'mode-enter passthrough ;; message-info "Passthrough mode ON"')
config.bind('<Escape>', 'mode-leave ;; message-info "Passthrough mode OFF"', mode='passthrough')
config.bind('<Escape>', 'clear-messages', mode='normal')

# Custom Commands
config.bind('<space>t', 'open -t', mode='normal')
# config.bind('<space>w', 'tab-close')
# config.bind('<space>o', 'tab-only')
config.bind('<space>f', 'cmd-set-text :')
config.bind('<space>mgh', 'open https://github.com/MohamedattiaDev')
config.bind('<space>ati', 'open https://mohamedattiaDev.github.io/AtiDocs')
config.bind('<space>ls', 'session-load default')
config.bind('<space>ss', 'session-save default')
config.bind('<space>wq', 'quit --save')
# config.bind('<space>w', 'session-save default')
config.bind('<space>V', 'view-source')
config.bind(',d', 'config-cycle colors.webpage.darkmode.enabled')
config.bind('<space><space>', 'cmd-set-text -s :open -t')
config.bind('xb', 'config-cycle statusbar.show always never')
config.bind('xt', 'config-cycle tabs.show always never')
config.bind('xx', 'config-cycle statusbar.show always never;; config-cycle tabs.show always never')
# config.bind('y', 'yank', mode='normal')
# config.bind('y', 'yank selection', mode='caret')
config.bind('<space>iw', 'devtools window')
config.bind('<space>I', 'devtools ')
# config.bind('V', 'mode-enter caret ;; fake-key V')
config.bind('Sh', 'open -t  qute://history')
config.bind('Sm', 'open -t qute://bookmarks')
config.bind('Uc', 'spawn ~/.config/qutebrowser/scripts/reload_and_notify')
config.bind('<space>t', 'yank selection --sel primary ;; cmd-later 100 open --tab {primary}', mode='caret')
config.bind('s', 'cmd-set-text /', mode='caret')
config.bind('<space>f', 'cmd-set-text :')
config.bind('gS', 'tab-give') # go in seperate tab
config.bind('<Ctrl-j>', 'completion-item-focus next',mode="command") 
config.bind('<Ctrl-k>', 'completion-item-focus prev',mode="command") 
config.bind('<Ctrl-n>', 'completion-item-focus next-category',mode="command")
config.bind('<Ctrl-p>', 'completion-item-focus prev-category',mode="command") 
config.bind('<Ctrl+Shift+d>', 'completion-item-del',mode="command") 
config.bind('<Ctrl-y>', 'completion-item-yank',mode="command")
config.bind('<Ctrl-h>', 'rl-backward-char',mode="command") 
config.bind('<Ctrl-l>', 'rl-forward-char',mode="command") 
config.bind('<Ctrl-w>', 'rl-forward-word',mode="command") 
config.bind('<Ctrl-b>', 'rl-backward-word',mode="command") 

config.bind('N', 'hint inputs', mode='normal')
config.bind('N', 'edit-text', mode='insert')

config.bind('qR', 'hint links spawn --userscript qr',mode="normal")
config.bind('Sd', 'spawn --userscript ~/.config/qutebrowser/scripts/open_download',mode="normal")
config.bind('E', 'edit-url', mode='normal')
# Bind 'Z' in normal mode to open a Zen-style floating preview
config.bind(
    'P',
    'hint --rapid links window',
    mode='normal'
) # preview links


config.bind(
    'K',
    'spawn --userscript ~/.config/qutebrowser/scripts/show_keymaps',
    mode='normal',
)

# -----------------------------------------------------------------------------
# Search Engines
# -----------------------------------------------------------------------------
c.url.searchengines = {
    'DEFAULT': 'https://duckduckgo.com/?q={}',
    'g': 'https://www.google.com/search?q={}',
    'ddg': 'https://duckduckgo.com/?q={}',
    'br': 'https://search.brave.com/search?q={}',
    'b': 'https://www.bing.com/search?q={}',
    'gh': 'https://github.com/search?q={}',
    'gl': 'https://gitlab.com/search?q={}',
    'so': 'https://stackoverflow.com/search?q={}',
    'npm': 'https://www.npmjs.com/search?q={}',
    'py': 'https://pypi.org/search/?q={}',
    'aur': 'https://aur.archlinux.org/packages/?K={}',
    'aw': 'https://wiki.archlinux.org/index.php?search={}',
    'yt': 'https://www.youtube.com/results?search_query={}',
    'wiki': 'https://en.wikipedia.org/w/index.php?search={}',
    'mdn': 'https://developer.mozilla.org/en-US/search?q={}',
    'dev': 'https://devdocs.io/#q={}',
    'chatgpt': 'https://chat.openai.com/?q={}',
    'gemini': 'https://gemini.google.com/?q={}',
    'r': 'https://www.reddit.com/r/all/search?q={}',
    'hn': 'https://hn.algolia.com/?q={}',
    # Localhost shortcuts
    'local': 'http://localhost:{}',
    'locals': 'https://localhost:{}',
}

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------
c.aliases.update({
    'dev': 'spawn --userscript ~/.config/qutebrowser/scripts/open-work-tabs',
    'yt': 'open https://www.youtube.com',
    # 'gh': 'open https://github.com',
    'mgh': 'open https://github.com/MohamedattiaDev',
    'ati': 'open https://mohamedattiaDev.github.io/AtiDocs',
    'fa3': 'open https://Fa3elKheer.github.io/Fa3elKheer',
    'g': 'open https://google.com',
    'gl': 'open https://gitlab.com',
    'mail': 'open https://mail.google.com',
    'chat': 'open https://chat.google.com',
    'devdocs': 'open https://devdocs.io'
})













# -----------------------------------------------------------------------------
# Per-domain Settings (Final Corrected Version)
# -----------------------------------------------------------------------------
#
# # ===== Core Privacy/Content Settings =====
# config.set('content.blocking.method', 'auto')  # Works without additional dependencies
# config.set('content.site_specific_quirks.enabled', False)
#
# # ===== Cookie Management =====
# config.set('content.cookies.accept', 'all', 'https://www.youtube.com')
# # config.set('content.cookies.accept', 'no-3rdparty', '*')
#
# # ===== JavaScript Settings =====
# config.set('content.javascript.enabled', True)
# config.set('content.javascript.clipboard', 'access')  # Corrected valid value
#
# # ===== YouTube-Specific Workarounds =====
# c.content.blocking.whitelist = [
#     '*://*.doubleclick.net/*',
#     '*://*.youtube.com/*'
# ]
#
# # Correct JavaScript log settings (proper dictionary format)
# config.set('content.javascript.log', {
#     'unknown': 'none',
#     'info': 'none',
#     'warning': 'none',
#     'error': 'none'  # Show only errors as warnings
# })
#
# # ===== Ad-Blocking =====
# config.set('content.blocking.adblock.lists', [
#     'https://easylist.to/easylist/easylist.txt',
#     'https://easylist.to/easylist/easyprivacy.txt',
#     'https://secure.fanboy.co.nz/fanboy-annoyance.txt',
#     'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt',
#     'https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt',
#     'https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11.txt',
#     'https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_2.txt'
# ])
#
#
# # Fix Google login
# config.set(
#     "content.headers.user_agent",
#     "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
#     "(KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36",
#     "https://accounts.google.com/*"
# )
# config.set("content.cookies.accept", "all", "https://accounts.google.com")
# config.set("content.cookies.accept", "all", "https://*.google.com")
# # ===== Caret Mode Fix =====
# config.set('content.javascript.enabled', True, 'chrome-devtools://*')
# config.set('content.javascript.enabled', True, 'devtools://*')
#
# print("--- Error-Free Config Loaded ---")
