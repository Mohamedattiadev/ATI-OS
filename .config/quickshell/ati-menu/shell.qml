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

  IpcHandler {
    target: "menu"

    function toggle(): void {
      if (menu.opened) menu.close(); else menu.open("{}");
    }

    function summon(route: string): void {
      menu.open(JSON.stringify({initialMenu: route || "root"}));
    }

    function close(): void {
      menu.close();
    }

    function status(): string {
      return menu.opened ? "open" : "closed";
    }
  }
}
