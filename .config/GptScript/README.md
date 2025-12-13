# GPTScript: Clipboard-Triggered AI Assistant

**GPTScript** is a lightweight clipboard assistant for Linux (X11), triggered by commands like `/gpt`, `/mail`, and `/sum` copied to your clipboard. It uses Google's Gemini API to generate intelligent responses, summaries, or formatted emails — then types the response directly into your active window.

---

## ✨ Features

- 💬 `/gpt your prompt` — General question answering with memory
- 📧 `/mail message` — Drafts a formal email based on your prompt
- 📄 `/sum text` — Summarizes long text in your clipboard
- 🧠 Context-aware memory (saved in `/tmp/gpt_context_history.txt`)
- 📋 Auto reads clipboard (via `xclip`) and types output (via `xdotool`)

---

## ⚙️ Requirements

- Linux with **X11**
- `xclip`, `xdotool`
- Python 3.7+
- [Google Gemini API Key](https://makersuite.google.com/app/apikey)

---

## 🚀 Installation

Clone the repo:

```bash
git clone https://github.com/yourusername/gptscript.git
cd gptscript
```

Create and activate a virtual environment:

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Make the script executable:

```bash
chmod +x gpt_inline_auto.py
```

Run the script:

```bash
./gpt_inline_auto.py
```

---

## 🔐 Environment Setup

### 1. Gemini API Key (Required)

You must add your **GEMINI_API_KEY** either to:

#### Option A: `~/.config/GptScript/user.env`

Copy the example file:

```bash
mkdir -p ~/.config/GptScript
cp user.env.example ~/.config/GptScript/user.env
```

Then edit it:

```env
GEMINI_API_KEY=your_google_api_key_here
NAME=Your Name
STUDENT_ID=YourID
EMAIL=you@example.com
```

#### Option B: System-wide `/etc/environment`

```bash
sudo bash -c 'echo "GEMINI_API_KEY=your_google_api_key_here" >> /etc/environment'
```

Then reboot or run:

```bash
source /etc/environment
```

---

## 🧪 Usage

1. Copy a line like this:

```text
/gpt What's the difference between TCP and UDP?
```

2. The assistant will read the clipboard, generate a response, and type it into your active window.

3. Try:

```text
/mail I need to reschedule my project presentation.
```

Or:

```text
/sum Here's a long article to summarize...
```

---

## 🧠 Context Reset

To clear the memory (conversation context), copy:

```text
/reset
```

---

## 📁 File Structure

```
gptscript/
├── gpt_inline_auto.py       # Main script
├── templates.py             # Email and persona templates
├── user.env.example         # Environment variable template
├── requirements.txt         # Python dependencies
```

---

## 🧷 Keyboard Shortcut Integration

Since I use **Qtile**, I’ve set it up so that pressing `Alt + g` runs the script and starts GPTScript instantly.

If you use Qtile too, you can add this to your `~/.config/qtile/config.py`:

```python
from libqtile.lazy import lazy
from libqtile.config import Key

mod = "mod1"  # "mod1" = Alt, "mod4" = Super/Windows key

keys.append(
    Key([mod], "g", lazy.spawn("python ~/Projects/gptscript/gpt_inline_auto.py"))
)
```

📌 Make sure the path to `gpt_inline_auto.py` is correct for your system.

> You can reload Qtile with your configured shortcut (usually `Mod + Ctrl + r`) to apply the change.


### 🪟 Other Window Managers

For users on other platforms:

- **i3wm**: Add this to `~/.config/i3/config`:

```i3
bindsym $mod+g exec python ~/Projects/gptscript/gpt_inline_auto.py
```

- **bspwm** (via `sxhkd`):

```sxhkd
alt + g
    python ~/Projects/gptscript/gpt_inline_auto.py
```
> As long as the system can run a command like:

```bash
python /path/to/gpt_inline_auto.py
```

You're good to go 🚀

---

## 🖥️ Compatibility

| Platform        | Works? | Notes                                                                 |
|----------------|--------|-----------------------------------------------------------------------|
| Linux (X11)     | ✅ Yes | Full support using `xclip` and `xdotool`                              |
| Linux (Wayland) | ⚠️ Partial | `xclip`/`xdotool` won't work — you'd need `wl-clipboard` / `wtype`    |
| macOS           | ❌ No  | Requires replacement of clipboard/input handling via `pbpaste`, `osascript`, etc. |
| Windows         | ❌ No  | Requires Python packages like `pyperclip` and `pyautogui`             |

> 🛠️ If you're using Wayland, macOS, or Windows and want to port this tool, you'll need to replace:
> - Clipboard access (`xclip`)
> - Typing/simulation (`xdotool`)
>
> Future versions may include abstraction for cross-platform support.


---

## 📄 License

MIT © [Mohamed Attia](https://github.com/MohamedattiaDev)

---

> **Note:** This tool sends requests to Google's Gemini API. Do not use it to send personal, sensitive, or confidential information unless you're fully aware of the implications.
