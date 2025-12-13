### How to change the notification level and show it in dunst

1- sudoedit /usr/lib/python3.13/site-packages/qutebrowser/utils/message.py
2- import subprocess # make sure this is at the top of the file
3- replace the show func with this:

```python

import subprocess
from qutebrowser.utils import usertypes  # Only needed if using usertypes.MessageLevel




def show(
    self,
    level: usertypes.MessageLevel,
    text: str,
    replace: str = None,
    rich: bool = False,
) -> None:
    """Send qutebrowser messages via desktop notifications only."""

    lower_text = text.lower()

    # 1. Skip clipboard-related messages
    if "yanked" in lower_text or "clipboard" in lower_text:
        return

    # 2. Default to level-based urgency and summary
    urgency_map = {
        usertypes.MessageLevel.error: ("critical", "message-error"),
        usertypes.MessageLevel.warning: ("normal", "message-warning"),
        usertypes.MessageLevel.info: ("low", "message-info"),
    }
    urgency, summary = urgency_map.get(level, ("low", "qutebrowser"))

    # 3. Override based on message content (priority over level)
    if "message-error" in lower_text:
        urgency, summary = "critical", "message-error"
    elif "message-warning" in lower_text:
        urgency, summary = "normal", "message-warning"
    elif "message-info" in lower_text:
        urgency, summary = "low", "message-info"

    # 4. Send notification (let Dunst styling handle the colors)
    try:
        subprocess.Popen([
            "notify-send",
            f"--urgency={urgency}",
            summary,  # This is the 'summary' field in Dunst
            text      # This is the body
        ])
    except Exception as e:
        print(f"Failed to send notification: {e}")
        import traceback
        traceback.print_exc()
```
