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
import "plugins/atiplugins" as AtiPlugins
import "plugins/menu" as MenuPlugin
import "plugins/clipboard" as ClipboardPlugin
import "plugins/translate" as TranslatePlugin
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

  // Phase 3's fifth load point. Zero plugins installed means zero objects
  // instantiated and one FileView watching a path that does not exist — see
  // PluginSurfaces.qml for why this process, and not a bar, is the host.
  AtiPlugins.PluginSurfaces { }

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

  // Third resident view. Same reasoning as the clipboard one directly above:
  // this is an editable FORM (two text fields you correct, a language
  // dropdown that re-runs the lookup), and the generic dmenu payload has no
  // way to render that at all -- its rows are glyph+label+subtext with
  // nowhere to type. Resident for the same reason the whole config is: a
  // fresh `qs -p` per keypress is a QML compile, and this one is summoned
  // from a word you just highlighted, where several hundred milliseconds is
  // the difference between a tool and an interruption.
  TranslatePlugin.Translate {
    id: translate
  }

  // The selection badge -- the little square beside the pointer. Separate
  // from the popup above on purpose: it is a different window with a
  // different layer policy (it must NEVER hold the keyboard, see its own
  // header), and folding it into the popup would mean one component with
  // two contradictory focus modes.
  TranslatePlugin.TranslateBadge {
    id: translateBadge
    onRequested: (word) => translate.open(word)
  }

  // The badge's payload, same file route as the two above and for the same
  // reason. Three tab-separated fields: word, cursor x, cursor y -- tabs
  // rather than spaces because the word can and does contain spaces.
  FileView {
    id: badgePayloadFile
    printErrors: false
    onLoaded: {
      const parts = text().replace(/\n+$/, "").split("\t");
      if (parts.length < 3) return;
      translateBadge.show(parts[0], parseInt(parts[1], 10) || 0, parseInt(parts[2], 10) || 0);
    }
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

  // The same trick for the translate popup's initial word -- see the
  // `openFile` handler below. Trailing newline trimmed: the writer is a
  // shell script and every convenient way to write a file from one adds it,
  // which would otherwise be looked up as part of the word.
  FileView {
    id: translatePayloadFile
    printErrors: false
    onLoaded: translate.open(text().replace(/\n+$/, ""))
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
    target: "translate"

    // `open` takes the word as its argument rather than reading the
    // selection itself: Quickshell IPC args are whitespace-split, so a
    // multi-word phrase would arrive shredded. ati-translate-popup reads the
    // selection and passes it base64-encoded for exactly that reason -- see
    // that script, and `openEncoded` below.
    function open(word: string): void { translate.open(word || ""); }

    // A FILE PATH, not the text and not base64.
    //
    // base64 was the first attempt, decoded with atob() -- which does not
    // exist in QML's JS engine. It is a browser API, not an ECMAScript one,
    // so the call threw, the catch swallowed it, and the popup opened with
    // an empty field every time while `open` with a single bare word worked
    // fine. Confirmed live before this was changed.
    //
    // The file-payload route is the one this shell already established for
    // exactly this problem, three handlers up: see dmenuPayloadFile and its
    // comment on why IPC's whitespace-splitting makes a path the only thing
    // that reliably crosses. ati-translate-popup writes the selection to
    // this file; nothing else reads it.
    function openFile(payloadPath: string): void {
      translatePayloadFile.path = payloadPath;
      translatePayloadFile.reload();
    }

    function close(): void { translate.close(); }
    function toggle(): void { translate.toggle(); }
    function status(): string { return translate.status(); }

    // Called by ati-translate-watch every time the PRIMARY selection
    // changes. Shows the badge; does NOT translate anything and does not
    // open the popup -- selecting text is something you do constantly and
    // must stay free.
    function badge(payloadPath: string): void {
      badgePayloadFile.path = payloadPath;
      badgePayloadFile.reload();
    }

    function hideBadge(): void { translateBadge.hide(); }
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
