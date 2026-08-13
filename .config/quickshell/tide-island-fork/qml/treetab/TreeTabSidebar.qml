pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

import "../common"
import "../common/Motion.js" as Motion

//
// FORK — new file. qtile's TreeTab panel, as a layer-shell sidebar.
//
// ============================ WHY ============================
//
// hypr/scripts/layout-cycle.sh ports qtile's three layouts, and its own
// header says of the third: "a group, groupbar ON — the same stack, with
// the window list drawn, which is the only thing TreeTab adds to Max".
// That sentence is true about the INFORMATION and wrong about the SHAPE,
// and the shape is the whole of what TreeTab is.
//
// Hyprland's groupbar is a horizontal strip of tabs across the top of the
// window. qtile's TreeTab is a 180 px VERTICAL PANEL down the left edge,
// taken out of the tiling area, listing every window in the stack under
// section headings. Read from the authority rather than from memory —
// /usr/lib/python3.14/site-packages/libqtile/layout/tree.py, qtile 0.36:
//
//   * TreeTab.layout() does `screen_rect.hsplit(self.panel_width)` and
//     lays the windows out in the REMAINDER. The panel is not an overlay;
//     it is subtracted from the workspace. (tree.py:718-724)
//   * _create_panel() makes an internal window and calls
//     `keep_below(enable=True)` — it sits under every real window.
//   * Section.draw() rules a 1 px horizontal line in section_fg, writes
//     the section title below it, then draws its children. (tree.py:198)
//   * Window.draw() frames each title in a filled rounded rect, indented
//     by `level * level_shift`, active row in active_bg/active_fg and
//     everything else in inactive_bg/inactive_fg. (tree.py:221)
//   * process_button_click() focuses the window whose row was hit.
//   * A collapsed node's title is PREFIXED with a superscript count of
//     what it is hiding — `add_superscript`, tree.py:63.
//
// None of that is a groupbar with different padding. It is a different
// surface in a different place holding different-shaped information, and
// it is what was asked for.
//
//
// ==================== WHAT qtile's CONFIG ACTUALLY RENDERS ====================
//
// ../qtile/config.py:7332 is the reference and four of its arguments are
// not doing what they look like they are doing. Checked against tree.py's
// `defaults` list and against fontconfig, not assumed:
//
//   font="Ubuntu Bold"      NOT A FONT ON THIS MACHINE. `fc-match "Ubuntu
//                           Bold"` returns NotoSansCJK-Regular.ttc —
//                           fontconfig substitutes a CJK face silently
//                           rather than failing, so the panel the user has
//                           been reading for years is Noto Sans CJK
//                           Regular, not Ubuntu, and not bold. There is
//                           therefore nothing to be faithful TO here; this
//                           file uses Inter Medium, which is the shell's
//                           own textFontFamily and which `fc-match`
//                           resolves to Inter.ttc "Inter" "Medium".
//
//   border_focus/           NOT IN TreeTab.defaults and read nowhere in
//   border_normal           tree.py. They are Layout-base window-border
//                           arguments; TreeTab draws no window borders.
//                           Inert.
//
//   margin_left=8           Same — no `margin_left` in TreeTab.defaults
//                           and no reader in tree.py. Inert. The 8 px the
//                           rows are actually inset by is `padding_left`.
//
//   sections=[ONE, TWO,     THREE OF THESE FOUR ARE ALWAYS EMPTY. A window
//   THREE, DEV]             lands in a named section only via
//                           `win.tree_section` or the `sort_windows`
//                           command, and config.py sets neither; every new
//                           client therefore goes to `def_section`, which
//                           Root.__init__ defines as children[0].
//                           (tree.py:130-157). config.py binds
//                           section_down but not section_up, so a window
//                           can be pushed out of ONE and never brought
//                           back. What the panel renders in daily use is
//                           one populated heading and three bare rules.
//                           See "SECTIONS" below for what is drawn here
//                           instead.
//
//
// ==================== THE GEOMETRY, DERIVED NOT GUESSED ====================
//
// qtile's row box is not `border_width` tall in the way the name suggests.
// TextFrame.draw_fill -> Drawer.rounded_fillrect -> _rounded_rect uses the
// linewidth as an INSET: `delta = radius + linewidth / 2`, and the arc
// centres sit at that delta, so the painted rectangle runs from x + lw/2
// to x + width - lw/2 on every side (drawer.py:96-118). The advance is
// then `framed.height + vspace + border_width` on the UN-inset height
// (tree.py:246). With this config's border_width=8, padding_y=6, vspace=3:
//
//     framed.height = textHeight + 12
//     painted row   = framed.height - 8      = textHeight + 4
//     pitch         = framed.height + 3 + 8  = textHeight + 23
//     visible gap   = pitch - painted        = 19 px
//
// So the rows are short and the air between them is as tall as the rows
// themselves. That is not a mistake being reproduced by accident — it is
// what border_width=8 means here, and it is the panel's rhythm.
//
// The corner radius is `height / 10`, also from _rounded_rect, which on a
// ~19 px row is ~2 px. Nearly square, and deliberately so.
//
// TextLayout is created with ALIGN_CENTER (drawer.py:340) and Window.draw
// sets an explicit `layout.width`, so WINDOW TITLES ARE CENTRED in the
// row. Section.draw calls `reset_width()` first — its own comment says
// "no centering" — so SECTION TITLES ARE LEFT ALIGNED at section_left.
// Both are reproduced; the split is the panel's most recognisable feature
// after the colour.
//
// ---- px() AND font() ARE DELIBERATELY NOT APPLIED ----
//
// Metrics.js exists because the vendored upstream QML was drawn for a
// 2560x1440 screen and this panel is 1366x768, so SCALE=0.92 tightens it.
// qtile's numbers have the opposite provenance: they were tuned BY this
// user ON this 1366x768 screen and are the known-good daily driver.
// Running 180 through px() would return 166 and would be correcting for a
// mismatch that does not exist here. Every literal below is qtile's own,
// unscaled, and named after the argument it came from.
//
//
// ==================== SECTIONS ====================
//
// qtile's four are static config names, three permanently empty (above).
// Copying them would copy three bare rules. Copying only the first would
// leave a heading that says "ONE" about nothing.
//
// The sections here are DERIVED from what the workspace actually contains,
// because in this port the thing that files windows is the Hyprland GROUP:
// layout-cycle.sh's treetab path is `group_all`, and the group is exactly
// "several windows in one tile, one visible at a time" — the stack that
// TreeTab exists to list.
//
//     STACK      one per Hyprland group, in group order. Numbered only if
//                a workspace somehow has more than one; layout-cycle.sh
//                builds a single group, so normally there is one heading.
//     TILED      tiled windows NOT in the group. Transient but real: a new
//                window is tiled beside the group until workspace-layout.sh
//                sees `openwindow` and re-applies. Having it named is how
//                you can see that happening.
//     FLOATING   floating windows, which the stack never contained and
//                which are visible whatever the stack is showing.
//
// Empty sections are omitted, which is the one place this deliberately
// does NOT follow qtile: qtile's are declared so it draws them empty; ours
// are derived, and a derived heading over nothing is noise.
//
//
// ==================== NO INDENTATION, AND THAT IS FAITHFUL ====================
//
// `level_shift` and the tree itself come from `move_left`/`move_right`,
// which REPARENT a node under its sibling (tree.py:580-589, 663-673).
// Hyprland has no such relation — `moveintogroup` appends to a flat list
// and there is no dispatcher that makes window B a child of window A. So
// every row here is at level 0.
//
// That is also what qtile looks like until you press those keys. Its own
// docstring: "Initially the panel looks like flat lists inside its
// section, and looks like trees if some of the windows are moved left or
// right." The flat list is the default state, not a degraded one.
//
// What IS ported is the other half of the tree behaviour: a section can be
// COLLAPSED by clicking its heading, and a collapsed heading carries the
// superscript count of what it is hiding — `add_superscript`, using the
// same U+2070/U+00B9/U+00B2/U+00B3/U+2074.. characters qtile's
// `to_superscript` table uses. Coverage checked with `fc-list :charset=`
// rather than assumed: Inter has all ten, so none of them arrives by
// silent fontconfig substitution.
//
//
// ==================== THE CONTRAST BUG THAT IS NOT PORTED ====================
//
// config.py sets `inactive_fg=colors[0]` on `inactive_bg=colors[3]` —
// the BACKGROUND slot used as ink on the RED slot. Measured over the
// palettes this shell ships: gruvbox 4.29:1, nord 3.05:1, both under the
// 4.5:1 floor. A faithful port would inherit an unreadable window list,
// and it would be unreadable in the silent way this tree keeps paying for,
// because wrong-contrast text still renders.
//
// The FILL is kept — `IslandTheme.red` is colors[3] and the wall of red
// rows with one bright active row is the look that was asked for. The INK
// is solved instead of copied: `IslandTheme.inkOn()` picks black or white
// against the fill's own luminance, which is the same function that has
// been deciding `accentInk` for every accent fill in this shell.
// active_bg=colors[8]/active_fg=colors[2] needs no such rescue — a dark
// ink on the bright signature colour is exactly accent/accentInk — so
// that pair IS ported, by role rather than by slot number.
//
// section_fg=colors[7] is the palette's purple, and IslandTheme had no
// legible form of it: success/warning/danger/info cover green, yellow,
// red and blue, and purple was the one slot with no solved role. Added
// there as `purpleText` rather than solved locally, because a colour that
// has to be legible on the surface is exactly what that file is for.
//
//
// ==================== SPACE, AND WHY THE ZONE ANIMATES ====================
//
// qtile takes panel_width out of the tiling area. A layer-shell surface
// does the same with `exclusiveZone` — but the layout here is PER
// WORKSPACE (layout-cycle.sh keeps one state file each) while an exclusive
// zone is per MONITOR. A zone that stayed at 180 would cost every other
// workspace 180 px for a panel that is not on it.
//
// So the zone follows `revealProgress`, which is 0 unless this monitor's
// current workspace is in treetab AND has something to list. It is
// ANIMATED, on the same critically damped curve and the same asymmetric
// 140/morph timing DynamicIslandWindow.qml already uses for its own zone,
// for the reason recorded there: the zone is a compositor-side
// reservation that the eye does not track, and it must not fight the
// motion it is causing. Measured on a headless output — the reflow of a
// 1346 px window down to 1166 and back is Hyprland's own window animation
// either way; with an instant zone the panel is simply gone one frame
// before the windows have finished moving into its space, which reads as a
// gap opening at the left edge. The content slides with the zone so the
// panel leaves rather than vanishes.
//
// `rowCount > 0` in the gate is not defensive tidying: an empty treetab
// workspace with a 180 px reservation is 13% of a 1366 px screen given to
// a heading-less blank strip.
//
//
// ==================== WHY Bottom AND NOT Top ====================
//
// qtile's panel is `keep_below(enable=True)`. Bottom is the layer with
// that meaning: above the wallpaper, below every window. The exclusive
// zone is what keeps tiled windows off it, so it is never covered in
// normal use; a floating window CAN cover it, and so could it in qtile.
// Top would put the sidebar over floating dialogs, which is a change, not
// a port.
//
// ==================== ONE MONITOR'S WORTH OF STATE ====================
//
// $XDG_RUNTIME_DIR/hypr-layouts/current holds the layout of the FOCUSED
// workspace — layout-cycle.sh rewrites it on every switch, and it is one
// value, not one per monitor. So this surface draws only on the focused
// monitor. On the one-output machine this is written for that is always
// true; on two it means the sidebar follows focus rather than claiming to
// know a layout it has not been told. The per-workspace files next to
// `current` could support a real per-monitor answer, at the cost of
// restating layout-cycle.sh's `default_for` table in QML for workspaces
// that have not been visited yet — a second copy of a policy, which is how
// this tree has produced silent disagreements before.
//
PanelWindow {
    id: root

    // The one live `hyprctl clients` feed. Passed in rather than owned,
    // because shell.qml only constructs it while a treetab workspace is
    // focused — see the Loader there. May be null.
    property var hyprlandData: null
    property bool layoutIsTreeTab: false
    property string outputName: ""

    // ---- qtile's own numbers, from config.py:7332 ----
    readonly property int panelWidth: 180        // panel_width
    readonly property int padLeftPx: 8           // padding_left
    readonly property int padXPx: 5              // padding_x
    readonly property int padYPx: 6              // padding_y
    readonly property int borderWidthPx: 8       // border_width
    readonly property int vspacePx: 3            // vspace
    readonly property int sectionTopPx: 15       // section_top
    readonly property int sectionBottomPx: 15    // section_bottom
    readonly property int sectionPaddingPx: 4    // section_padding (tree.py default)
    readonly property int sectionLeftPx: 4       // section_left (tree.py default)
    readonly property int rowFontPx: 11          // fontsize
    readonly property int sectionFontPx: 10      // section_fontsize

    // The derivations from "THE GEOMETRY" above, in one place so the
    // arithmetic is checkable against tree.py rather than re-guessed.
    readonly property int rowBoxHeight: Math.ceil(rowFontMetrics.height) + 2 * root.padYPx
    readonly property int rowPaintedHeight: root.rowBoxHeight - root.borderWidthPx
    readonly property int rowPitch: root.rowBoxHeight + root.vspacePx + root.borderWidthPx
    readonly property int rowInset: Math.round(root.borderWidthPx / 2)

    // ---------------------------------------------------------------
    //  Which workspace this surface is describing
    // ---------------------------------------------------------------

    readonly property var monitorInfo: {
        const data = root.hyprlandData;
        if (!data || !data.monitors || root.outputName === "")
            return null;

        const list = data.monitors;
        for (let index = 0; index < list.length; index++) {
            if (list[index] && String(list[index].name) === root.outputName)
                return list[index];
        }

        return null;
    }

    readonly property bool monitorFocused:
        root.monitorInfo ? root.monitorInfo.focused === true : false

    readonly property string workspaceName:
        (root.monitorInfo && root.monitorInfo.activeWorkspace)
            ? String(root.monitorInfo.activeWorkspace.name) : ""

    // ---------------------------------------------------------------
    //  Collapse state — qtile's TreeNode.expanded, kept per section key
    // ---------------------------------------------------------------
    //
    // Replaced wholesale rather than mutated: a `var` holding an object
    // does not notify on in-place edits, so a mutation would collapse the
    // section in the model and never repaint the panel.
    property var collapsedSections: ({})

    function toggleSection(key) {
        const next = {};
        for (const existing in root.collapsedSections)
            next[existing] = root.collapsedSections[existing];
        next[key] = !next[key];
        root.collapsedSections = next;
    }

    // qtile's to_superscript table, same characters: U+2070, U+00B9,
    // U+00B2, U+00B3, then U+2074..U+2079. Note that 1, 2 and 3 are the
    // Latin-1 forms and NOT U+2071-2073, which are a letter and two
    // unassigned code points — copying the range naively would print tofu
    // for exactly the counts a window list most often has.
    readonly property string superscriptDigits: "⁰¹²³⁴⁵⁶⁷⁸⁹"

    function superscript(value) {
        const digits = String(Math.max(0, Math.round(value)));
        let out = "";
        for (let index = 0; index < digits.length; index++)
            out += root.superscriptDigits.charAt(Number(digits.charAt(index)));
        return out;
    }

    // ---------------------------------------------------------------
    //  The model
    // ---------------------------------------------------------------

    function clientTitle(client) {
        const title = String(client.title || "").trim();
        if (title !== "")
            return title;

        // qtile draws `window.name`, which is never empty for a mapped
        // client. Hyprland's can be, briefly, while a toplevel is still
        // setting itself up — and a blank row is a row you cannot click
        // with any confidence about what you are clicking.
        return String(client.class || "").trim();
    }

    readonly property var sections: {
        const data = root.hyprlandData;
        const workspace = root.workspaceName;
        if (!data || !data.windowList || workspace === "")
            return [];

        const clients = data.windowList;
        const mine = [];
        for (let index = 0; index < clients.length; index++) {
            const client = clients[index];
            if (!client || !client.workspace)
                continue;
            if (String(client.workspace.name) !== workspace)
                continue;
            mine.push(client);
        }

        // Position order, which is what layout-cycle.sh sorts by before it
        // walks the workspace to build the group. Sorting the same way
        // means the panel and the group agree about which window is first
        // instead of both depending on focus history.
        mine.sort(function (a, b) {
            const ax = (a.at && a.at.length > 1) ? a.at[0] : 0;
            const ay = (a.at && a.at.length > 1) ? a.at[1] : 0;
            const bx = (b.at && b.at.length > 1) ? b.at[0] : 0;
            const by = (b.at && b.at.length > 1) ? b.at[1] : 0;
            return ax !== bx ? ax - bx : ay - by;
        });

        // ---- WHICH ROW IS "ACTIVE" ----
        //
        // focusHistoryID 0 is the focused client, machine-wide. When focus
        // is somewhere else entirely — a scratchpad on a special
        // workspace, which this config has five of — no row on this
        // workspace would light up at all, and the panel would stop saying
        // which window is on screen at the moment you most need it to.
        //
        // qtile has the same situation and answers it in TreeTab.blur():
        // "Does not clear current window, will change if new one will be
        // focused." The equivalent here is Hyprland's own `visible` flag,
        // which is true for the group member currently drawn and false for
        // the ones stacked behind it — literally "the window you are
        // looking at". Used only as the fallback, so a focused row always
        // wins.
        let focusedHere = false;
        for (let index = 0; index < mine.length; index++) {
            if (mine[index].focusHistoryID === 0) {
                focusedHere = true;
                break;
            }
        }

        function isActive(client) {
            if (focusedHere)
                return client.focusHistoryID === 0;
            return client.visible === true
                && client.grouped !== undefined && client.grouped.length > 0;
        }

        const groupsByKey = {};
        const groupOrder = [];
        const looseTiled = [];
        const floating = [];

        for (let index = 0; index < mine.length; index++) {
            const client = mine[index];
            if (client.floating === true) {
                floating.push(client);
                continue;
            }

            const members = client.grouped ? client.grouped : [];
            if (members.length === 0) {
                looseTiled.push(client);
                continue;
            }

            const key = String(members[0]).toLowerCase();
            if (!groupsByKey[key]) {
                groupsByKey[key] = { order: members, byAddress: {} };
                groupOrder.push(key);
            }
            groupsByKey[key].byAddress[String(client.address).toLowerCase()] = client;
        }

        function toRow(client) {
            return {
                address: String(client.address || ""),
                label: root.clientTitle(client),
                isActive: isActive(client)
            };
        }

        const built = [];

        function push(key, title, clients2) {
            if (clients2.length === 0)
                return;

            const collapsed = root.collapsedSections[key] === true;
            const rows = [];
            if (!collapsed) {
                for (let index = 0; index < clients2.length; index++)
                    rows.push(toRow(clients2[index]));
            }

            built.push({
                key: key,
                // add_superscript: the count is shown only while collapsed,
                // because expanded you can simply see them.
                title: collapsed ? root.superscript(clients2.length) + title : title,
                rows: rows
            });
        }

        for (let index = 0; index < groupOrder.length; index++) {
            const group = groupsByKey[groupOrder[index]];
            // The group's OWN order, not position order: every member of a
            // Hyprland group reports the same `at`, so sorting them by
            // geometry is sorting by nothing. `grouped` is the tab order
            // the groupbar was drawing, which is the order the user
            // already knows.
            const ordered = [];
            for (let member = 0; member < group.order.length; member++) {
                const client = group.byAddress[String(group.order[member]).toLowerCase()];
                if (client)
                    ordered.push(client);
            }
            push("group:" + groupOrder[index],
                 groupOrder.length > 1 ? "STACK " + (index + 1) : "STACK",
                 ordered);
        }

        push("tiled", "TILED", looseTiled);
        push("floating", "FLOATING", floating);

        return built;
    }

    // Counted from the clients, not from `sections`, so collapsing every
    // section does not retract the panel out from under the heading you
    // just clicked.
    readonly property int rowCount: {
        const data = root.hyprlandData;
        const workspace = root.workspaceName;
        if (!data || !data.windowList || workspace === "")
            return 0;

        const clients = data.windowList;
        let total = 0;
        for (let index = 0; index < clients.length; index++) {
            const client = clients[index];
            if (client && client.workspace && String(client.workspace.name) === workspace)
                total++;
        }
        return total;
    }

    // ---------------------------------------------------------------
    //  The surface
    // ---------------------------------------------------------------

    readonly property bool wanted:
        root.layoutIsTreeTab && root.monitorFocused && root.rowCount > 0

    // NOT readonly. A Behavior writes the property it animates, and
    // attaching one to a readonly property takes the whole config down —
    // the failure is a load error, not a dead animation.
    property real revealProgress: root.wanted ? 1 : 0

    Behavior on revealProgress {
        NumberAnimation {
            duration: root.wanted ? 140 : Motion.morphDuration()
            easing.type: Easing.BezierSpline
            // The critically damped curve, not the spring. `spring()`
            // overshoots past 1 by design, and this value is multiplied
            // into a compositor-side reservation — an overshoot would
            // reserve more than the panel is wide and snap back.
            easing.bezierCurve: Motion.fade()
        }
    }

    anchors.left: true
    anchors.top: true
    anchors.bottom: true
    implicitWidth: root.panelWidth
    exclusiveZone: Math.round(root.panelWidth * root.revealProgress)

    color: IslandTheme.surface

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-treetab"

    visible: root.wanted || root.revealProgress > 0.001

    // Font metrics for the two type sizes, so the row pitch is derived
    // from the face that is actually rendering rather than from a guess at
    // what 11 px of Inter is tall.
    FontMetrics {
        id: rowFontMetrics
        font.family: "Inter Medium"
        font.pixelSize: root.rowFontPx
    }

    HyprlandDispatch { id: dispatcher }

    Item {
        id: slider
        anchors.fill: parent
        // Slides out with the zone rather than blinking off, so the panel
        // and the windows filling its space are one movement.
        x: -(1 - root.revealProgress) * root.panelWidth

        Flickable {
            id: sectionFlick

            anchors.fill: parent
            contentWidth: width
            contentHeight: sectionColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // FORK: P1-3. This one had no `id` at all, which is itself the
            // sign — nothing outside referred to it because nothing outside
            // could say anything about it, including that it scrolls.
            ScrollBar.vertical: IslandScrollBar { view: sectionFlick }
            // Only scrollable when it has to be: a panel that rubber-bands
            // under the pointer while you are aiming at a row is a panel
            // that loses the click.
            interactive: contentHeight > height

            Column {
                id: sectionColumn
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.sections

                    Column {
                        id: sectionItem

                        required property var modelData

                        width: sectionColumn.width
                        spacing: 0

                        // Section.draw's first act: a 1 px rule across the
                        // full panel width in section_fg, at the section's
                        // own top. The first section's rule therefore sits
                        // on the panel's top edge — `self._tree.draw(self,
                        // 0)` starts at y=0 — which is why there is no
                        // leading margin here.
                        Rectangle {
                            width: sectionItem.width
                            height: 1
                            color: IslandTheme.purpleText
                        }

                        Item {
                            width: sectionItem.width
                            // section_top above the label, section_padding
                            // below it, both from Section.draw's
                            // `top += layout.height + section_top + section_padding`.
                            height: root.sectionTopPx
                                + Math.ceil(sectionFontMetrics.height)
                                + root.sectionPaddingPx

                            FontMetrics {
                                id: sectionFontMetrics
                                font.family: "Inter Medium"
                                font.pixelSize: root.sectionFontPx
                            }

                            Text {
                                x: root.sectionLeftPx
                                y: root.sectionTopPx
                                width: sectionItem.width - 2 * root.sectionLeftPx
                                // reset_width() — "no centering". The
                                // section heading is the one thing in this
                                // panel that is left aligned.
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                                text: sectionItem.modelData.title
                                color: IslandTheme.purpleText
                                font.family: "Inter Medium"
                                font.pixelSize: root.sectionFontPx
                                // Not qtile's, and the only typographic
                                // liberty taken: at 10 px a short uppercase
                                // word set solid reads as a smudge, and
                                // this heading has to be distinguishable
                                // from a row title at a glance rather than
                                // by colour alone.
                                font.letterSpacing: 1
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                // collapse_branch / expand_branch, moved
                                // from a keybind to the heading itself:
                                // this surface has no keyboard focus to
                                // press a key into (see keyboardFocus
                                // above), and the heading is the only part
                                // of a section that is not a window.
                                onClicked: root.toggleSection(sectionItem.modelData.key)
                            }
                        }

                        Repeater {
                            model: sectionItem.modelData.rows

                            Item {
                                id: rowItem

                                required property var modelData

                                width: sectionItem.width
                                height: root.rowPitch

                                readonly property color fillColor: rowItem.modelData.isActive
                                    ? IslandTheme.accent
                                    : IslandTheme.red

                                Rectangle {
                                    id: rowFill

                                    // padding_left + level * level_shift,
                                    // plus draw_fill's border_width/2
                                    // inset. Level is always 0 — see "NO
                                    // INDENTATION" in the header.
                                    x: root.padLeftPx + root.rowInset
                                    y: root.rowInset
                                    width: sectionItem.width - x
                                    height: root.rowPaintedHeight
                                    // _rounded_rect's corner_radius is
                                    // height / 10, which is the reason
                                    // these are very nearly square.
                                    radius: Math.round(root.rowPaintedHeight / 10)

                                    color: rowMouse.containsMouse
                                        ? IslandTheme.mix(rowItem.fillColor, IslandTheme.ink, 0.14)
                                        : rowItem.fillColor

                                    Behavior on color {
                                        ColorAnimation { duration: IslandTheme.durationFast }
                                    }

                                    Text {
                                        anchors.fill: parent
                                        anchors.leftMargin: root.padXPx
                                        anchors.rightMargin: root.padXPx
                                        // ALIGN_CENTER, and Window.draw
                                        // sets an explicit layout width so
                                        // it actually takes effect. This
                                        // is the panel's signature after
                                        // the colour.
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        text: rowItem.modelData.label
                                        // NOT config.py's active_fg /
                                        // inactive_fg. See "THE CONTRAST
                                        // BUG THAT IS NOT PORTED" — its
                                        // inactive pair measures 4.29:1 on
                                        // gruvbox and 3.05:1 on nord.
                                        color: IslandTheme.inkOn(rowItem.fillColor)
                                        font.family: "Inter Medium"
                                        font.pixelSize: root.rowFontPx
                                    }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: rowFill
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // process_button_click ->
                                    // group.focus(node.window). On a
                                    // grouped window `focuswindow` also
                                    // makes it the visible member, which
                                    // is what makes this panel a tab
                                    // strip rather than a list.
                                    onClicked: dispatcher.focusWindow(rowItem.modelData.address)
                                }
                            }
                        }

                        // section_bottom.
                        Item {
                            width: sectionItem.width
                            height: root.sectionBottomPx
                        }
                    }
                }
            }
        }
    }
}
