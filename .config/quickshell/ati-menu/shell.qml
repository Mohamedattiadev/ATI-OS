// ati-menu — Omarchy's own Menu.qml/MenuModel.js (vendored, see ../../../
// NOTICE.md), running as its own resident Quickshell instance rather than
// nested inside topbar/tide-island-fork. Same reasoning topbar.sh gives for
// why the topbar is its own config and not part of the island's tree:
// Quickshell keys its IPC socket and instance by CONFIG PATH, so a crash or
// a `qs -p` restart of this one can never take the bar down with it, and it
// runs identically regardless of which bar (native/island) the session is
// wearing -- it isn't part of either.
//
// Resident, not launched fresh per keypress: a Quickshell start is a QML
// compile (topbar.sh's popups.qml carries the same reasoning) -- launching
// fresh every time would answer the first keystroke several hundred
// milliseconds late, every time. IPC toggle/summon/close instead, matching
// topbar's own IpcHandler convention exactly.
import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/menu" as MenuPlugin
import "plugins/clipboard" as ClipboardPlugin
import "services" as Services

ShellRoot {
  id: shellRoot

  // Vendored too (see NOTICE.md): the Apps section of Omarchy's own menu
  // merges installed desktop entries in via `root.shell.appLibrary`
  // (Menu.qml, null-safe when absent -- see the commit that first vendored
  // Menu.qml without this). Real app-launch, in the same searchable tree
  // as every other entry, was the single biggest visible gap against the
  // real thing.
  property Services.AppLibrary appLibrary: Services.AppLibrary { }

  MenuPlugin.Menu {
    id: menu
    shell: shellRoot
  }

  // Second resident view, same process -- a split-pane clipboard picker
  // (real image thumbnails + copy timestamp on the right) that the generic
  // dmenu payload above has no way to render (its rows are single-line
  // glyph+label+subtext, no image/split-pane concept at all). Its own
  // IpcHandler target ("clip") rather than overloading "menu", for the
  // same reason bar/tide/menu are already three separate targets in
  // ati-bar-action: two genuinely different surfaces, not two renderings
  // of the same one.
  ClipboardPlugin.Clipboard {
    id: clip
  }

  // Menu.qml's openDmenu() (vendored, see NOTICE.md) has been fully wired
  // and working since the day Menu.qml was vendored -- what was missing was
  // any way to REACH it. summon() below only ever builds {initialMenu:
  // route}, never a {mode:"select"/"input", ...} payload. This FileView is
  // that missing path: dmenu() below points it at a payload file a caller
  // script wrote, and onLoaded hands the raw JSON straight to menu.open(),
  // which already branches into openDmenu() itself once mode is present.
  //
  // A file path, not inline JSON, crosses the IPC boundary: Quickshell IPC
  // args are whitespace-split, and a select payload's `options` array (each
  // element itself containing literal tabs, see Menu.qml's row-splitting at
  // MenuModel row parsing) would not survive that split reliably as a
  // single argument the way a short route string does.
  FileView {
    id: dmenuPayloadFile
    printErrors: false
    onLoaded: menu.open(text())
  }

  IpcHandler {
    target: "menu"

    function toggle(): void {
      if (menu.opened) menu.close(); else menu.open("{}");
    }

    function summon(route: string): void {
      menu.open(JSON.stringify({initialMenu: route || "root"}));
    }

    function dmenu(payloadPath: string): void {
      dmenuPayloadFile.path = payloadPath;
      dmenuPayloadFile.reload();
    }

    function close(): void {
      menu.close();
    }

    function status(): string {
      return menu.opened ? "open" : "closed";
    }
  }

  IpcHandler {
    target: "clip"

    function toggle(): void {
      clip.toggle();
    }

    function open(): void {
      clip.open();
    }

    function close(): void {
      clip.close();
    }

    function status(): string {
      return clip.status();
    }
  }
}
