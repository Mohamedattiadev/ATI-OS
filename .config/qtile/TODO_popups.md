# Deferred popup integrations

Preserved from `config.py` cleanup. Re-enable by moving each block into
`lib/hooks.py` (for hook stubs) or the relevant importing module (for
`from popups.* import ...`). Also drop the matching `NOTE: will be used
later` comments in `lib/constants.py` (CHORD_CHIP_COLORS) and inside the
widget bar builders when re-wiring.

## Bluetooth popup

```python
from popups.BluetoothPopup import (
    show as show_bluetooth_popup,
    close as close_bluetooth_popup,
    move as bluetooth_move,
    toggle_device as bluetooth_toggle,
    request_disconnect,
    confirm_disconnect,
    reload_devices,
)

@hook.subscribe.enter_chord
def auto_enable_bluetooth_popup(chord_name):
    if chord_name == "Bluetooth-Mode":
        show_bluetooth_popup(qtile)
```

## Audio popup

```python
from popups.AudioPopup import (
    show as show_audio_popup,
    close as close_audio_popup,
    move as audio_move,
    left as audio_left,
    right as audio_right,
    select as audio_select,
    refresh as audio_refresh,
)

@hook.subscribe.enter_chord
def auto_enable_audio_popup(chord_name):
    if chord_name == "Audio-Mode":
        show_audio_popup(qtile)
```

## WiFi popup

```python
from popups.WifiPopup import (
    show as show_wifi_popup,
    close as close_wifi_popup,
    move_vertical as wifi_move,
    move_horizontal as wifi_move_col,
    select as wifi_select,
    manual_refresh as wifi_manual_refresh,
)

@hook.subscribe.enter_chord
def auto_enable_wifi_popup(chord_name):
    if chord_name == "Wifi-Mode":
        show_wifi_popup(qtile)
```

## Updates popup

```python
from popups.UpdatesPopup import (
    show as updates_popup,
    move as updates_move,
    toggle_select as updates_toggle,
    request_update,
    ignore_selected,
    confirm,
    rofi_search,
    close as close_updates_popup,
)

@hook.subscribe.enter_chord
def auto_enable_updates_popup(chord_name):
    if chord_name == "Updates-Mode":
        updates_popup(qtile)
```

## Related re-wire points

- `lib/constants.py` — uncomment `CHORD_CHIP_COLORS` entries for `Bluetooth-Mode` / `Audio-Mode` / `Wifi-Mode` / `Updates-Mode`.
- widget bar builders (currently inline in `config.py`) — chord label strings for BLUETOOTH / AUDIO / WIFI / UPDATES modes are already commented near the `chord_chip` Chord widget block.
- `lib/hooks.py` — extend `cleanup_on_leave` to call the popup close funcs when leaving each mode (stubs already commented in place).
